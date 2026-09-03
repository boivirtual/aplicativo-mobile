import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'connectivity_service.dart';
import '../data/daos/animal_cache_dao.dart';

/// Baixa o cadastro de animais para o cache local (animais_cache),
/// permitindo que autocomplete e ficha do animal funcionem offline depois
/// da primeira vez que houver sinal.
///
/// Desde a mudança que parou de filtrar a exportação por fazenda (ver
/// AnimalDao::getAnimaisAtivosPorFazendaExport no servidor), esse download
/// não é mais "por fazenda do array do usuário" — é um download só, de
/// TODOS os animais ativos do banco (bd) do cliente (mais as fêmeas
/// inativas que ainda têm filho ativo), independente de quais fazendas o
/// usuário tem no array local. Isso é necessário porque mãe/filho podem
/// estar em fazendas às quais o usuário não tem acesso direto. As pesagens
/// (lista de pendentes, "a pesar" etc.) continuam restritas às fazendas do
/// array do usuário — essa restrição é outra, não mexe aqui.
class AnimalCacheService {
  AnimalCacheService._();
  static final AnimalCacheService instance = AnimalCacheService._();

  final Set<String> _emAndamento = {};

  /// Bancos (bd) cujo cadastro já foi baixado com sucesso NESTA sessão do
  /// app — sem isso, toda vez que a tela de pesagem era reaberta (ex:
  /// voltar do formulário, ou o pull-to-refresh da lista de pendentes) o
  /// cadastro inteiro era baixado de novo, mostrando "Baixando cadastro de
  /// animais..." repetidamente mesmo segundos depois do último download.
  /// Baixa de novo só quando o app é reaberto (processo novo) — o cadastro
  /// não muda tão rápido a ponto de precisar disso a cada vez que o usuário
  /// troca de tela.
  final Set<String> _sincronizadasNestaSessao = {};

  /// true enquanto há pelo menos um download de cadastro de animais em
  /// andamento — usado pela tela para mostrar "Baixando dados...".
  final ValueNotifier<bool> baixando = ValueNotifier(false);

  /// Baixa o cadastro completo de animais do banco (bd) do cliente — não
  /// recebe mais fazenda: a exportação em si não filtra por fazenda (ver
  /// classe acima). Único ponto de entrada agora; substitui as antigas
  /// garantirCacheDaFazenda/garantirCacheDeTodasFazendas.
  ///
  /// [forcar]: ignora a trava de "já baixado nesta sessão" — usado quando o
  /// app volta de segundo plano depois de tempo parado (ver MainContainer),
  /// já que nesse caso o processo nunca reiniciou e a trava continuaria
  /// impedindo um novo download mesmo fazendo sentido atualizar de novo.
  Future<void> garantirCacheCompleto(String? bd, {bool forcar = false}) async {
    if (bd == null || bd.isEmpty) return;
    if (forcar) _sincronizadasNestaSessao.remove(bd);
    if (_sincronizadasNestaSessao.contains(bd)) return;
    if (_emAndamento.contains(bd)) return;
    if (!ConnectivityService.instance.temInternetReal) return;

    _emAndamento.add(bd);
    baixando.value = true;
    try {
      // Timeout maior que as chamadas interativas: isso baixa o cadastro
      // inteiro do cliente (pode ser milhares de animais) — numa internet
      // lenta mas funcionando, vale esperar mais antes de desistir.
      final response = await http
          .get(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/animal/list_fazenda_completo.php?local=0&bd=$bd",
            ),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final animais = (data['animais'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          await AnimalCacheDao.instance.salvarLote(animais);
          // Só marca como "feito nesta sessão" em caso de sucesso de
          // verdade — se falhar (sem internet, timeout, erro do servidor),
          // a próxima chamada tenta de novo em vez de ficar presa sem
          // cache algum até o app reiniciar.
          _sincronizadasNestaSessao.add(bd);
        }
      }
    } catch (_) {
      // best-effort — não deve travar nenhuma tela se isso falhar
    } finally {
      _emAndamento.remove(bd);
      if (_emAndamento.isEmpty) baixando.value = false;
    }
  }
}
