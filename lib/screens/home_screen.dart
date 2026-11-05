import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/recursos.dart';
import '../services/connectivity_service.dart';
import '../services/resumo_diario_service.dart';

class HomeScreen extends StatelessWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    const Color azulBarra = Color(0xFF18385F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Bem-vindo ao Boi Virtual!",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: azulBarra,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Selecione uma funcionalidade:",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // Linha 1: Mapa de Gado — largura total
              _buildWideCard(
                "Mapa de Gado",
                'home.png',
                () => onNavigate?.call(0),
                // azul bem claro para destacar dos outros
                fundo: const Color(0xFFE3F2FD),
              ),

              const SizedBox(height: 15),

              // Linhas 2 e 3: Pesagem e Chuva; Agenda e Resumo Diário
              // (mesmos índices do rodapé, em main_container.dart)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.1,
                children: [
                  _buildMenuCard("Pesagem", 'pesagem.png', 1, onNavigate),
                  _buildMenuCard("Chuva", 'chuva.png', 2, onNavigate),
                  // fora desta versão (ver config/recursos.dart): clareado
                  // e sem abrir
                  Opacity(
                    opacity: agendaLiberada ? 1 : 0.45,
                    child: _buildMenuCard(
                      "Agenda",
                      'agenda.png',
                      3,
                      agendaLiberada ? onNavigate : null,
                    ),
                  ),
                  // fora desta versão (ver config/recursos.dart): clareado
                  // e sem abrir
                  Opacity(
                    opacity: resumoDiarioLiberado ? 1 : 0.45,
                    child: resumoDiarioLiberado
                        ? _CardResumoDiario(onNavigate: onNavigate)
                        : _buildMenuCard(
                            "Resumo Diário",
                            'farmer.png',
                            4,
                            null,
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Quadro LARGO (Mapa de Gado) - mesmo padrão dos outros
  Widget _buildWideCard(
    String title,
    String img,
    VoidCallback onTap, {
    Color fundo = Colors.white,
  }) {
    const Color azulIcone = Color(0xFF228cb9);

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double alturaCalculada = (constraints.maxWidth / 2) / 1.1;

          return Container(
            width: double.infinity,
            height: alturaCalculada,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: fundo,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // ÍCONE AJUSTADO (de 50 para 32 para igualar aos outros)
                Align(
                  alignment: Alignment.topLeft,
                  child: Image.asset(
                    'assets/images/$img',
                    width: 32,
                    height: 32,
                    color: azulIcone,
                  ),
                ),
                // FONTE AJUSTADA (de 18 para 14 para igualar aos outros)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18385F),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Quadros MENORES. fundo/cor/meio: card em alerta (ex.: Resumo Diário
  // com o dia anterior sem resumo) — fundo, cor do ícone e do nome e um
  // aviso no meio do card.
  static Widget _buildMenuCard(
    String title,
    String img,
    int index,
    Function(int)? tap, {
    Color fundo = Colors.white,
    Color? cor,
    String? meio,
  }) {
    const Color azulIcone = Color(0xFF228cb9);

    return GestureDetector(
      onTap: () => tap?.call(index),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: fundo,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(
              'assets/images/$img',
              width: 32,
              height: 32,
              color: cor ?? azulIcone,
            ),
            if (meio != null)
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  meio,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w900,
                    color: cor,
                  ),
                ),
              ),
            // sempre em uma linha: nos cards menores (3 por linha) a fonte
            // encolhe um pouco em vez de quebrar o nome
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: cor ?? const Color(0xFF18385F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Card do Resumo Diário na Home. Com UMA fazenda só, confere no servidor
/// (só com internet boa, sem avisos) se o dia anterior ficou sem resumo e
/// sem folga — mesma conferência da tela inicial do Resumo
/// (ResumoDiarioService.diaAnteriorPendente). Pendente: card vermelho com
/// "Falta Resumo dd/mm/aaaa". Com mais de uma fazenda, card normal. A Home
/// é montada de novo cada vez que volta para ela, então a conferência se
/// refaz (ex.: depois de registrar o resumo ou a folga).
class _CardResumoDiario extends StatefulWidget {
  final Function(int)? onNavigate;
  const _CardResumoDiario({this.onNavigate});

  @override
  State<_CardResumoDiario> createState() => _CardResumoDiarioState();
}

class _CardResumoDiarioState extends State<_CardResumoDiario> {
  /// Dia anterior sem resumo nem folga (null = em dia ou não conferido).
  DateTime? _faltaResumo;

  @override
  void initState() {
    super.initState();
    _conferir();
  }

  Future<void> _conferir() async {
    final prefs = await SharedPreferences.getInstance();
    final bd = prefs.getString('userCNPJ');
    final fazendasJson = prefs.getString('userFazendas');
    if (bd == null || fazendasJson == null) return;
    final fazendas = json.decode(fazendasJson);
    if (fazendas is! List || fazendas.length != 1) return;
    // na hora (logo depois do login a última medição pode não existir)
    final nivel = await ConnectivityService.instance.verificarAgora();
    if (nivel != NivelConexao.internetOk) return;
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final r = await ResumoDiarioService.instance.diaAnteriorPendente(
      bd,
      (fazendas[0] as Map)['id'].toString(),
      hoje,
    );
    if (!mounted || r == null || !r.pendente) return;
    setState(() => _faltaResumo = hoje.subtract(const Duration(days: 1)));
  }

  @override
  Widget build(BuildContext context) {
    final dia = _faltaResumo;
    if (dia == null) {
      return HomeScreen._buildMenuCard(
        "Resumo Diário",
        'farmer.png',
        4,
        widget.onNavigate,
      );
    }
    final data =
        '${dia.day.toString().padLeft(2, '0')}/'
        '${dia.month.toString().padLeft(2, '0')}/${dia.year}';
    return HomeScreen._buildMenuCard(
      "Resumo Diário",
      'farmer.png',
      4,
      widget.onNavigate,
      // vermelho bem claro; ícone e textos em vermelho escuro
      fundo: const Color(0xFFFFEBEE),
      cor: const Color(0xFFB71C1C),
      meio: 'Falta Resumo $data',
    );
  }
}
