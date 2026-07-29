import 'package:sqflite/sqflite.dart';
import '../local_database.dart';

/// DAO da tabela animais_cache — cadastro de animais das fazendas do
/// usuário replicado localmente, para autocomplete e ficha funcionarem sem
/// internet.
class AnimalCacheDao {
  AnimalCacheDao._();
  static final AnimalCacheDao instance = AnimalCacheDao._();

  Future<void> salvarLote(
    String fazendaId,
    List<Map<String, dynamic>> animais, {
    String? fazendaNome,
  }) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final a in animais) {
      batch.insert('animais_cache', {
        'id_animal': a['id'].toString(),
        'fazenda_id': fazendaId,
        'fazenda_nome': fazendaNome,
        'codigo': a['codigo']?.toString(),
        'sexo': a['sexo']?.toString(),
        'nascimento': a['nascimento']?.toString(),
        'raca': a['raca']?.toString(),
        'pelagem': a['pelagem']?.toString(),
        'id_mae': a['idMae']?.toString(),
        'brinco_mae': a['brincoMae']?.toString(),
        'ultimo_peso': a['ultimoPeso']?.toString(),
        'data_ultimo_peso': a['DataUltimo']?.toString(),
        'peso_desmama': a['pesoDesmama']?.toString(),
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<bool> temCacheParaFazenda(String fazendaId) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM animais_cache WHERE fazenda_id = ?',
      [fazendaId],
    );
    return ((r.first['qtd'] as int?) ?? 0) > 0;
  }

  /// true se existe cache de QUALQUER fazenda — usado pela "Consultar Mãe",
  /// que busca em todas as fazendas do usuário, não numa fazenda específica.
  Future<bool> temCacheGlobal() async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery('SELECT COUNT(*) as qtd FROM animais_cache');
    return ((r.first['qtd'] as int?) ?? 0) > 0;
  }

  /// Remove o traço e os zeros à esquerda do número (ex: "C-000000087" ->
  /// "C87", "000001874" -> "1874") para comparar do mesmo jeito que o
  /// usuário digita o código na busca — sem isso, "C87" nunca batia com o
  /// valor salvo no cache ("C-000000087"), mesmo o animal existindo.
  String _normalizarCodigo(String codigo) {
    String semTraco;
    if (codigo.contains('-')) {
      final partes = codigo.split('-');
      final numero = partes[1].replaceFirst(RegExp(r'^0+'), '');
      semTraco = '${partes[0]}${numero.isEmpty ? "0" : numero}';
    } else {
      final numero = codigo.replaceFirst(RegExp(r'^0+'), '');
      semTraco = numero.isEmpty ? "0" : numero;
    }
    return semTraco.toUpperCase();
  }

  /// Parte numérica do código (ex: "C-000000087" -> "000000087",
  /// "000001874" -> "000001874") — sempre com a mesma quantidade de dígitos
  /// nesta base, então comparar como texto já dá a ordem numérica certa.
  /// Regra do sistema (igual à busca online, que usa
  /// "ORDER BY tbl_animal_codigo_numerico ASC"): animais com o mesmo número
  /// mas prefixos de letra diferentes (ex: B-87 e C-87) têm que aparecer
  /// juntos, antes de números maiores que só coincidem ter "87" no meio
  /// (ex: 1874, 6587) — NÃO pode ordenar pelo código completo (isso jogaria
  /// os números "puros" para o começo da lista, na frente de B-87/C-87).
  String _parteNumerica(String codigo) {
    return codigo.contains('-') ? codigo.split('-').last : codigo;
  }

  /// Autocomplete por código (alfa ou numérico) — busca em memória sobre o
  /// cache da fazenda, comparando os códigos já sem traço/zeros à esquerda
  /// para tolerar o jeito como o usuário realmente digita (ver
  /// _normalizarCodigo), e ordenando pelo número (ver _parteNumerica).
  Future<List<Map<String, dynamic>>> buscarPorCodigo(
    String fazendaId,
    String termo,
  ) async {
    final db = await LocalDatabase.instance.database;
    final todos = await db.query(
      'animais_cache',
      where: 'fazenda_id = ?',
      whereArgs: [fazendaId],
    );

    final termoNormalizado = _normalizarCodigo(termo.trim());
    final encontrados = todos.where((linha) {
      final codigo = linha['codigo']?.toString() ?? '';
      return _normalizarCodigo(codigo).contains(termoNormalizado);
    }).toList();

    encontrados.sort((a, b) => _parteNumerica(a['codigo']?.toString() ?? '')
        .compareTo(_parteNumerica(b['codigo']?.toString() ?? '')));

    return encontrados.take(10).toList();
  }

  /// true se o animal é uma fêmea com mais de 12 meses — mesma regra usada
  /// na busca global do servidor (AnimalDao::getAnimalByIdLike, ramo
  /// "local == 0"), pra "Consultar Mãe" oferecer as mesmas candidatas
  /// offline e online.
  bool _femeaAdulta(Map<String, dynamic> linha) {
    if (linha['sexo']?.toString() != 'F') return false;
    final nascimento = DateTime.tryParse(linha['nascimento']?.toString() ?? '');
    if (nascimento == null) return false;
    final agora = DateTime.now();
    final diferencaMeses =
        (agora.year - nascimento.year) * 12 + (agora.month - nascimento.month);
    return diferencaMeses > 12;
  }

  /// Busca por código em TODAS as fazendas cacheadas (não só uma) — usado
  /// pela "Consultar Mãe", que precisa achar a mãe em qualquer fazenda que
  /// o usuário tenha acesso, só entre fêmeas adultas (mesma regra do
  /// servidor).
  Future<List<Map<String, dynamic>>> buscarPorCodigoGlobalFemeaAdulta(
    String termo,
  ) async {
    final db = await LocalDatabase.instance.database;
    final todos = await db.query('animais_cache');

    final termoNormalizado = _normalizarCodigo(termo.trim());
    final encontrados = todos.where((linha) {
      if (!_femeaAdulta(linha)) return false;
      final codigo = linha['codigo']?.toString() ?? '';
      return _normalizarCodigo(codigo).contains(termoNormalizado);
    }).toList();

    encontrados.sort((a, b) => _parteNumerica(a['codigo']?.toString() ?? '')
        .compareTo(_parteNumerica(b['codigo']?.toString() ?? '')));

    return encontrados.take(10).toList();
  }

  /// Todos os filhos (de qualquer fazenda) de um animal, pela ficha da mãe.
  Future<List<Map<String, dynamic>>> buscarFilhosPorIdMae(String idMae) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'animais_cache',
      where: 'id_mae = ?',
      whereArgs: [idMae],
      orderBy: 'id_animal DESC',
    );
  }

  Future<Map<String, dynamic>?> buscarPorId(String idAnimal) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'animais_cache',
      where: 'id_animal = ?',
      whereArgs: [idAnimal],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  Future<void> atualizarLoteAberto(
    String idAnimal, {
    String? loteAberto,
    String? pesagemIdLoteAberto,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'animais_cache',
      {
        'lote_aberto': loteAberto,
        'pesagem_id_lote_aberto': pesagemIdLoteAberto,
      },
      where: 'id_animal = ?',
      whereArgs: [idAnimal],
    );
  }
}
