import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'connectivity_service.dart';
import '../data/daos/pesagem_local_dao.dart';
import '../data/daos/item_pesagem_local_dao.dart';
import '../data/daos/outbox_dao.dart';

class SincronizacaoResultado {
  final int processadas;
  final int comErro;
  const SincronizacaoResultado({required this.processadas, required this.comErro});
}

/// Motor de sincronização da fila offline (outbox_sincronizacao).
///
/// Processa a fila em ordem de chegada (FIFO), respeitando a dependência
/// "cabeçalho da pesagem antes dos itens dela". Dispara sozinho quando a
/// conectividade real volta e periodicamente enquanto o app está em
/// primeiro plano; também pode ser chamado manualmente (botão "Sincronizar
/// agora"). Erro de rede vira retry com backoff; erro de negócio do
/// servidor (ex: "pesagem não pertence ao app") vira "conflito" — não
/// trava o usuário, só fica pendente de revisão.
class SyncService {
  SyncService._();
  static final SyncService instance = SyncService._();

  Timer? _timerForeground;
  StreamSubscription<NivelConexao>? _subConectividade;
  bool _sincronizando = false;

  final StreamController<int> _pendentesController =
      StreamController<int>.broadcast();
  final StreamController<int> _conflitosController =
      StreamController<int>.broadcast();

  /// Stream com a contagem de operações pendentes/em erro na fila — usado
  /// pelo indicador visual "N pendentes de sincronização".
  Stream<int> get pendentes => _pendentesController.stream;

  /// Stream com a contagem de operações que o servidor recusou e não
  /// tentam de novo sozinhas — usado pelo indicador "Pendências de
  /// revisão".
  Stream<int> get conflitos => _conflitosController.stream;

  /// true só enquanto existe pelo menos uma operação sendo processada de
  /// verdade — usado pelo overlay "Sincronizando dados...". Deliberadamente
  /// não é o mesmo que "_pendentesSync > 0": aquela contagem cai item a
  /// item durante o loop e some rápido demais (pisca) quando a fila tem só
  /// 1-2 operações; este flag cobre a duração inteira da tentativa.
  final ValueNotifier<bool> sincronizando = ValueNotifier(false);

  void iniciar() {
    _subConectividade ??= ConnectivityService.instance.status.listen((nivel) {
      if (nivel == NivelConexao.internetOk) {
        sincronizarAgora();
      }
    });
    _timerForeground ??= Timer.periodic(const Duration(seconds: 30), (_) {
      if (ConnectivityService.instance.temInternetReal) {
        sincronizarAgora();
      }
    });
    atualizarContagemPendentes();
  }

  /// Chamado quando a última tela que usa o indicador de sync é fechada —
  /// não paramos o listener de conectividade (é leve e global), só o timer
  /// periódico de primeiro plano.
  void pausarTimerForeground() {
    _timerForeground?.cancel();
    _timerForeground = null;
  }

  Future<void> atualizarContagemPendentes() async {
    final qtd = await OutboxDao.instance.contarPendentes();
    if (!_pendentesController.isClosed) {
      _pendentesController.add(qtd);
    }
    final qtdConflitos = await OutboxDao.instance.contarConflitos();
    if (!_conflitosController.isClosed) {
      _conflitosController.add(qtdConflitos);
    }
  }

  Future<SincronizacaoResultado> sincronizarAgora() async {
    if (_sincronizando) {
      return const SincronizacaoResultado(processadas: 0, comErro: 0);
    }
    _sincronizando = true;

    try {
      await ConnectivityService.instance.verificarAgora();
      if (!ConnectivityService.instance.temInternetReal) {
        return const SincronizacaoResultado(processadas: 0, comErro: 0);
      }

      final pendentes = await OutboxDao.instance.listarPendentes();
      if (pendentes.isEmpty) {
        return const SincronizacaoResultado(processadas: 0, comErro: 0);
      }

      sincronizando.value = true;
      int processadas = 0;
      int comErro = 0;

      // Pesagens (id do servidor -> bd) tocadas por SALVAR_ITEM/EXCLUIR_ITEM
      // nesta rodada — o servidor recalcula sozinho o "repetido" de todos os
      // itens do animal a cada criação/exclusão (mesmo em pesagens que não
      // estão neste aparelho: outro dispositivo, ou o sistema web). Depois
      // do loop, busca esse resultado de volta pra essas pesagens conhecidas
      // aqui, só como informação extra pro usuário — quem realmente barra a
      // finalização com pesos conflitantes é o sistema web.
      final Map<int, String?> pesagensParaReconciliar = {};

      for (final operacao in pendentes) {
        if (!OutboxDao.instance.podeTentarAgora(operacao)) continue;

        final dependeDe = operacao['depende_de_uuid'] as String?;
        if (dependeDe != null) {
          final aindaPendente = await OutboxDao.instance
              .buscarPendentePorEntidade(
                dependeDe,
                TipoOperacaoOutbox.criarPesagem,
              );
          if (aindaPendente != null) continue;
        }

        final sucesso = await _processarOperacao(
          operacao,
          pesagensParaReconciliar,
        );
        if (sucesso) {
          processadas++;
        } else {
          comErro++;
        }
      }

      for (final entrada in pesagensParaReconciliar.entries) {
        await _reconciliarMensRepetido(entrada.key, entrada.value);
      }

      await atualizarContagemPendentes();
      return SincronizacaoResultado(processadas: processadas, comErro: comErro);
    } finally {
      _sincronizando = false;
      sincronizando.value = false;
    }
  }

  Future<bool> _processarOperacao(
    Map<String, dynamic> operacao,
    Map<int, String?> pesagensParaReconciliar,
  ) async {
    final id = operacao['id'] as int;
    final tipo = operacao['tipo_operacao'] as String;
    final payload =
        json.decode(operacao['payload_json'] as String) as Map<String, dynamic>;

    try {
      switch (tipo) {
        case TipoOperacaoOutbox.criarPesagem:
          return await _processarCriarPesagem(id, payload);
        case TipoOperacaoOutbox.salvarItem:
          return await _processarSalvarItem(
            id,
            payload,
            pesagensParaReconciliar,
          );
        case TipoOperacaoOutbox.editarItem:
          return await _processarChamadaSimples(id, payload, 'update_item.php');
        case TipoOperacaoOutbox.excluirItem:
          final sucesso = await _processarChamadaSimples(
            id,
            payload,
            'delete_item.php',
          );
          if (sucesso) {
            final idServidor = int.tryParse(
              payload['pesagem_id']?.toString() ?? '',
            );
            if (idServidor != null) {
              pesagensParaReconciliar[idServidor] = payload['bd']?.toString();
            }
          }
          return sucesso;
        case TipoOperacaoOutbox.editarPesagem:
          return await _processarChamadaSimples(id, payload, 'update_pesagem.php');
        default:
          await OutboxDao.instance.marcarConflito(id, "Tipo de operação desconhecido: $tipo");
          return false;
      }
    } catch (e) {
      await OutboxDao.instance.marcarErro(id, e.toString());
      return false;
    }
  }

  Future<bool> _processarCriarPesagem(int id, Map<String, dynamic> payload) async {
    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/create_pesagem.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(payload),
    );

    if (response.statusCode != 200) {
      await OutboxDao.instance.marcarErro(id, "HTTP ${response.statusCode}");
      return false;
    }

    final resJson = json.decode(response.body);
    if (resJson['success'] != true) {
      await OutboxDao.instance.marcarConflito(
        id,
        resJson['message']?.toString() ?? "Erro desconhecido ao criar pesagem.",
      );
      return false;
    }

    final idServidor = int.parse(resJson['pesagem_id'].toString());
    final uuid = payload['uuid_app'] as String?;
    if (uuid != null) {
      final local = await PesagemLocalDao.instance.buscarPorUuid(uuid);
      if (local != null) {
        await PesagemLocalDao.instance.confirmarSincronizacao(
          local['id_local'] as int,
          idServidor,
        );
      }
    }

    await OutboxDao.instance.marcarConcluido(id);
    return true;
  }

  Future<bool> _processarSalvarItem(
    int id,
    Map<String, dynamic> payload,
    Map<int, String?> pesagensParaReconciliar,
  ) async {
    final pesagemUuid = payload['uuid_app'] as String?;
    final localPesagem = pesagemUuid != null
        ? await PesagemLocalDao.instance.buscarPorUuid(pesagemUuid)
        : null;
    final idServidorPesagem = localPesagem?['id_servidor'] as int?;

    if (idServidorPesagem == null) {
      // Cabeçalho ainda não confirmado — não deveria acontecer se a
      // dependência foi respeitada, mas por segurança adia em vez de falhar.
      return false;
    }

    final payloadEnvio = Map<String, dynamic>.from(payload)
      ..['pesagem_id'] = idServidorPesagem;

    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/save_item.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(payloadEnvio),
    );

    if (response.statusCode != 200) {
      await OutboxDao.instance.marcarErro(id, "HTTP ${response.statusCode}");
      return false;
    }

    final resJson = json.decode(response.body);
    if (resJson['success'] != true) {
      await OutboxDao.instance.marcarConflito(
        id,
        resJson['message']?.toString() ?? "Erro desconhecido ao salvar item.",
      );
      return false;
    }

    final numeroServidor = int.parse(resJson['numero_item'].toString());
    final itemUuid = (payload['item'] as Map?)?['uuid_app'] as String?;
    if (itemUuid != null) {
      final itemLocal = await ItemPesagemLocalDao.instance.buscarPorUuid(
        itemUuid,
      );
      if (itemLocal != null) {
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(
          itemLocal['id_local'] as int,
          numeroServidor,
        );
      }
    }

    pesagensParaReconciliar[idServidorPesagem] = payload['bd']?.toString();

    await OutboxDao.instance.marcarConcluido(id);
    return true;
  }

  /// Busca de volta o que o servidor já recalculou sozinho (mens_repetido/
  /// id_pesagem_repetido) depois de um SALVAR_ITEM/EXCLUIR_ITEM, e atualiza
  /// os itens locais dessa pesagem — melhor esforço, não trava nem falha a
  /// sincronização se der errado (o alerta principal, que barra a
  /// finalização de verdade, é do sistema web).
  Future<void> _reconciliarMensRepetido(
    int idServidorPesagem,
    String? bd,
  ) async {
    try {
      final response = await http.post(
        Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/get_pesagem_completa.php"),
        body: json.encode({"bd": bd, "id_pesagem": idServidorPesagem}),
      );
      if (response.statusCode != 200) return;

      final data = json.decode(response.body);
      if (data['success'] != true) return;

      final local = await PesagemLocalDao.instance.buscarPorIdServidor(
        idServidorPesagem,
      );
      if (local == null) return;
      final idLocal = local['id_local'] as int;

      final itens = (data['itens'] as List<dynamic>?) ?? [];
      for (final item in itens) {
        final numeroServidor = int.tryParse(
          item['tbl_ite_pesagem_numero_item']?.toString() ?? '',
        );
        if (numeroServidor == null) continue;

        await ItemPesagemLocalDao.instance.atualizarMensRepetido(
          idLocal,
          numeroServidor,
          mensRepetido:
              item['tbl_ite_pesagem_mens_repetido']?.toString() ?? '',
          idPesagemRepetido:
              item['tbl_ite_pesagem_id_repetido']?.toString() ?? '',
        );
      }
    } catch (_) {
      // best-effort — não deve travar a sincronização se isso falhar
    }
  }

  Future<bool> _processarChamadaSimples(
    int id,
    Map<String, dynamic> payload,
    String endpoint,
  ) async {
    final response = await http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/$endpoint"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(payload),
    );

    if (response.statusCode != 200) {
      await OutboxDao.instance.marcarErro(id, "HTTP ${response.statusCode}");
      return false;
    }

    Map<String, dynamic>? resJson;
    try {
      resJson = json.decode(response.body) as Map<String, dynamic>;
    } catch (_) {
      // update_item.php/delete_item.php podem responder corpo vazio em
      // alguns casos de payload malformado — trata como sucesso silencioso
      // (mesmo comportamento tolerante que a tela já tinha antes).
    }

    if (resJson != null && resJson['success'] == false) {
      await OutboxDao.instance.marcarConflito(
        id,
        resJson['message']?.toString() ?? "Operação recusada pelo servidor.",
      );
      return false;
    }

    await OutboxDao.instance.marcarConcluido(id);
    return true;
  }
}
