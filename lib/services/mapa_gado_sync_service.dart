import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../data/daos/mapa_gado_dao.dart';
import 'connectivity_service.dart';

/// Sincronização do Mapa de Gado — download do tabuleiro (cache local) e
/// envio da fila de ações feitas no mapa (mover todos os animais, nova
/// descrição do lote). Isolado da fila da pesagem, mesmo motivo do
/// ChuvaSyncService: nada aqui pode atrapalhar a pesagem.
///
/// As ações são enviadas uma por vez, na ordem em que foram feitas (uma
/// nova descrição do lote depende da transferência que veio antes dela).
/// Sem internet ou com falha de rede, para e tenta de novo depois; se o
/// servidor recusar (ex: pasto excluído no sistema web), a ação vai para
/// "erro" e a fila segue — a tela avisa o usuário.
class MapaGadoSyncService {
  MapaGadoSyncService._();
  static final MapaGadoSyncService instance = MapaGadoSyncService._();

  final Uuid _uuid = const Uuid();

  Timer? _timer;
  StreamSubscription<NivelConexao>? _subConectividade;
  bool _baixando = false;
  bool _enviando = false;

  /// Avisa a tela sempre que a fila muda (enviou, falhou, nova ação).
  final ValueNotifier<int> versaoFila = ValueNotifier(0);

  /// Liga o reenvio automático: ao voltar internet e a cada 30s (mesmo
  /// intervalo da chuva e da pesagem). Chamado uma vez em main.dart.
  void iniciar() {
    _subConectividade ??= ConnectivityService.instance.status.listen((nivel) {
      if (nivel == NivelConexao.internetOk) _enviarDaContaLogada();
    });
    _timer ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (ConnectivityService.instance.temInternetReal) _enviarDaContaLogada();
    });
  }

  Future<void> _enviarDaContaLogada() async {
    final prefs = await SharedPreferences.getInstance();
    final bd = prefs.getString('userCNPJ');
    if (bd == null || bd.isEmpty) return;
    await enviarPendentes(bd);
  }

  // ---------------------------------------------------------------------
  // Ações do usuário
  // ---------------------------------------------------------------------

  /// Mover TODOS os animais do pasto [origem] para o [destino]. Aplica no
  /// tabuleiro na hora e envia em segundo plano.
  Future<void> transferirTudo({
    required String bd,
    required int origem,
    required int destino,
    required String? usuario,
  }) async {
    await MapaGadoDao.instance.registrarAcao(
      bd: bd,
      uuid: _uuid.v4(),
      tipo: AcaoMapa.transferirTudo,
      payload: {
        'origem': origem,
        'destino': destino,
        'usuario': usuario ?? '',
        'data_hora': _agora(),
      },
    );
    _depoisDeRegistrar(bd);
  }

  /// Nova Descrição do Lote no [pasto] (já montada, até 6 lotes).
  Future<void> gravarDescricaoLote({
    required String bd,
    required int pasto,
    required String descricaoLote,
    required List<String> lotes,
    required String? usuario,

    /// Edição pelo campo "Descrição do Lote" da tela do pasto (novo_id =
    /// 'N' no web): o pasto continua com o número de lote que já tem.
    bool manterNumero = false,
  }) async {
    final seis = [...lotes.take(6), ...List.filled(6, '')].take(6).toList();
    await MapaGadoDao.instance.registrarAcao(
      bd: bd,
      uuid: _uuid.v4(),
      tipo: AcaoMapa.descricaoLote,
      payload: {
        'pasto': pasto,
        'descricao_lote': descricaoLote,
        'lotes': seis,
        if (manterNumero) 'manter_numero': true,
        'usuario': usuario ?? '',
        'data_hora': _agora(),
      },
    );
    _depoisDeRegistrar(bd);
  }

  void _depoisDeRegistrar(String bd) {
    versaoFila.value++;
    if (ConnectivityService.instance.temInternetReal) {
      // Sem await de propósito: a tela não espera a rede.
      enviarPendentes(bd);
    }
  }

  static String _agora() {
    final d = DateTime.now();
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${d.year}-${dois(d.month)}-${dois(d.day)} '
        '${dois(d.hour)}:${dois(d.minute)}:${dois(d.second)}';
  }

  // ---------------------------------------------------------------------
  // Envio da fila
  // ---------------------------------------------------------------------

  Future<void> enviarPendentes(String bd) async {
    if (_enviando) return;
    _enviando = true;
    try {
      final pendentes = await MapaGadoDao.instance.listarPendentes(bd);
      for (final acao in pendentes) {
        final id = acao['id'] as int;
        final tipo = acao['tipo'] as String;
        final payload =
            json.decode(acao['payload_json'] as String) as Map<String, dynamic>;

        final endpoint = tipo == AcaoMapa.transferirTudo
            ? 'transferir_tudo.php'
            : tipo == AcaoMapa.descricaoLote
            ? 'descricao_lote.php'
            : null;
        if (endpoint == null) {
          await MapaGadoDao.instance.marcarErro(id, 'Ação desconhecida: $tipo');
          continue;
        }

        final _Resposta r = await _post(endpoint, {'bd': bd, ...payload});
        // Rastro no log do aparelho (adb logcat) de cada envio da fila.
        debugPrint(
          '[MapaGadoSync] $tipo #$id -> '
          '${r.sucesso ? 'ok' : (r.redeFalhou ? 'falha de rede' : 'recusado')} '
          '${r.mensagem}',
        );
        if (r.redeFalhou) {
          await MapaGadoDao.instance.contarTentativa(id, r.mensagem);
          break; // tenta de novo depois, mantendo a ordem
        }
        if (r.sucesso) {
          await MapaGadoDao.instance.removerAcao(id);
          // Nova descrição do lote: o servidor devolve o número gerado
          // ("L-0031/26") — grava no cache na hora, sem esperar o próximo
          // download da fazenda.
          if (tipo == AcaoMapa.descricaoLote) {
            final idLote = int.tryParse('${r.dados['id_lote'] ?? ''}') ?? 0;
            final anoLote = int.tryParse('${r.dados['ano_lote'] ?? ''}') ?? 0;
            if (idLote > 0) {
              await MapaGadoDao.instance.atualizarNumeroLote(
                bd: bd,
                pastoId: int.tryParse('${payload['pasto']}') ?? 0,
                descricaoLote: '${payload['descricao_lote'] ?? ''}',
                idLote: idLote,
                anoLote: anoLote,
              );
            }
          }
        } else {
          await MapaGadoDao.instance.marcarErro(id, r.mensagem);
        }
        versaoFila.value++;
      }
    } finally {
      _enviando = false;
    }
  }

  Future<_Resposta> _post(String endpoint, Map<String, dynamic> corpo) async {
    try {
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/mapa-gado/$endpoint"),
            headers: {"Content-Type": "application/json"},
            body: json.encode(corpo),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        return _Resposta.rede('HTTP ${response.statusCode}');
      }
      final dados = json.decode(response.body);
      if (dados is! Map) return _Resposta.rede('Resposta inválida do servidor');
      return dados['success'] == true
          ? _Resposta.ok(Map<String, dynamic>.from(dados))
          : _Resposta.recusada(
              (dados['message'] ?? 'Erro no servidor').toString(),
            );
    } catch (e) {
      return _Resposta.rede(e.toString());
    }
  }

  // ---------------------------------------------------------------------
  // Download do tabuleiro
  // ---------------------------------------------------------------------

  /// Envia o que estiver pendente e baixa o tabuleiro de todas as fazendas
  /// do usuário. Melhor esforço: sem internet ou com erro, mantém o cache
  /// anterior e devolve false.
  Future<bool> baixar(String? bd, List<int> fazendas) async {
    if (bd == null || bd.isEmpty) return false;
    final ids = fazendas.where((f) => f > 0).toSet().toList();
    if (ids.isEmpty) return false;
    if (!ConnectivityService.instance.temInternetReal) return false;
    if (_baixando) return false;

    _baixando = true;
    try {
      await enviarPendentes(bd);

      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/mapa-gado/tabuleiro.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({"bd": bd, "fazendas": ids}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;

      final data = json.decode(response.body);
      if (data['success'] != true) return false;

      List<Map<String, dynamic>> lista(String chave) =>
          ((data[chave] as List?) ?? const [])
              .map((e) => e as Map<String, dynamic>)
              .toList();

      await MapaGadoDao.instance.salvarDoServidor(
        bd: bd,
        fazendasConsultadas: ids,
        categorias: lista('categorias'),
        descricoesLote: lista('descricoes_lote'),
        pastos: lista('pastos'),
        animais: lista('animais'),
        pesosMedios: lista('pesos_medios'),
      );
      await _baixarSatelite(bd, ids);
      return true;
    } catch (e) {
      debugPrint('[MapaGadoSync] baixar: falhou -> $e');
      return false;
    } finally {
      _baixando = false;
    }
  }
}

extension on MapaGadoSyncService {
  /// Mapa Satélite (GeoJSON + cores dos módulos). Melhor esforço e à parte
  /// do tabuleiro: se falhar (ex: servidor ainda sem o endpoint), o
  /// tabuleiro baixado continua valendo.
  Future<void> _baixarSatelite(String bd, List<int> ids) async {
    try {
      final versoes = await MapaGadoDao.instance.versoesSatelite(bd);
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/mapa-gado/satelite.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({"bd": bd, "fazendas": ids, "versoes": versoes}),
          )
          .timeout(const Duration(seconds: 30));
      if (response.statusCode != 200) return;
      final data = json.decode(response.body);
      if (data is! Map || data['success'] != true) return;

      List<Map<String, dynamic>> lista(String chave) =>
          ((data[chave] as List?) ?? const [])
              .map((e) => e as Map<String, dynamic>)
              .toList();

      await MapaGadoDao.instance.salvarSatelite(
        bd: bd,
        modulos: lista('modulos'),
        mapas: lista('mapas'),
      );
    } catch (e) {
      debugPrint('[MapaGadoSync] satélite: falhou -> $e');
    }
  }
}

class _Resposta {
  final bool sucesso;
  final bool redeFalhou;
  final String mensagem;

  /// Corpo da resposta de sucesso (ex: id_lote/ano_lote da descrição).
  final Map<String, dynamic> dados;

  const _Resposta._(
    this.sucesso,
    this.redeFalhou,
    this.mensagem, [
    this.dados = const {},
  ]);
  factory _Resposta.ok(Map<String, dynamic> dados) =>
      _Resposta._(true, false, '', dados);
  factory _Resposta.rede(String m) => _Resposta._(false, true, m);
  factory _Resposta.recusada(String m) => _Resposta._(false, false, m);
}
