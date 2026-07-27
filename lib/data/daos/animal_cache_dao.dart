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

  /// Autocomplete por código (alfa ou numérico), igual à busca LIKE que a
  /// API fazia — sem distinguir maiúsculas/minúsculas.
  Future<List<Map<String, dynamic>>> buscarPorCodigo(
    String fazendaId,
    String termo,
  ) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'animais_cache',
      where: 'fazenda_id = ? AND codigo LIKE ?',
      whereArgs: [fazendaId, '%$termo%'],
      orderBy: 'codigo ASC',
      limit: 10,
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
