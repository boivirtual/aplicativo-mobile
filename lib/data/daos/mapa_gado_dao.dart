import 'package:sqflite/sqflite.dart';
import '../../utils/mapa_tabuleiro_calculo.dart';
import '../local_database.dart';

/// DAO do cache do Mapa de Gado (Tabuleiro) — pastos, animais no pasto e
/// faixas de categoria das fazendas do usuário, replicados localmente para
/// a tela funcionar offline. Por enquanto somente leitura: cada download
/// substitui por inteiro o que havia da fazenda.
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
    required List<Map<String, dynamic>> pastos,
    required List<Map<String, dynamic>> animais,
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
        batch.insert('mapa_pastos_cache', {
          'bd': bd,
          'id': _int(p['id']),
          'fazenda_id': _int(p['local']),
          'descricao': (p['descricao'] ?? '').toString(),
          'modulo': _int(p['modulo']),
          'capim': (p['capim'] ?? '').toString(),
          'categorias': (p['categorias'] ?? '').toString(),
          'ordem': _int(p['ordem']),
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
    });
  }

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

  Future<List<PastoMapa>> pastos(String bd, int fazendaId) async {
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
      ],
      where: 'bd = ? AND fazenda_id = ?',
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
          ),
        )
        .toList();
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

  static int _int(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;
}
