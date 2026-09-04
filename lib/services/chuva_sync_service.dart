import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/api_config.dart';
import '../data/daos/chuva_dao.dart';
import 'connectivity_service.dart';

/// Motor de sincronização da chuva — download do cache local (mesmo papel
/// de AnimalCacheService) e reenvio dos lançamentos feitos offline.
///
/// Deliberadamente uma classe própria, sem tocar em SyncService/OutboxDao
/// (fila usada pela Pesagem, já validada em campo): a chuva tem uma regra
/// de conflito bem mais simples (um registro por dia/fazenda, o mais
/// recente sempre sobrescreve — sem "itens" nem numeração para reconciliar),
/// não precisa da fila genérica, e mantê-la isolada garante que nada aqui
/// pode quebrar a sincronização da pesagem.
class ChuvaSyncService {
  ChuvaSyncService._();
  static final ChuvaSyncService instance = ChuvaSyncService._();

  Timer? _timer;
  StreamSubscription<NivelConexao>? _subConectividade;
  bool _enviando = false;

  /// Liga o reenvio automático: ao voltar internet e, como reforço, a cada
  /// 30s enquanto o app está em primeiro plano (mesmo intervalo do
  /// SyncService da pesagem). Chamado uma vez em main.dart.
  void iniciar() {
    _subConectividade ??= ConnectivityService.instance.status.listen((nivel) {
      if (nivel == NivelConexao.internetOk) {
        _tentarEnviarPendentesDaContaLogada();
      }
    });
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (ConnectivityService.instance.temInternetReal) {
        _tentarEnviarPendentesDaContaLogada();
      }
    });
  }

  Future<void> _tentarEnviarPendentesDaContaLogada() async {
    if (_enviando) return;
    final prefs = await SharedPreferences.getInstance();
    final bd = prefs.getString('userCNPJ');
    if (bd == null || bd.isEmpty) return;
    await enviarPendentes(bd);
  }

  /// Chamado na tela "Atualizando dados", junto com o cadastro de animais —
  /// sobe qualquer lançamento feito offline e depois atualiza o cache local
  /// com o que está no servidor (outros dispositivos, sistema web, etc.).
  Future<void> sincronizarInicial(String? bd, List<int> fazendas) async {
    if (bd == null || bd.isEmpty || fazendas.isEmpty) {
      debugPrint(
        '[ChuvaSync] sincronizarInicial: abortou -> bd=$bd fazendas=$fazendas',
      );
      return;
    }
    if (!ConnectivityService.instance.temInternetReal) {
      debugPrint('[ChuvaSync] sincronizarInicial: sem internet real, abortou');
      return;
    }

    await enviarPendentes(bd);
    await baixar(bd, fazendas);
  }

  Future<void> baixar(String bd, List<int> fazendas) async {
    try {
      debugPrint('[ChuvaSync] baixar: bd=$bd fazendas=$fazendas');
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/chuva/list.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({"bd": bd, "fazendas": fazendas}),
          )
          .timeout(const Duration(seconds: 20));
      debugPrint(
        '[ChuvaSync] baixar: status=${response.statusCode} body=${response.body.substring(0, response.body.length.clamp(0, 500))}',
      );
      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      if (data['success'] == true) {
        final chuvas = (data['chuvas'] as List)
            .map((e) => e as Map<String, dynamic>)
            .toList();
        debugPrint('[ChuvaSync] baixar: ${chuvas.length} registro(s) recebido(s), salvando no cache local');
        await ChuvaDao.instance.salvarLoteDoServidor(bd, chuvas);
      } else {
        debugPrint('[ChuvaSync] baixar: servidor respondeu success=false -> ${data['message']}');
      }
    } catch (e, st) {
      // best-effort — mesmo padrão do AnimalCacheService, não deve travar
      // nenhuma tela se isso falhar — mas loga pra dar pra diagnosticar.
      debugPrint('[ChuvaSync] baixar: falhou -> $e\n$st');
    }
  }

  /// Reenvia todos os lançamentos deste aparelho ainda não confirmados
  /// pelo servidor (bd informado).
  Future<void> enviarPendentes(String bd) async {
    if (_enviando) return;
    _enviando = true;
    try {
      final pendentes = await ChuvaDao.instance.listarPendentes(bd);
      for (final p in pendentes) {
        final fazendaId = p['fazenda_id'] as String;
        final data = p['data'] as String;
        final ok = await enviarUm(
          bd: bd,
          fazendaId: fazendaId,
          data: data,
          volume: (p['volume'] as num).toDouble(),
          usuario: p['usuario'] as String?,
        );
        if (ok) {
          await ChuvaDao.instance.marcarSincronizado(
            bd: bd,
            fazendaId: fazendaId,
            data: data,
          );
        }
      }
    } finally {
      _enviando = false;
    }
  }

  /// Envia um único lançamento — usado tanto pelo reenvio em lote acima
  /// quanto pela tentativa imediata do ChuvaRepository ao gravar com
  /// internet disponível.
  Future<bool> enviarUm({
    required String bd,
    required String fazendaId,
    required String data,
    required double volume,
    String? usuario,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/chuva/create.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              "bd": bd,
              "data_chuva": data,
              "codigo_local_chuva": fazendaId,
              "volume_chuva": volume,
              "user": usuario,
            }),
          )
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200 && response.statusCode != 201) {
        return false;
      }
      final resJson = json.decode(response.body);
      return resJson['error'] == false;
    } catch (_) {
      return false;
    }
  }
}
