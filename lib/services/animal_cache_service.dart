import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'connectivity_service.dart';
import '../data/daos/animal_cache_dao.dart';

/// Baixa o cadastro de animais de uma fazenda para o cache local
/// (animais_cache), permitindo que autocomplete e ficha do animal
/// funcionem offline depois da primeira vez que houver sinal.
class AnimalCacheService {
  AnimalCacheService._();
  static final AnimalCacheService instance = AnimalCacheService._();

  final Set<String> _emAndamento = {};

  /// Fazendas (chave "bd:fazendaId") cujo cadastro já foi baixado com
  /// sucesso NESTA sessão do app — sem isso, toda vez que a tela de
  /// pesagem era reaberta (ex: voltar do formulário, ou o pull-to-refresh
  /// da lista de pendentes) o cadastro inteiro da fazenda era baixado de
  /// novo, mostrando "Baixando cadastro de animais..." repetidamente
  /// mesmo segundos depois do último download. Baixa de novo só quando o
  /// app é reaberto (processo novo) — o cadastro não muda tão rápido a
  /// ponto de precisar disso a cada vez que o usuário troca de tela.
  final Set<String> _sincronizadasNestaSessao = {};

  /// true enquanto há pelo menos um download de cadastro de animais em
  /// andamento — usado pela tela para mostrar "Baixando dados...".
  final ValueNotifier<bool> baixando = ValueNotifier(false);

  Future<void> garantirCacheDaFazenda(
    String fazendaId,
    String? bd, {
    String? nomeFazenda,
  }) async {
    if (fazendaId.isEmpty || bd == null || bd.isEmpty) return;
    final chave = '$bd:$fazendaId';
    if (_sincronizadasNestaSessao.contains(chave)) return;
    if (_emAndamento.contains(chave)) return;
    if (!ConnectivityService.instance.temInternetReal) return;

    _emAndamento.add(chave);
    baixando.value = true;
    try {
      // Timeout maior que as chamadas interativas: isso baixa o cadastro
      // inteiro da fazenda (pode ser centenas/milhares de animais) — numa
      // internet lenta mas funcionando, vale esperar mais antes de desistir.
      final response = await http
          .get(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/animal/list_fazenda_completo.php?local=$fazendaId&bd=$bd",
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final animais = (data['animais'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          await AnimalCacheDao.instance.salvarLote(
            fazendaId,
            animais,
            fazendaNome: nomeFazenda,
          );
          // Só marca como "feito nesta sessão" em caso de sucesso de
          // verdade — se falhar (sem internet, timeout, erro do servidor),
          // a próxima chamada tenta de novo em vez de ficar presa sem
          // cache algum até o app reiniciar.
          _sincronizadasNestaSessao.add(chave);
        }
      }
    } catch (_) {
      // best-effort — não deve travar nenhuma tela se isso falhar
    } finally {
      _emAndamento.remove(chave);
      if (_emAndamento.isEmpty) baixando.value = false;
    }
  }

  /// Garante o cache de TODAS as fazendas que o usuário tem acesso (o array
  /// devolvido no login) — necessário pra "Consultar Mãe" funcionar offline,
  /// já que essa busca não é restrita à fazenda selecionada na tela, é
  /// global entre todos os locais do usuário.
  ///
  /// Baixa todas as fazendas em paralelo (Future.wait) e só resolve quando
  /// TODAS terminarem — quem chama sem dar `await` (ex: PesagemScreen, ao
  /// selecionar uma fazenda) continua funcionando exatamente igual, fire-
  /// -and-forget; quem PRECISA esperar terminar de verdade (ex: a tela de
  /// "Atualizando dados" no login) agora pode.
  Future<void> garantirCacheDeTodasFazendas(
    List<dynamic> fazendas,
    String? bd,
  ) async {
    await Future.wait(
      fazendas.map((f) {
        final mapa = f as Map;
        final id = mapa['id']?.toString() ?? '';
        final nome = mapa['nome']?.toString();
        return garantirCacheDaFazenda(id, bd, nomeFazenda: nome);
      }),
    );
  }
}
