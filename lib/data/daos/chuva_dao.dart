import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import '../local_database.dart';

/// DAO da tabela chuva_cache — cadastro de precipitação das fazendas do
/// usuário, replicado localmente para a tela de Chuva funcionar offline
/// (autocomplete/ficha do animal já funcionam do mesmo jeito, ver
/// AnimalCacheDao) e permitir lançar um volume sem internet.
class ChuvaDao {
  ChuvaDao._();
  static final ChuvaDao instance = ChuvaDao._();

  /// Grava um lançamento feito neste aparelho — sempre local primeiro,
  /// nunca espera rede (mesma filosofia da pesagem: o vaqueiro não pode
  /// ficar esperando o app responder). Fica com sincronizado = 0 até
  /// ChuvaSyncService confirmar com o servidor.
  Future<void> salvarLocal({
    required String bd,
    required String fazendaId,
    required String data,
    required double volume,
    String? usuario,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.insert('chuva_cache', {
      'bd': bd,
      'fazenda_id': fazendaId,
      'data': data,
      'volume': volume,
      'id_servidor': null,
      'usuario': usuario,
      'sincronizado': 0,
      'atualizado_em': DateTime.now().toIso8601String(),
    }, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Grava (ou atualiza) o que veio do servidor — usado tanto pela
  /// sincronização inicial (download em massa) quanto pela confirmação
  /// pontual depois de subir um lançamento pendente.
  ///
  /// Nunca sobrescreve uma linha que ainda está pendente de envio
  /// (sincronizado = 0): se o usuário editou um dia offline e a
  /// sincronização inicial baixa o valor antigo desse mesmo dia (ainda não
  /// atualizado no servidor), o lançamento local pendente prevalece — ele
  /// mesmo vai sobrescrever o servidor assim que conseguir subir.
  Future<void> salvarLoteDoServidor(
    String bd,
    List<Map<String, dynamic>> chuvas,
  ) async {
    final db = await LocalDatabase.instance.database;

    final pendentes = await db.query(
      'chuva_cache',
      columns: ['fazenda_id', 'data'],
      where: 'bd = ? AND sincronizado = 0',
      whereArgs: [bd],
    );
    final chavesPendentes = pendentes
        .map((r) => '${r['fazenda_id']}|${r['data']}')
        .toSet();

    final agora = DateTime.now().toIso8601String();
    final batch = db.batch();
    for (final c in chuvas) {
      final fazendaId = c['local'].toString();
      final data = c['data'].toString();
      if (chavesPendentes.contains('$fazendaId|$data')) continue;

      batch.insert('chuva_cache', {
        'bd': bd,
        'fazenda_id': fazendaId,
        'data': data,
        'volume': (c['volume'] as num?)?.toDouble() ?? 0,
        'id_servidor': int.tryParse(c['id'].toString()),
        'usuario': null,
        'sincronizado': 1,
        'atualizado_em': agora,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  Future<void> marcarSincronizado({
    required String bd,
    required String fazendaId,
    required String data,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'chuva_cache',
      {'sincronizado': 1},
      where: 'bd = ? AND fazenda_id = ? AND data = ?',
      whereArgs: [bd, fazendaId, data],
    );
  }

  /// Lançamentos feitos neste aparelho que ainda não foram confirmados
  /// pelo servidor — o que ChuvaSyncService tenta reenviar.
  Future<List<Map<String, dynamic>>> listarPendentes(String bd) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'chuva_cache',
      where: 'bd = ? AND sincronizado = 0',
      whereArgs: [bd],
    );
  }

  Future<int> contarPendentes(String bd) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM chuva_cache WHERE bd = ? AND sincronizado = 0',
      [bd],
    );
    return (r.first['qtd'] as int?) ?? 0;
  }

  /// Volume já lançado numa data/fazenda específica — usado para avisar o
  /// usuário antes de sobrescrever (mesmo aviso que o sistema web mostra).
  Future<Map<String, dynamic>?> buscarPorData({
    required String bd,
    required String fazendaId,
    required String data,
  }) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'chuva_cache',
      where: 'bd = ? AND fazenda_id = ? AND data = ?',
      whereArgs: [bd, fazendaId, data],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  /// Precipitação x dias chuvosos por mês, no ano informado — sempre 12
  /// itens (jan..dez), mesmo sem lançamento no mês (mm/dias = 0). Mesma
  /// contagem do sistema web: "dia chuvoso" é o dia com volume > 0.
  Future<List<Map<String, num>>> agregarPorMes({
    required String bd,
    required String fazendaId,
    required int ano,
  }) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.rawQuery(
      '''
      SELECT CAST(strftime('%m', data) AS INTEGER) AS mes,
             SUM(volume) AS mm,
             SUM(CASE WHEN volume > 0 THEN 1 ELSE 0 END) AS dias
        FROM chuva_cache
       WHERE bd = ? AND fazenda_id = ? AND strftime('%Y', data) = ?
       GROUP BY mes
      ''',
      [bd, fazendaId, ano.toString().padLeft(4, '0')],
    );

    final porMes = <int, Map<String, num>>{
      for (var m = 1; m <= 12; m++) m: {'mes': m, 'mm': 0, 'dias': 0},
    };
    for (final linha in linhas) {
      final mes = linha['mes'] as int;
      porMes[mes] = {
        'mes': mes,
        'mm': (linha['mm'] as num?) ?? 0,
        'dias': (linha['dias'] as num?) ?? 0,
      };
    }
    return porMes.values.toList();
  }

  /// Precipitação x dias chuvosos por ano, nos últimos 5 anos (anoFinal-4
  /// até anoFinal) — sempre 5 itens.
  Future<List<Map<String, num>>> agregarPorAno({
    required String bd,
    required String fazendaId,
    required int anoFinal,
  }) async {
    final anoInicial = anoFinal - 4;
    final db = await LocalDatabase.instance.database;
    final linhas = await db.rawQuery(
      '''
      SELECT CAST(strftime('%Y', data) AS INTEGER) AS ano,
             SUM(volume) AS mm,
             SUM(CASE WHEN volume > 0 THEN 1 ELSE 0 END) AS dias
        FROM chuva_cache
       WHERE bd = ? AND fazenda_id = ?
         AND CAST(strftime('%Y', data) AS INTEGER) BETWEEN ? AND ?
       GROUP BY ano
      ''',
      [bd, fazendaId, anoInicial, anoFinal],
    );

    final porAno = <int, Map<String, num>>{
      for (var a = anoInicial; a <= anoFinal; a++)
        a: {'ano': a, 'mm': 0, 'dias': 0},
    };
    for (final linha in linhas) {
      final ano = linha['ano'] as int;
      porAno[ano] = {
        'ano': ano,
        'mm': (linha['mm'] as num?) ?? 0,
        'dias': (linha['dias'] as num?) ?? 0,
      };
    }
    return porAno.values.toList();
  }
}
