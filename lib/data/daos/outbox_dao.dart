import 'dart:convert';
import '../local_database.dart';

/// Tipos de operação que podem esperar na fila de sincronização.
class TipoOperacaoOutbox {
  static const criarPesagem = 'CRIAR_PESAGEM';
  static const salvarItem = 'SALVAR_ITEM';
  static const editarItem = 'EDITAR_ITEM';
  static const excluirItem = 'EXCLUIR_ITEM';
  static const editarPesagem = 'EDITAR_PESAGEM';
}

class StatusOutbox {
  static const pendente = 'pendente';
  static const processando = 'processando';
  static const erro = 'erro';
  static const conflito = 'conflito';
  static const concluido = 'concluido';
}

/// DAO da fila de sincronização (outbox_sincronizacao).
class OutboxDao {
  OutboxDao._();
  static final OutboxDao instance = OutboxDao._();

  Future<int> enfileirar({
    required String tipoOperacao,
    required String entidadeUuid,
    String? dependeDeUuid,
    required Map<String, dynamic> payload,
  }) async {
    final db = await LocalDatabase.instance.database;
    return db.insert('outbox_sincronizacao', {
      'tipo_operacao': tipoOperacao,
      'entidade_uuid': entidadeUuid,
      'depende_de_uuid': dependeDeUuid,
      'payload_json': json.encode(payload),
      'tentativas': 0,
      'status': StatusOutbox.pendente,
      'criado_em': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> listarPendentes() async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'outbox_sincronizacao',
      where: 'status IN (?, ?)',
      whereArgs: [StatusOutbox.pendente, StatusOutbox.erro],
      orderBy: 'id ASC',
    );
  }

  Future<int> contarPendentes() async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) as qtd FROM outbox_sincronizacao WHERE status IN ('${StatusOutbox.pendente}', '${StatusOutbox.erro}')",
    );
    return (r.first['qtd'] as int?) ?? 0;
  }

  Future<int> contarConflitos() async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      "SELECT COUNT(*) as qtd FROM outbox_sincronizacao WHERE status = '${StatusOutbox.conflito}'",
    );
    return (r.first['qtd'] as int?) ?? 0;
  }

  /// Operações que o servidor recusou explicitamente e que não tentam de
  /// novo sozinhas — base da tela "Pendências de revisão".
  Future<List<Map<String, dynamic>>> listarConflitos() async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'outbox_sincronizacao',
      where: 'status = ?',
      whereArgs: [StatusOutbox.conflito],
      orderBy: 'id DESC',
    );
  }

  /// Bota a operação de volta na fila normal — próxima sincronização tenta
  /// de novo. Zera tentativas/espera pra não herdar backoff de uma corrida
  /// anterior sem relação com o motivo do conflito.
  Future<void> reenfileirar(int id) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'outbox_sincronizacao',
      {
        'status': StatusOutbox.pendente,
        'tentativas': 0,
        'proxima_tentativa_em': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  /// Busca a operação pendente mais recente para uma entidade+tipo (usado
  /// para reescrever o payload em vez de duplicar operação, ex: editar um
  /// item que ainda não foi sincronizado).
  Future<Map<String, dynamic>?> buscarPendentePorEntidade(
    String entidadeUuid,
    String tipoOperacao,
  ) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'outbox_sincronizacao',
      where: 'entidade_uuid = ? AND tipo_operacao = ? AND status IN (?, ?)',
      whereArgs: [
        entidadeUuid,
        tipoOperacao,
        StatusOutbox.pendente,
        StatusOutbox.erro,
      ],
      orderBy: 'id DESC',
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  Future<void> reescreverPayload(int id, Map<String, dynamic> payload) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'outbox_sincronizacao',
      {'payload_json': json.encode(payload)},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> cancelar(int id) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('outbox_sincronizacao', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> marcarConcluido(int id) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'outbox_sincronizacao',
      {'status': StatusOutbox.concluido},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarErro(int id, String mensagem, {int? tentativas}) async {
    final db = await LocalDatabase.instance.database;
    final atual = await db.query(
      'outbox_sincronizacao',
      columns: ['tentativas'],
      where: 'id = ?',
      whereArgs: [id],
    );
    final tentativasAtuais = atual.isNotEmpty
        ? (atual.first['tentativas'] as int? ?? 0)
        : 0;
    final novasTentativas = tentativas ?? (tentativasAtuais + 1);

    // Backoff exponencial simples: 15s, 30s, 60s, 120s..., limitado a 30 min.
    final segundosEspera = (15 * (1 << novasTentativas.clamp(0, 7))).clamp(
      15,
      1800,
    );
    final proximaTentativa = DateTime.now().add(
      Duration(seconds: segundosEspera),
    );

    await db.update(
      'outbox_sincronizacao',
      {
        'status': StatusOutbox.erro,
        'tentativas': novasTentativas,
        'ultimo_erro': mensagem,
        'proxima_tentativa_em': proximaTentativa.toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> marcarConflito(int id, String mensagem) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'outbox_sincronizacao',
      {'status': StatusOutbox.conflito, 'ultimo_erro': mensagem},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  bool podeTentarAgora(Map<String, dynamic> linha) {
    final proxima = linha['proxima_tentativa_em'] as String?;
    if (proxima == null) return true;
    final dataProxima = DateTime.tryParse(proxima);
    if (dataProxima == null) return true;
    return DateTime.now().isAfter(dataProxima);
  }
}
