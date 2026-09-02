import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('localizar pesagem presa (27/08/2026, sem itens, só offline)', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      r'C:\Users\George\AppData\Local\Temp\boivirtual_offline.db',
    );

    final candidatas = await db.query(
      'pesagens_locais',
      where: "criado_em LIKE ?",
      whereArgs: ['2026-08-27%'],
    );
    // ignore: avoid_print
    print('Pesagens criadas em 27/08/2026: $candidatas');

    for (final p in candidatas) {
      final idLocal = p['id_local'];
      final itens = await db.query(
        'itens_pesagem_locais',
        where: 'pesagem_id_local = ?',
        whereArgs: [idLocal],
      );
      // ignore: avoid_print
      print('--- pesagem id_local=$idLocal tem ${itens.length} item(ns) ---');
    }

    await db.close();
  });
}
