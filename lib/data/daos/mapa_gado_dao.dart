import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import '../../utils/mapa_tabuleiro_calculo.dart';
import '../local_database.dart';

/// Tipos de ação da fila do Mapa de Gado (mapa_outbox).
class AcaoMapa {
  AcaoMapa._();

  /// Mover TODOS os animais de um pasto para outro.
  /// payload: {origem, destino, usuario, data_hora}
  static const transferirTudo = 'transferir_tudo';

  /// Nova Descrição do Lote num pasto.
  /// payload: {pasto, descricao_lote, lotes[6], usuario, data_hora}
  static const descricaoLote = 'descricao_lote';
}

/// DAO do cache do Mapa de Gado (Tabuleiro) — pastos, animais no pasto,
/// faixas de categoria e opções de descrição do lote das fazendas do
/// usuário, replicados localmente para a tela funcionar offline — e da
/// fila das ações feitas no mapa (mapa_outbox).
///
/// Toda ação é aplicada no cache NA HORA (o tabuleiro já mostra o
/// resultado, com ou sem internet) e fica na fila até o servidor
/// confirmar. Como cada download substitui o cache pelo que está no
/// servidor, as ações ainda pendentes são reaplicadas por cima logo depois
/// (ver [salvarDoServidor]) — senão um download feito antes do envio
/// "desfaria" na tela o que o usuário acabou de mover.
class MapaGadoDao {
  MapaGadoDao._();
  static final MapaGadoDao instance = MapaGadoDao._();

  /// Substitui o cache das fazendas consultadas pelo que veio do servidor,
  /// numa transação só — se algo falhar no meio, fica o cache anterior
  /// inteiro (nunca meio apagado).
  Future<void> salvarDoServidor({
    required String bd,
    required List<int> fazendasConsultadas,
    required List<Map<String, dynamic>> categorias,
    required List<Map<String, dynamic>> descricoesLote,
    required List<Map<String, dynamic>> pastos,
    required List<Map<String, dynamic>> animais,
    List<Map<String, dynamic>> pesosMedios = const [],
  }) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();

    // O servidor filtra animais só pelo pasto; a fazenda do card é a do
    // pasto, não a de tbl_animal_pasto_local.
    final fazendaDoPasto = <int, int>{
      for (final p in pastos) _int(p['id']): _int(p['local']),
    };

    await db.transaction((txn) async {
      final batch = txn.batch();

      batch.delete('mapa_categorias_cache', where: 'bd = ?', whereArgs: [bd]);
      for (final c in categorias) {
        batch.insert('mapa_categorias_cache', {
          'bd': bd,
          'id': _int(c['id']),
          'idade_de': _int(c['de']),
          'idade_ate': _int(c['ate']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      batch.delete(
        'mapa_descricoes_lote_cache',
        where: 'bd = ?',
        whereArgs: [bd],
      );
      for (final d in descricoesLote) {
        batch.insert('mapa_descricoes_lote_cache', {
          'bd': bd,
          'id': _int(d['id']),
          'descricao': (d['descricao'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final fazenda in fazendasConsultadas) {
        batch.delete(
          'mapa_pastos_cache',
          where: 'bd = ? AND fazenda_id = ?',
          whereArgs: [bd, fazenda],
        );
        batch.delete(
          'mapa_animais_pasto_cache',
          where: 'bd = ? AND fazenda_id = ?',
          whereArgs: [bd, fazenda],
        );
        batch.insert('mapa_fazendas_cache', {
          'bd': bd,
          'fazenda_id': fazenda,
          'atualizado_em': agora,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final p in pastos) {
        final lotes = (p['lotes'] as List?)?.map((e) => e.toString()).toList();
        batch.insert('mapa_pastos_cache', {
          'bd': bd,
          'id': _int(p['id']),
          'fazenda_id': _int(p['local']),
          'descricao': (p['descricao'] ?? '').toString(),
          'modulo': _int(p['modulo']),
          'capim': (p['capim'] ?? '').toString(),
          'categorias': (p['categorias'] ?? '').toString(),
          'ordem': _int(p['ordem']),
          'descricao_lote': (p['descricao_lote'] ?? '').toString(),
          'lotes_json': json.encode(lotes ?? List.filled(6, '')),
          // servidor antigo (sem o campo) = todos no tabuleiro
          'tabuleiro': p['tabuleiro'] == false ? 0 : 1,
          'data_com_animais': p['data_com_animais']?.toString(),
          'data_sem_animais': p['data_sem_animais']?.toString(),
          'area': (p['area'] as num?)?.toDouble() ?? 0,
          'id_lote': _int(p['id_lote']),
          'ano_lote': _int(p['ano_lote']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final fazenda in fazendasConsultadas) {
        batch.delete(
          'mapa_pesos_medios_cache',
          where: 'bd = ? AND fazenda_id = ?',
          whereArgs: [bd, fazenda],
        );
      }
      for (final pm in pesosMedios) {
        batch.insert('mapa_pesos_medios_cache', {
          'bd': bd,
          'fazenda_id': _int(pm['local']),
          'categoria': _int(pm['categoria']),
          'sexo': (pm['sexo'] ?? '').toString(),
          'peso': _int(pm['peso']),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final a in animais) {
        final pastoId = _int(a['pasto']);
        final fazenda = fazendaDoPasto[pastoId];
        if (fazenda == null) continue;
        batch.insert('mapa_animais_pasto_cache', {
          'bd': bd,
          'fazenda_id': fazenda,
          'local': _int(a['local']),
          'numero_item': _int(a['item']),
          'pasto_id': pastoId,
          'sexo': a['sexo']?.toString(),
          'nascimento': a['nascimento']?.toString(),
        });
      }

      await batch.commit(noResult: true);

      // Ações ainda não confirmadas pelo servidor voltam a valer por cima
      // do que acabou de ser baixado (ver docblock da classe).
      final pendentes = await txn.query(
        'mapa_outbox',
        where: "bd = ? AND status = 'pendente'",
        whereArgs: [bd],
        orderBy: 'id',
      );
      for (final p in pendentes) {
        await _aplicarNoCache(
          txn,
          bd,
          p['tipo'] as String,
          json.decode(p['payload_json'] as String) as Map<String, dynamic>,
        );
      }
    });
  }

  // ---------------------------------------------------------------------
  // Leitura
  // ---------------------------------------------------------------------

  Future<Map<int, CategoriaIdadeMapa>> categorias(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_categorias_cache',
      columns: ['id', 'idade_de', 'idade_ate'],
      where: 'bd = ?',
      whereArgs: [bd],
    );
    return {
      for (final l in linhas)
        l['id'] as int: CategoriaIdadeMapa(
          id: l['id'] as int,
          idadeDe: l['idade_de'] as int,
          idadeAte: l['idade_ate'] as int,
        ),
    };
  }

  /// Opções de "Descrição do Lote", na ordem do código (igual ao select
  /// do web).
  Future<List<MapEntry<int, String>>> descricoesLote(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_descricoes_lote_cache',
      columns: ['id', 'descricao'],
      where: 'bd = ?',
      whereArgs: [bd],
      orderBy: 'id',
    );
    return linhas
        .map((l) => MapEntry(l['id'] as int, (l['descricao'] ?? '').toString()))
        .toList();
  }

  /// Pastos da fazenda na ordem do Tabuleiro. Por padrão só os do
  /// Tabuleiro; [incluirForaTabuleiro] traz também os módulos 1006/1007
  /// (Mapa Satélite).
  Future<List<PastoMapa>> pastos(
    String bd,
    int fazendaId, {
    bool incluirForaTabuleiro = false,
  }) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_pastos_cache',
      columns: [
        'id',
        'fazenda_id',
        'descricao',
        'modulo',
        'capim',
        'categorias',
        'ordem',
        'descricao_lote',
        'tabuleiro',
        'data_com_animais',
        'data_sem_animais',
        'area',
        'id_lote',
        'ano_lote',
      ],
      where: incluirForaTabuleiro
          ? 'bd = ? AND fazenda_id = ?'
          : 'bd = ? AND fazenda_id = ? AND tabuleiro = 1',
      whereArgs: [bd, fazendaId],
      orderBy: 'ordem',
    );
    return linhas
        .map(
          (l) => PastoMapa(
            id: l['id'] as int,
            fazendaId: l['fazenda_id'] as int,
            descricao: (l['descricao'] ?? '').toString(),
            modulo: l['modulo'] as int,
            capim: (l['capim'] ?? '').toString(),
            categorias: (l['categorias'] ?? '').toString(),
            ordem: l['ordem'] as int,
            descricaoLote: (l['descricao_lote'] ?? '').toString(),
            tabuleiro: (l['tabuleiro'] as int? ?? 1) == 1,
            dataComAnimais: l['data_com_animais'] as String?,
            dataSemAnimais: l['data_sem_animais'] as String?,
            area: (l['area'] as num?)?.toDouble() ?? 0,
            idLote: l['id_lote'] as int? ?? 0,
            anoLote: l['ano_lote'] as int? ?? 0,
          ),
        )
        .toList();
  }

  /// Peso médio da fazenda por "categoria|sexo" (ex: "2|F") — Lotação.
  Future<Map<String, int>> pesosMedios(String bd, int fazendaId) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_pesos_medios_cache',
      columns: ['categoria', 'sexo', 'peso'],
      where: 'bd = ? AND fazenda_id = ?',
      whereArgs: [bd, fazendaId],
    );
    return {
      for (final l in linhas) '${l['categoria']}|${l['sexo']}': l['peso'] as int,
    };
  }

  // ---------------------------------------------------------------------
  // Mapa Satélite
  // ---------------------------------------------------------------------

  /// Versão (md5) do mapa que este aparelho já tem, por fazenda — enviada
  /// ao servidor para ele só devolver o GeoJSON que mudou.
  Future<Map<String, String>> versoesSatelite(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_satelite_cache',
      columns: ['fazenda_id', 'versao'],
      where: 'bd = ?',
      whereArgs: [bd],
    );
    return {
      for (final l in linhas) l['fazenda_id'].toString(): l['versao'] as String,
    };
  }

  /// Grava o que veio de api/rest/mapa-gado/satelite.php. geojson null com
  /// versão não vazia = o mapa guardado continua valendo (só atualiza a
  /// coordenada); versão vazia = fazenda sem mapa desenhado.
  Future<void> salvarSatelite({
    required String bd,
    required List<Map<String, dynamic>> modulos,
    required List<Map<String, dynamic>> mapas,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      final batch = txn.batch();
      batch.delete('mapa_modulos_cache', where: 'bd = ?', whereArgs: [bd]);
      for (final m in modulos) {
        batch.insert('mapa_modulos_cache', {
          'bd': bd,
          'id': _int(m['id']),
          'cor': (m['cor'] ?? '').toString(),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }

      for (final m in mapas) {
        final fazenda = _int(m['local']);
        final versao = (m['versao'] ?? '').toString();
        final latitude = (m['latitude'] as num?)?.toDouble();
        final longitude = (m['longitude'] as num?)?.toDouble();

        if (m['geojson'] == null && versao.isNotEmpty) {
          batch.update(
            'mapa_satelite_cache',
            {'latitude': latitude, 'longitude': longitude},
            where: 'bd = ? AND fazenda_id = ?',
            whereArgs: [bd, fazenda],
          );
          continue;
        }
        batch.insert('mapa_satelite_cache', {
          'bd': bd,
          'fazenda_id': fazenda,
          'versao': versao,
          'geojson': m['geojson'] == null ? null : json.encode(m['geojson']),
          'latitude': latitude,
          'longitude': longitude,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  /// GeoJSON (texto) e coordenada da fazenda; null = nunca baixado.
  Future<({String? geojson, double? latitude, double? longitude})?>
  mapaSatelite(String bd, int fazendaId) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_satelite_cache',
      columns: ['geojson', 'latitude', 'longitude'],
      where: 'bd = ? AND fazenda_id = ?',
      whereArgs: [bd, fazendaId],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    final l = linhas.first;
    return (
      geojson: l['geojson'] as String?,
      latitude: (l['latitude'] as num?)?.toDouble(),
      longitude: (l['longitude'] as num?)?.toDouble(),
    );
  }

  /// Cor de cada módulo ("#RRGGBB"), por id.
  Future<Map<int, String>> coresModulos(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_modulos_cache',
      columns: ['id', 'cor'],
      where: 'bd = ?',
      whereArgs: [bd],
    );
    return {for (final l in linhas) l['id'] as int: l['cor'] as String};
  }

  Future<List<AnimalPastoMapa>> animais(String bd, int fazendaId) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_animais_pasto_cache',
      columns: ['pasto_id', 'sexo', 'nascimento'],
      where: 'bd = ? AND fazenda_id = ?',
      whereArgs: [bd, fazendaId],
    );
    return linhas
        .map(
          (l) => AnimalPastoMapa(
            pastoId: l['pasto_id'] as int,
            sexo: l['sexo'] as String?,
            nascimento: l['nascimento'] as String?,
          ),
        )
        .toList();
  }

  /// Quando a fazenda foi baixada pela última vez (null = nunca).
  Future<DateTime?> atualizadoEm(String bd, int fazendaId) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_fazendas_cache',
      columns: ['atualizado_em'],
      where: 'bd = ? AND fazenda_id = ?',
      whereArgs: [bd, fazendaId],
      limit: 1,
    );
    if (linhas.isEmpty) return null;
    return DateTime.tryParse(linhas.first['atualizado_em'].toString());
  }

  /// Último download do mapa neste aparelho, de qualquer fazenda da conta
  /// (ISO 8601; null = nunca) — exibido na tela "Atualizações".
  Future<String?> ultimaAtualizacao(String bd) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT MAX(atualizado_em) AS ultima FROM mapa_fazendas_cache WHERE bd = ?',
      [bd],
    );
    return r.first['ultima'] as String?;
  }

  // ---------------------------------------------------------------------
  // Fila de ações (mapa_outbox)
  // ---------------------------------------------------------------------

  /// Grava a ação na fila e já aplica no cache, na mesma transação.
  Future<void> registrarAcao({
    required String bd,
    required String uuid,
    required String tipo,
    required Map<String, dynamic> payload,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.insert('mapa_outbox', {
        'bd': bd,
        'uuid': uuid,
        'tipo': tipo,
        'payload_json': json.encode(payload),
        'status': 'pendente',
        'tentativas': 0,
        'criado_em': DateTime.now().toIso8601String(),
      });
      await _aplicarNoCache(txn, bd, tipo, payload);
    });
  }

  Future<List<Map<String, dynamic>>> listarPendentes(String bd) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'mapa_outbox',
      where: "bd = ? AND status = 'pendente'",
      whereArgs: [bd],
      orderBy: 'id',
    );
  }

  Future<int> contar(String bd, String status) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS qtd FROM mapa_outbox WHERE bd = ? AND status = ?',
      [bd, status],
    );
    return (r.first['qtd'] as int?) ?? 0;
  }

  /// Ações que o servidor recusou (mensagem de cada uma).
  Future<List<String>> mensagensDeErro(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_outbox',
      columns: ['ultimo_erro'],
      where: "bd = ? AND status = 'erro'",
      whereArgs: [bd],
      orderBy: 'id',
    );
    return linhas.map((l) => (l['ultimo_erro'] ?? '').toString()).toList();
  }

  Future<void> removerAcao(int id) async {
    final db = await LocalDatabase.instance.database;
    await db.delete('mapa_outbox', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> marcarErro(int id, String mensagem) async {
    final db = await LocalDatabase.instance.database;
    await db.rawUpdate(
      "UPDATE mapa_outbox SET status = 'erro', ultimo_erro = ?, tentativas = tentativas + 1 WHERE id = ?",
      [mensagem, id],
    );
  }

  Future<void> contarTentativa(int id, String mensagem) async {
    final db = await LocalDatabase.instance.database;
    await db.rawUpdate(
      'UPDATE mapa_outbox SET ultimo_erro = ?, tentativas = tentativas + 1 WHERE id = ?',
      [mensagem, id],
    );
  }

  Future<void> limparErros(String bd) async {
    final db = await LocalDatabase.instance.database;
    await db.delete(
      'mapa_outbox',
      where: "bd = ? AND status = 'erro'",
      whereArgs: [bd],
    );
  }

  // ---------------------------------------------------------------------
  // Aplicação local das ações (mesma regra do servidor)
  // ---------------------------------------------------------------------

  Future<void> _aplicarNoCache(
    DatabaseExecutor txn,
    String bd,
    String tipo,
    Map<String, dynamic> payload,
  ) async {
    if (tipo == AcaoMapa.transferirTudo) {
      await _aplicarTransferencia(
        txn,
        bd,
        _int(payload['origem']),
        _int(payload['destino']),
      );
    } else if (tipo == AcaoMapa.descricaoLote) {
      final lotes = ((payload['lotes'] as List?) ?? const [])
          .map((e) => e.toString())
          .toList();
      await txn.update(
        'mapa_pastos_cache',
        {
          'descricao_lote': (payload['descricao_lote'] ?? '').toString(),
          'lotes_json': json.encode(lotes),
          // número do lote novo só existe depois que o servidor gravar
          'id_lote': 0,
          'ano_lote': 0,
        },
        where: 'bd = ? AND id = ?',
        whereArgs: [bd, _int(payload['pasto'])],
      );
    }
  }

  /// Premissas 1 e 6 de transferir_tudo_mapa_gados.php: a descrição do
  /// lote da origem vai para o destino só se o destino não tiver nenhuma;
  /// a origem sempre fica sem. Os animais passam para o destino.
  Future<void> _aplicarTransferencia(
    DatabaseExecutor txn,
    String bd,
    int origem,
    int destino,
  ) async {
    Future<Map<String, Object?>?> pasto(int id) async {
      final l = await txn.query(
        'mapa_pastos_cache',
        columns: ['fazenda_id', 'descricao_lote', 'lotes_json', 'id_lote', 'ano_lote'],
        where: 'bd = ? AND id = ?',
        whereArgs: [bd, id],
        limit: 1,
      );
      return l.isEmpty ? null : l.first;
    }

    final pOrigem = await pasto(origem);
    final pDestino = await pasto(destino);
    if (pOrigem == null || pDestino == null) return;

    final descOrigem = (pOrigem['descricao_lote'] ?? '').toString();
    final descDestino = (pDestino['descricao_lote'] ?? '').toString();

    if (descOrigem.isNotEmpty && descDestino.isEmpty) {
      await txn.update(
        'mapa_pastos_cache',
        {
          'descricao_lote': descOrigem,
          'lotes_json': pOrigem['lotes_json'],
          'id_lote': pOrigem['id_lote'],
          'ano_lote': pOrigem['ano_lote'],
        },
        where: 'bd = ? AND id = ?',
        whereArgs: [bd, destino],
      );
    }
    await txn.update(
      'mapa_pastos_cache',
      {
        'descricao_lote': '',
        'lotes_json': json.encode(List.filled(6, '')),
        'id_lote': 0,
        'ano_lote': 0,
      },
      where: 'bd = ? AND id = ?',
      whereArgs: [bd, origem],
    );

    await txn.update(
      'mapa_animais_pasto_cache',
      {'pasto_id': destino, 'fazenda_id': pDestino['fazenda_id']},
      where: 'bd = ? AND pasto_id = ?',
      whereArgs: [bd, origem],
    );
  }

  static int _int(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
}
