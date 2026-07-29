import 'package:sqflite/sqflite.dart';
import '../local_database.dart';

/// DAO da tabela animais_cache — cadastro de animais das fazendas do
/// usuário replicado localmente, para autocomplete e ficha funcionarem sem
/// internet.
class AnimalCacheDao {
  AnimalCacheDao._();
  static final AnimalCacheDao instance = AnimalCacheDao._();

  Future<void> salvarLote(String fazendaId, List<Map<String, dynamic>> animais) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final a in animais) {
      batch.insert('animais_cache', {
        'id_animal': a['id'].toString(),
        'fazenda_id': fazendaId,
        'codigo': a['codigo']?.toString(),
        'sexo': a['sexo']?.toString(),
        'nascimento': a['nascimento']?.toString(),
        'raca': a['raca']?.toString(),
        'pelagem': a['pelagem']?.toString(),
        'id_mae': a['idMae']?.toString(),
        'brinco_mae': a['brincoMae']?.toString(),
        'ultimo_peso': a['ultimoPeso']?.toString(),
        'data_ultimo_peso': a['DataUltimo']?.toString(),
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

  /// Autocomplete por código (alfa ou numérico) — busca em memória sobre o
  /// cache da fazenda, comparando os códigos já sem traço/zeros à esquerda
  /// para tolerar o jeito como o usuário realmente digita (ver
  /// _normalizarCodigo).
  Future<List<Map<String, dynamic>>> buscarPorCodigo(
    String fazendaId,
    String termo,
  ) async {
    final db = await LocalDatabase.instance.database;
    final todos = await db.query(
      'animais_cache',
      where: 'fazenda_id = ?',
      whereArgs: [fazendaId],
      orderBy: 'codigo ASC',
    );

    final termoNormalizado = _normalizarCodigo(termo.trim());
    final encontrados = todos.where((linha) {
      final codigo = linha['codigo']?.toString() ?? '';
      return _normalizarCodigo(codigo).contains(termoNormalizado);
    }).take(10).toList();

    return encontrados;
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
