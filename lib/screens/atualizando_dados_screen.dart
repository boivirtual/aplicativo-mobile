import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/animal_cache_service.dart';
import '../services/connectivity_service.dart';
import '../repositories/pesagem_repository.dart';

/// Tela de transição mostrada ao logar ou reabrir o app já logado — atualiza
/// o cadastro de animais e as pesagens ANTES de liberar o resto do app.
///
/// Antes, o vaqueiro já tinha acesso à digitação da pesagem antes desses
/// dados terminarem de baixar em segundo plano — se o modo avião fosse
/// ligado nesse meio-tempo (ex: saindo da fazenda pro curral rápido demais),
/// o cadastro de animais podia ficar vazio, sem chance de consultar offline
/// (bug real). Agora esse download acontece aqui, com a tela travada, antes
/// de liberar qualquer outra parte do app.
///
/// Com internet ausente, pula direto (não tem o que atualizar). Com internet
/// presente mas lenta, um tempo limite evita virar uma trava nova — libera
/// o app mesmo assim com o que já tiver, deixando o resto terminar sozinho.
class AtualizandoDadosScreen extends StatefulWidget {
  const AtualizandoDadosScreen({super.key});

  @override
  State<AtualizandoDadosScreen> createState() =>
      _AtualizandoDadosScreenState();
}

class _AtualizandoDadosScreenState extends State<AtualizandoDadosScreen> {
  static const _tempoLimite = Duration(seconds: 18);

  @override
  void initState() {
    super.initState();
    _atualizarEContinuar();
  }

  Future<void> _atualizarEContinuar() async {
    try {
      // Checagem fresca — o nível de conectividade "de fábrica" do serviço
      // é otimista até a primeira verificação real terminar, então não dá
      // pra confiar no valor já conhecido logo na abertura do app.
      await ConnectivityService.instance.verificarAgora();
      if (ConnectivityService.instance.temInternetReal) {
        final prefs = await SharedPreferences.getInstance();
        final fazendasJson = prefs.getString('userFazendas');
        final cnpj = prefs.getString('userCNPJ');
        if (fazendasJson != null) {
          final List<dynamic> fazendas = json.decode(fazendasJson);
          await _atualizarTudo(cnpj, fazendas).timeout(_tempoLimite);
        }
      }
    } catch (_) {
      // Sem internet, timeout, ou qualquer erro — segue pro app mesmo
      // assim, com o que já estiver em cache local. O que não terminou
      // continua rodando sozinho em segundo plano (ver garantirCacheDaFazenda
      // e garantirItensDasPendentes, que não são cancelados pelo timeout).
    } finally {
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    }
  }

  Future<void> _atualizarTudo(String? cnpj, List<dynamic> fazendas) async {
    final idsFazendas = fazendas
        .map((f) => int.tryParse((f as Map)['id'].toString()) ?? 0)
        .toList();

    // Precisa vir primeiro: popula o cache local de pesagens, que
    // garantirItensDasPendentes usa pra saber quais pesagens ainda
    // precisam ter os itens baixados.
    await PesagemRepository.instance.listarPendentes(
      bd: cnpj,
      fazendas: idsFazendas,
    );

    await Future.wait([
      AnimalCacheService.instance.garantirCacheDeTodasFazendas(
        fazendas,
        cnpj,
      ),
      PesagemRepository.instance.garantirItensDasPendentes(cnpj),
      PesagemRepository.instance.listarFinalizadas(
        bd: cnpj,
        fazendas: idsFazendas,
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF18385F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 5),
            SizedBox(height: 25),
            Text(
              "Aguarde! Atualizando os dados",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
