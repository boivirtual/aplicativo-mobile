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

  /// Transferir animais de UMA categoria (Confirma da tela do pasto).
  /// payload: {origem, destino, categoria, sexo ('M', 'F' ou '' =
  /// bezerros), quantidade, usuario, data_hora}
  static const transferirCategoria = 'transferir_categoria';

  /// Levar a Descrição do Lote do pasto origem para o destino (depois de
  /// transferir parte dos animais para um pasto sem descrição).
  /// payload: {origem, destino, usuario, data_hora}
  static const levarDescricaoLote = 'levar_descricao_lote';

  /// Morte de um animal (botão Morte da tela do pasto).
  /// payload: {fazenda, pasto, animal (id), codigo, sexo, nascimento
  /// (Y-m-d), motivo, data_morte (Y-m-d), observacao, usuario, data_hora}
  static const morte = 'morte';

  /// Nutrição — Confirmar Inclusão.
  /// payload: {chave (uuid da linha local), fazenda, pasto, data (Y-m-d),
  /// produto, produto_descricao, unidade, quantidade, qtd_animais, cocho,
  /// usuario, data_hora}
  static const nutricaoIncluir = 'nutricao_incluir';

  /// Nutrição — excluir (lixeira da tabela).
  /// payload: {id (do servidor), chave, usuario, data_hora}
  static const nutricaoExcluir = 'nutricao_excluir';
}

/// Qual registro do pasto sai com a morte de um animal (ou o erro).
class _PlanoMorte {
  final int? excluir;
  final int? trocarItem;
  final String? trocarNascimento;
  final String? erro;
  const _PlanoMorte({
    this.excluir,
    this.trocarItem,
    this.trocarNascimento,
    this.erro,
  });
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
        batch.insert(
          'mapa_descricoes_lote_cache',
          {
            'bd': bd,
            'id': _int(d['id']),
            'descricao': (d['descricao'] ?? '').toString(),
          },
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
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
      for (final l in linhas)
        '${l['categoria']}|${l['sexo']}': l['peso'] as int,
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
      columns: ['pasto_id', 'numero_item', 'sexo', 'nascimento'],
      where: 'bd = ? AND fazenda_id = ?',
      whereArgs: [bd, fazendaId],
    );
    return linhas
        .map(
          (l) => AnimalPastoMapa(
            pastoId: l['pasto_id'] as int,
            item: l['numero_item'] as int? ?? 0,
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

  /// Os lotes (até 6) que compõem a Descrição do Lote do pasto
  /// (tbl_pasto_descricao_lote_1..6), sem os vazios.
  Future<List<String>> lotesDoPasto(String bd, int pastoId) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_pastos_cache',
      columns: ['lotes_json'],
      where: 'bd = ? AND id = ?',
      whereArgs: [bd, pastoId],
      limit: 1,
    );
    if (linhas.isEmpty) return const [];
    try {
      final lista = json.decode(
        (linhas.first['lotes_json'] ?? '[]').toString(),
      );
      if (lista is! List) return const [];
      return lista.map((e) => e.toString()).where((e) => e.isNotEmpty).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Número/ano do lote gerado pelo servidor para a nova descrição — só se
  /// o pasto ainda estiver com essa mesma descrição (outra ação pendente
  /// pode já ter trocado).
  Future<void> atualizarNumeroLote({
    required String bd,
    required int pastoId,
    required String descricaoLote,
    required int idLote,
    required int anoLote,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'mapa_pastos_cache',
      {'id_lote': idLote, 'ano_lote': anoLote},
      where: 'bd = ? AND id = ? AND descricao_lote = ?',
      whereArgs: [bd, pastoId, descricaoLote],
    );
  }

  /// Número/ano do lote que o servidor gerou para um pasto que estava
  /// aguardando número (id_lote = 0) — usado no "Levar a Descrição do
  /// Lote". Não mexe em pasto sem descrição nem em quem já tem número.
  Future<void> definirNumeroLote({
    required String bd,
    required int pastoId,
    required int idLote,
    required int anoLote,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'mapa_pastos_cache',
      {'id_lote': idLote, 'ano_lote': anoLote},
      where: "bd = ? AND id = ? AND id_lote = 0 AND descricao_lote <> ''",
      whereArgs: [bd, pastoId],
    );
  }

  // ---------------------------------------------------------------------
  // Extras baixados com o tabuleiro (botão Morte)
  // ---------------------------------------------------------------------

  /// Motivos de morte, animais em estação de monta e tipo de controle de
  /// estoque — só grava o que o servidor mandou (servidor antigo não manda
  /// nada e o que já estava no aparelho continua valendo).
  Future<void> salvarExtras({
    required String bd,
    String? controleEstoque,
    List<dynamic>? motivosMorte,
    List<dynamic>? animaisEstacaoMonta,
    List<dynamic>? scoresCocho,
    List<dynamic>? produtosNutricao,
  }) async {
    final db = await LocalDatabase.instance.database;
    Future<void> gravar(String chave, Object? valor) async {
      if (valor == null) return;
      await db.insert('mapa_extras_cache', {
        'bd': bd,
        'chave': chave,
        'valor': json.encode(valor),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }

    await gravar('controle_estoque', controleEstoque);
    await gravar('motivos_morte', motivosMorte);
    await gravar('animais_estacao_monta', animaisEstacaoMonta);
    await gravar('scores_cocho', scoresCocho);
    await gravar('produtos_nutricao', produtosNutricao);
  }

  Future<dynamic> _extra(String bd, String chave) async {
    final db = await LocalDatabase.instance.database;
    final l = await db.query(
      'mapa_extras_cache',
      columns: ['valor'],
      where: 'bd = ? AND chave = ?',
      whereArgs: [bd, chave],
      limit: 1,
    );
    if (l.isEmpty || l.first['valor'] == null) return null;
    try {
      return json.decode(l.first['valor'] as String);
    } catch (_) {
      return null;
    }
  }

  /// 'I' (por animal), 'L' (por lote) ou null se ainda não foi baixado.
  Future<String?> controleEstoque(String bd) async =>
      (await _extra(bd, 'controle_estoque'))?.toString();

  /// Opções do select "Motivo da Morte" (código, descrição).
  Future<List<MapEntry<int, String>>> motivosMorte(String bd) async {
    final lista = await _extra(bd, 'motivos_morte');
    if (lista is! List) return const [];
    return [
      for (final m in lista)
        if (m is Map)
          MapEntry(_int(m['id']), (m['descricao'] ?? '').toString()),
    ];
  }

  /// O animal está em Estação de Monta? (aviso do web ao informar o Nº)
  Future<bool> animalEmEstacaoMonta(String bd, int idAnimal) async {
    final lista = await _extra(bd, 'animais_estacao_monta');
    return lista is List && lista.any((e) => _int(e) == idAnimal);
  }

  // ---------------------------------------------------------------------
  // Morte de um animal — regra local (igual à do servidor)
  // ---------------------------------------------------------------------

  /// Confere, no cache, se a morte pode ser gravada nesse pasto — mesmas
  /// mensagens de gravar_morte.php. null = pode.
  Future<String?> validarMorte({
    required String bd,
    required int fazenda,
    required int pasto,
    required String sexo,
    required String nascimento,
    DateTime? hoje,
  }) async {
    final db = await LocalDatabase.instance.database;
    final plano = await _planoDaMorte(
      db,
      bd: bd,
      fazenda: fazenda,
      pasto: pasto,
      sexo: sexo,
      nascimento: nascimento,
      dia: hoje ?? DateTime.now(),
    );
    return plano.erro;
  }

  /// Decide qual registro do pasto sai com a morte do animal:
  ///   - um registro do pasto com o mesmo sexo e nascimento; senão
  ///   - o registro mais recente do pasto com o mesmo sexo e categoria,
  ///     trocando a data de nascimento com um registro de outro pasto da
  ///     fazenda que tenha o nascimento do animal.
  Future<_PlanoMorte> _planoDaMorte(
    DatabaseExecutor txn, {
    required String bd,
    required int fazenda,
    required int pasto,
    required String sexo,
    required String nascimento,
    required DateTime dia,
  }) async {
    final nasc = nascimento.length >= 10
        ? nascimento.substring(0, 10)
        : nascimento;
    final doPasto = await txn.query(
      'mapa_animais_pasto_cache',
      columns: ['numero_item', 'sexo', 'nascimento'],
      where: 'bd = ? AND pasto_id = ? AND sexo = ?',
      whereArgs: [bd, pasto, sexo],
      orderBy: 'numero_item DESC',
    );
    String data(Object? v) {
      final s = (v ?? '').toString();
      return s.length >= 10 ? s.substring(0, 10) : s;
    }

    for (final a in doPasto) {
      if (data(a['nascimento']) == nasc) {
        return _PlanoMorte(excluir: a['numero_item'] as int);
      }
    }

    // Categoria (faixa de idade) do animal na data da ação.
    final faixas = await txn.query(
      'mapa_categorias_cache',
      columns: ['id', 'idade_de', 'idade_ate'],
      where: 'bd = ?',
      whereArgs: [bd],
    );
    int? categoriaDe(String? nascimentoRegistro) {
      final meses = MapaTabuleiroCalculo.idadeEmMeses(nascimentoRegistro, dia);
      int? codigo;
      for (final f in faixas) {
        if (meses >= (f['idade_de'] as int) &&
            meses <= (f['idade_ate'] as int)) {
          codigo = f['id'] as int;
        }
      }
      return codigo;
    }

    const rotulos = {
      1: '00 a 07 meses',
      2: '08 a 12 meses',
      3: '13 a 24 meses',
      4: '25 a 36 meses',
      5: '> 36 meses',
    };
    final categoria = categoriaDe(nasc);
    final descCategoria = rotulos[categoria] ?? '';

    Map<String, Object?>? atual;
    for (final a in doPasto) {
      if (categoriaDe(a['nascimento'] as String?) == categoria) {
        atual = a;
        break;
      }
    }
    if (atual == null) {
      return _PlanoMorte(
        erro:
            'Não existe animais com o sexo $sexo, categoria $descCategoria '
            'no pasto.',
      );
    }

    final outros = await txn.query(
      'mapa_animais_pasto_cache',
      columns: ['numero_item', 'pasto_id', 'nascimento'],
      where: 'bd = ? AND fazenda_id = ? AND sexo = ? AND nascimento LIKE ?',
      whereArgs: [bd, fazenda, sexo, '$nasc%'],
      orderBy: 'numero_item DESC',
      limit: 1,
    );
    if (outros.isEmpty) {
      return _PlanoMorte(
        erro:
            'Não existe animais com o sexo $sexo, categoria $descCategoria, '
            'nascimento $nasc em outros pastos.',
      );
    }
    return _PlanoMorte(
      excluir: atual['numero_item'] as int,
      trocarItem: outros.first['numero_item'] as int,
      trocarNascimento: atual['nascimento'] as String?,
    );
  }

  /// Aplica a morte no cache: tira o registro do pasto (com a troca de
  /// nascimento, se precisar), limpa a Descrição do Lote se o pasto ficou
  /// vazio. (O cadastro de animais não é alterado aqui: a busca da tela
  /// de Morte esconde os animais com morte pendente — ver
  /// [animaisComMortePendente].)
  Future<void> _aplicarMorte(
    DatabaseExecutor txn,
    String bd,
    Map<String, dynamic> payload,
  ) async {
    final fazenda = _int(payload['fazenda']);
    final pasto = _int(payload['pasto']);
    final dataHora = (payload['data_hora'] ?? '').toString();
    final dia =
        DateTime.tryParse(dataHora.replaceFirst(' ', 'T')) ?? DateTime.now();

    final plano = await _planoDaMorte(
      txn,
      bd: bd,
      fazenda: fazenda,
      pasto: pasto,
      sexo: (payload['sexo'] ?? '').toString(),
      nascimento: (payload['nascimento'] ?? '').toString(),
      dia: dia,
    );
    final excluir = plano.excluir;
    if (excluir != null) {
      if (plano.trocarItem != null) {
        await txn.update(
          'mapa_animais_pasto_cache',
          {'nascimento': plano.trocarNascimento},
          where: 'bd = ? AND fazenda_id = ? AND numero_item = ?',
          whereArgs: [bd, fazenda, plano.trocarItem],
        );
      }
      await txn.delete(
        'mapa_animais_pasto_cache',
        where: 'bd = ? AND pasto_id = ? AND numero_item = ?',
        whereArgs: [bd, pasto, excluir],
      );

      final restantes =
          Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COUNT(*) FROM mapa_animais_pasto_cache WHERE bd = ? AND pasto_id = ?',
              [bd, pasto],
            ),
          ) ??
          0;
      if (restantes == 0) {
        await txn.update(
          'mapa_pastos_cache',
          {
            'descricao_lote': '',
            'lotes_json': json.encode(List.filled(6, '')),
            'id_lote': 0,
            'ano_lote': 0,
            if (dataHora.isNotEmpty) 'data_sem_animais': dataHora,
          },
          where: 'bd = ? AND id = ?',
          whereArgs: [bd, pasto],
        );
      }
    }
  }

  /// Animais com morte ainda na fila (não enviada ou recusada) — a busca
  /// do Nº Animal não pode oferecer de novo.
  Future<Set<int>> animaisComMortePendente(String bd) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'mapa_outbox',
      columns: ['payload_json'],
      where: 'bd = ? AND tipo = ?',
      whereArgs: [bd, AcaoMapa.morte],
    );
    final ids = <int>{};
    for (final l in linhas) {
      try {
        final p = json.decode(l['payload_json'] as String) as Map;
        ids.add(_int(p['animal']));
      } catch (_) {}
    }
    return ids;
  }

  // ---------------------------------------------------------------------
  // Nutrição (botão Nutrição da tela do pasto)
  // ---------------------------------------------------------------------

  /// Opções de "Situação do Cocho" (código, descrição).
  Future<List<MapEntry<int, String>>> scoresCocho(String bd) async {
    final lista = await _extra(bd, 'scores_cocho');
    if (lista is! List) return const [];
    return [
      for (final m in lista)
        if (m is Map)
          MapEntry(_int(m['id']), (m['descricao'] ?? '').toString()),
    ];
  }

  /// Produtos da nutrição: {id, descricao, unidade}.
  Future<List<Map<String, dynamic>>> produtosNutricao(String bd) async {
    final lista = await _extra(bd, 'produtos_nutricao');
    if (lista is! List) return const [];
    return [
      for (final m in lista)
        if (m is Map)
          {
            'id': _int(m['id']),
            'descricao': (m['descricao'] ?? '').toString(),
            'unidade': (m['unidade'] ?? '').toString(),
          },
    ];
  }

  Map<String, Object?> _linhaNutricao(String bd, Map<String, dynamic> n) => {
    'bd': bd,
    'chave': 's${_int(n['id'])}',
    'id': _int(n['id']),
    'fazenda_id': _int(n['local']),
    'pasto_id': _int(n['pasto']),
    'data': (n['data'] ?? '').toString(),
    'produto_id': _int(n['produto']),
    'produto': (n['produto_descricao'] ?? '').toString(),
    'unidade': (n['unidade'] ?? '').toString(),
    'quantidade': double.tryParse('${n['quantidade']}') ?? 0,
    'qtd_animais': _int(n['qtd_animais']),
    'media_cabeca': double.tryParse('${n['media_cabeca']}') ?? 0,
  };

  /// Nutrições recentes (a partir de [desde], Y-m-d) das fazendas, como
  /// vieram do servidor junto com o tabuleiro. As inclusões/exclusões ainda
  /// pendentes voltam a valer por cima.
  Future<void> salvarNutricoes({
    required String bd,
    required List<int> fazendas,
    required String desde,
    required List<Map<String, dynamic>> nutricoes,
  }) async {
    if (fazendas.isEmpty) return;
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'mapa_nutricao_cache',
        where: 'bd = ? AND data >= ? AND fazenda_id IN (${fazendas.join(',')})',
        whereArgs: [bd, desde],
      );
      for (final n in nutricoes) {
        await txn.insert(
          'mapa_nutricao_cache',
          _linhaNutricao(bd, n),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _reaplicarNutricao(txn, bd);
    });
  }

  /// Nutrições de UM pasto numa data, buscadas na hora no servidor (data
  /// fora do período que vem com o tabuleiro).
  Future<void> salvarNutricoesDoDia({
    required String bd,
    required int pasto,
    required String data,
    required List<Map<String, dynamic>> nutricoes,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.transaction((txn) async {
      await txn.delete(
        'mapa_nutricao_cache',
        where: 'bd = ? AND pasto_id = ? AND data = ?',
        whereArgs: [bd, pasto, data],
      );
      for (final n in nutricoes) {
        await txn.insert(
          'mapa_nutricao_cache',
          _linhaNutricao(bd, n),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
      await _reaplicarNutricao(txn, bd);
    });
  }

  Future<void> _reaplicarNutricao(DatabaseExecutor txn, String bd) async {
    final pendentes = await txn.query(
      'mapa_outbox',
      where: "bd = ? AND status = 'pendente' AND tipo IN (?, ?)",
      whereArgs: [bd, AcaoMapa.nutricaoIncluir, AcaoMapa.nutricaoExcluir],
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
  }

  /// Linhas da tabela do modal: nutrições do pasto na data (Y-m-d).
  Future<List<Map<String, Object?>>> nutricoesDoPasto(
    String bd,
    int pasto,
    String data,
  ) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'mapa_nutricao_cache',
      where: 'bd = ? AND pasto_id = ? AND data = ?',
      whereArgs: [bd, pasto, data],
      orderBy: 'id = 0, id, rowid',
    );
  }

  /// O servidor confirmou a inclusão: a linha local passa a ter o id dele
  /// (para poder ser excluída depois).
  Future<void> definirIdNutricao(String bd, String chave, int id) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'mapa_nutricao_cache',
      {'id': id},
      where: 'bd = ? AND chave = ?',
      whereArgs: [bd, chave],
    );
  }

  /// Excluir uma nutrição que ainda nem foi enviada: tira a inclusão da
  /// fila e a linha do cache (o servidor nunca fica sabendo). Devolve
  /// false se não havia inclusão pendente com essa chave.
  Future<bool> cancelarInclusaoNutricao(String bd, String chave) async {
    final db = await LocalDatabase.instance.database;
    return db.transaction((txn) async {
      final acoes = await txn.query(
        'mapa_outbox',
        columns: ['id', 'payload_json'],
        where: 'bd = ? AND tipo = ?',
        whereArgs: [bd, AcaoMapa.nutricaoIncluir],
      );
      for (final a in acoes) {
        final p = json.decode(a['payload_json'] as String) as Map;
        if (p['chave'] == chave) {
          await txn.delete(
            'mapa_outbox',
            where: 'id = ?',
            whereArgs: [a['id']],
          );
          await txn.delete(
            'mapa_nutricao_cache',
            where: 'bd = ? AND chave = ?',
            whereArgs: [bd, chave],
          );
          return true;
        }
      }
      return false;
    });
  }

  Future<void> _aplicarNutricaoIncluir(
    DatabaseExecutor txn,
    String bd,
    Map<String, dynamic> p,
  ) async {
    await txn.insert('mapa_nutricao_cache', {
      'bd': bd,
      'chave': (p['chave'] ?? '').toString(),
      'id': 0,
      'fazenda_id': _int(p['fazenda']),
      'pasto_id': _int(p['pasto']),
      'data': (p['data'] ?? '').toString(),
      'produto_id': _int(p['produto']),
      'produto': (p['produto_descricao'] ?? '').toString(),
      'unidade': (p['unidade'] ?? '').toString(),
      'quantidade': double.tryParse('${p['quantidade']}') ?? 0,
      'qtd_animais': _int(p['qtd_animais']),
      'media_cabeca': 0,
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<void> _aplicarNutricaoExcluir(
    DatabaseExecutor txn,
    String bd,
    Map<String, dynamic> p,
  ) async {
    await txn.delete(
      'mapa_nutricao_cache',
      where: 'bd = ? AND (chave = ? OR (id > 0 AND id = ?))',
      whereArgs: [bd, (p['chave'] ?? '').toString(), _int(p['id'])],
    );
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
    if (tipo == AcaoMapa.nutricaoIncluir) {
      await _aplicarNutricaoIncluir(txn, bd, payload);
    } else if (tipo == AcaoMapa.nutricaoExcluir) {
      await _aplicarNutricaoExcluir(txn, bd, payload);
    } else if (tipo == AcaoMapa.morte) {
      await _aplicarMorte(txn, bd, payload);
    } else if (tipo == AcaoMapa.transferirTudo) {
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
          // Número do lote novo só existe depois que o servidor gravar;
          // na edição pelo campo (manter_numero) o pasto fica com o que
          // já tem.
          if (payload['manter_numero'] != true) ...{
            'id_lote': 0,
            'ano_lote': 0,
          },
        },
        where: 'bd = ? AND id = ?',
        whereArgs: [bd, _int(payload['pasto'])],
      );
    } else if (tipo == AcaoMapa.transferirCategoria) {
      await _aplicarTransferenciaCategoria(txn, bd, payload);
    } else if (tipo == AcaoMapa.levarDescricaoLote) {
      await _aplicarLevarDescricao(
        txn,
        bd,
        _int(payload['origem']),
        _int(payload['destino']),
      );
    }
  }

  Future<Map<String, Object?>?> _pastoDoCache(
    DatabaseExecutor txn,
    String bd,
    int id,
  ) async {
    final l = await txn.query(
      'mapa_pastos_cache',
      columns: [
        'fazenda_id',
        'descricao_lote',
        'lotes_json',
        'id_lote',
        'ano_lote',
      ],
      where: 'bd = ? AND id = ?',
      whereArgs: [bd, id],
      limit: 1,
    );
    return l.isEmpty ? null : l.first;
  }

  /// Transferência por categoria — mesma regra do servidor
  /// (MapaGadoService::transferirCategoria): passa os primeiros animais
  /// (ordem do número do item) da categoria/sexo, com a idade calculada na
  /// data da ação; se a origem ficar vazia, valem as Premissas 1 e 6 da
  /// Descrição do Lote.
  Future<void> _aplicarTransferenciaCategoria(
    DatabaseExecutor txn,
    String bd,
    Map<String, dynamic> payload,
  ) async {
    final origem = _int(payload['origem']);
    final destino = _int(payload['destino']);
    final categoria = _int(payload['categoria']);
    final sexo = (payload['sexo'] ?? '').toString();
    final quantidade = _int(payload['quantidade']);
    final dataHora = (payload['data_hora'] ?? '').toString();
    final dia =
        DateTime.tryParse(dataHora.replaceFirst(' ', 'T')) ?? DateTime.now();

    final pOrigem = await _pastoDoCache(txn, bd, origem);
    final pDestino = await _pastoDoCache(txn, bd, destino);
    if (pOrigem == null || pDestino == null || quantidade <= 0) return;

    final faixa = await txn.query(
      'mapa_categorias_cache',
      columns: ['idade_de', 'idade_ate'],
      where: 'bd = ? AND id = ?',
      whereArgs: [bd, categoria],
      limit: 1,
    );
    if (faixa.isEmpty) return;
    final de = faixa.first['idade_de'] as int;
    final ate = faixa.first['idade_ate'] as int;

    final animais = await txn.query(
      'mapa_animais_pasto_cache',
      columns: ['numero_item', 'sexo', 'nascimento'],
      where: 'bd = ? AND pasto_id = ?',
      whereArgs: [bd, origem],
      orderBy: 'numero_item',
    );
    final itens = <int>[];
    for (final a in animais) {
      if (itens.length >= quantidade) break;
      if (sexo.isNotEmpty && a['sexo'] != sexo) continue;
      final meses = MapaTabuleiroCalculo.idadeEmMeses(
        a['nascimento'] as String?,
        dia,
      );
      if (meses >= de && meses <= ate) itens.add(a['numero_item'] as int);
    }
    if (itens.isEmpty) return;

    final noDestinoAntes =
        Sqflite.firstIntValue(
          await txn.rawQuery(
            'SELECT COUNT(*) FROM mapa_animais_pasto_cache WHERE bd = ? AND pasto_id = ?',
            [bd, destino],
          ),
        ) ??
        0;

    await txn.update(
      'mapa_animais_pasto_cache',
      {'pasto_id': destino, 'fazenda_id': pDestino['fazenda_id']},
      where: 'bd = ? AND pasto_id = ? AND numero_item IN (${itens.join(',')})',
      whereArgs: [bd, origem],
    );

    // Datas "há X dia(s)" da tela — aproximação até o próximo download
    // (a regra completa das 24h fica no servidor).
    if (noDestinoAntes == 0 && dataHora.isNotEmpty) {
      await txn.update(
        'mapa_pastos_cache',
        {'data_com_animais': dataHora},
        where: 'bd = ? AND id = ?',
        whereArgs: [bd, destino],
      );
    }

    if (animais.length == itens.length) {
      // a origem ficou vazia
      if (dataHora.isNotEmpty) {
        await txn.update(
          'mapa_pastos_cache',
          {'data_sem_animais': dataHora},
          where: 'bd = ? AND id = ?',
          whereArgs: [bd, origem],
        );
      }
      await _aplicarPremissasLote(txn, bd, origem, destino, pOrigem, pDestino);
    }
  }

  /// "Levar a Descrição do Lote": o destino recebe a descrição, os lotes
  /// e o número do lote da origem; a origem continua com a descrição e
  /// fica aguardando o número novo do servidor.
  Future<void> _aplicarLevarDescricao(
    DatabaseExecutor txn,
    String bd,
    int origem,
    int destino,
  ) async {
    final pOrigem = await _pastoDoCache(txn, bd, origem);
    if (pOrigem == null) return;
    final descOrigem = (pOrigem['descricao_lote'] ?? '').toString();
    if (descOrigem.isEmpty) return;
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
    await txn.update(
      'mapa_pastos_cache',
      {'id_lote': 0, 'ano_lote': 0},
      where: 'bd = ? AND id = ?',
      whereArgs: [bd, origem],
    );
  }

  /// Premissa 1: destino SEM descrição do lote e origem COM -> a descrição
  /// vai para o destino. Premissas 1 e 6: a origem sempre fica sem.
  Future<void> _aplicarPremissasLote(
    DatabaseExecutor txn,
    String bd,
    int origem,
    int destino,
    Map<String, Object?> pOrigem,
    Map<String, Object?> pDestino,
  ) async {
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
        columns: [
          'fazenda_id',
          'descricao_lote',
          'lotes_json',
          'id_lote',
          'ano_lote',
        ],
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
