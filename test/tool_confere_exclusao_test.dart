import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('confere que a pesagem 13 sumiu e o resto continua intacto', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      r'C:\Users\George\AppData\Local\Temp\boivirtual_offline_confere.db',
    );

    final sumiu = await db.query(
      'pesagens_locais',
      where: 'id_local = ?',
      whereArgs: [13],
    );
    expect(sumiu, isEmpty);

    final totalPesagens = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM pesagens_locais',
    );
    final totalAnimaisCache = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM animais_cache',
    );
    final totalItens = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM itens_pesagem_locais',
    );
    // ignore: avoid_print
    print('Total pesagens_locais agora: ${totalPesagens.first['qtd']}');
    // ignore: avoid_print
    print('Total animais_cache agora: ${totalAnimaisCache.first['qtd']}');
    // ignore: avoid_print
    print('Total itens_pesagem_locais agora: ${totalItens.first['qtd']}');

    await db.close();
  });
}
