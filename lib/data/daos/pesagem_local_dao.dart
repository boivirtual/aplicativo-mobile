import 'dart:convert';
import '../local_database.dart';

class StatusSyncPesagem {
  static const pendente = 'pendente';
  static const sincronizado = 'sincronizado';
}

/// DAO da tabela pesagens_locais — cabeçalho da pesagem espelhado no
/// dispositivo, para a tela funcionar sem depender do servidor.
class PesagemLocalDao {
  PesagemLocalDao._();
  static final PesagemLocalDao instance = PesagemLocalDao._();

  Future<int> inserir({
    required String uuid,
    int? idServidor,
    required String bd,
    required String fazendaId,
    required String epocaId,
    required String lote,
    required int qtdAPesar,
    String? filtroDesc,
    String? usuario,
    required List<String> criteriosLista,
    String finalizada = 'N',
    String statusSync = StatusSyncPesagem.pendente,
    int? qtdPesadosServidor,
  }) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    return db.insert('pesagens_locais', {
      'uuid': uuid,
      'id_servidor': idServidor,
      'bd': bd,
      'fazenda_id': fazendaId,
      'epoca_id': epocaId,
      'lote': lote,
      'qtd_a_pesar': qtdAPesar,
      'qtd_pesados_servidor': qtdPesadosServidor,
      'filtro_desc': filtroDesc,
      'usuario': usuario,
      'criterios_lista': json.encode(criteriosLista),
      'finalizada': finalizada,
      'status_sync': statusSync,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }

  Future<Map<String, dynamic>?> buscarPorUuid(String uuid) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'pesagens_locais',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  Future<Map<String, dynamic>?> buscarPorIdLocal(int idLocal) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'pesagens_locais',
      where: 'id_local = ?',
      whereArgs: [idLocal],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  Future<Map<String, dynamic>?> buscarPorIdServidor(int idServidor) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'pesagens_locais',
      where: 'id_servidor = ?',
      whereArgs: [idServidor],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  /// Resolve uma pesagem local a partir do "id" que a tela usa: positivo =
  /// id_servidor; negativo = -id_local (convenção enquanto não sincronizado).
  Future<Map<String, dynamic>?> resolverPorIdDeTela(int idTela) async {
    if (idTela > 0) return buscarPorIdServidor(idTela);
    if (idTela < 0) return buscarPorIdLocal(-idTela);
    return null;
  }

  Future<void> confirmarSincronizacao(int idLocal, int idServidor) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'pesagens_locais',
      {
        'id_servidor': idServidor,
        'status_sync': StatusSyncPesagem.sincronizado,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> atualizarCabecalho(
    int idLocal, {
    String? bd,
    String? fazendaId,
    String? epocaId,
    String? lote,
    int? qtdAPesar,
    String? filtroDesc,
    List<String>? criteriosLista,
    int? qtdPesadosServidor,
  }) async {
    final db = await LocalDatabase.instance.database;
    final valores = <String, dynamic>{
      'atualizado_em': DateTime.now().toIso8601String(),
    };
    if (bd != null && bd.isNotEmpty) valores['bd'] = bd;
    if (fazendaId != null) valores['fazenda_id'] = fazendaId;
    if (epocaId != null) valores['epoca_id'] = epocaId;
    if (lote != null) valores['lote'] = lote;
    if (qtdAPesar != null) valores['qtd_a_pesar'] = qtdAPesar;
    if (qtdPesadosServidor != null) {
      valores['qtd_pesados_servidor'] = qtdPesadosServidor;
    }
    if (filtroDesc != null) valores['filtro_desc'] = filtroDesc;
    if (criteriosLista != null) {
      valores['criterios_lista'] = json.encode(criteriosLista);
    }

    await db.update(
      'pesagens_locais',
      valores,
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<List<Map<String, dynamic>>> listarPendentesLocais(String bd) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'pesagens_locais',
      where: 'bd = ? AND finalizada = ?',
      whereArgs: [bd, 'N'],
      orderBy: 'id_local DESC',
    );
  }

  /// Pesagens já confirmadas pelo servidor (id_servidor preenchido), ainda
  /// marcadas como não finalizadas neste aparelho — candidatas a checar se
  /// ainda existem no servidor (ver PesagemRepository._reconciliarExcluidos).
  Future<List<Map<String, dynamic>>> listarSincronizadasNaoFinalizadas(
    String bd,
  ) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'pesagens_locais',
      where: 'bd = ? AND finalizada = ? AND id_servidor IS NOT NULL',
      whereArgs: [bd, 'N'],
    );
  }

  /// Remove a pesagem do cache local — usado só quando o servidor confirma
  /// que ela não existe mais (ex: excluída pelo sistema web).
  Future<void> excluirPorIdLocal(int idLocal) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('pesagens_locais', where: 'id_local = ?', whereArgs: [idLocal]);
  }

  /// Salva/atualiza no cache local uma pesagem que veio do servidor (para
  /// permitir reabrir offline mesmo pesagens criadas antes deste dispositivo
  /// ter a fila offline, ou criadas por outro dispositivo/sistema web).
  ///
  /// [bd] precisa ser o CNPJ/banco real do usuário logado — listarPendentesLocais
  /// filtra por esse campo quando offline, então gravar bd vazio aqui fazia
  /// pesagens importadas do servidor sumirem da lista offline (só a pesagem
  /// criada neste próprio aparelho, com bd certo, continuava aparecendo).
  Future<int> importarDoServidor(
    Map<String, dynamic> pesagemServidor, {
    required String bd,
  }) async {
    final idServidor = int.parse(
      pesagemServidor['tbl_pesagem_id'].toString(),
    );
    final existente = await buscarPorIdServidor(idServidor);
    final qtdPesadosServidor = int.tryParse(
      pesagemServidor['tbl_pesagem_qtd_animais_pesados']?.toString() ?? '',
    );

    final criteriosBruto =
        (pesagemServidor['tbl_pesagem_criterios_apartacao'] ?? '').toString();
    final criteriosLista = criteriosBruto.trim().isEmpty
        ? <String>[]
        : criteriosBruto
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList();

    if (existente != null) {
      await atualizarCabecalho(
        existente['id_local'] as int,
        bd: bd,
        fazendaId: pesagemServidor['tbl_pesagem_codigo_local']?.toString(),
        epocaId: pesagemServidor['tbl_pesagem_codigo_epoca']?.toString(),
        lote: pesagemServidor['tbl_pesagem_lote']?.toString() ?? '',
        qtdAPesar:
            int.tryParse(
              pesagemServidor['tbl_pesagem_qtd_animais_a_pesar']?.toString() ??
                  '0',
            ) ??
            0,
        filtroDesc: pesagemServidor['tbl_pesagem_filtros']?.toString(),
        criteriosLista: criteriosLista,
        qtdPesadosServidor: qtdPesadosServidor,
      );
      return existente['id_local'] as int;
    }

    return inserir(
      uuid: 'importado-servidor-$idServidor',
      idServidor: idServidor,
      bd: bd,
      fazendaId: pesagemServidor['tbl_pesagem_codigo_local']?.toString() ?? '',
      epocaId: pesagemServidor['tbl_pesagem_codigo_epoca']?.toString() ?? '',
      lote: pesagemServidor['tbl_pesagem_lote']?.toString() ?? '',
      qtdAPesar:
          int.tryParse(
            pesagemServidor['tbl_pesagem_qtd_animais_a_pesar']?.toString() ??
                '0',
          ) ??
          0,
      filtroDesc: pesagemServidor['tbl_pesagem_filtros']?.toString(),
      criteriosLista: criteriosLista,
      finalizada:
          pesagemServidor['tbl_pesagem_finalizada']?.toString() ?? 'N',
      statusSync: StatusSyncPesagem.sincronizado,
      qtdPesadosServidor: qtdPesadosServidor,
    );
  }
}
