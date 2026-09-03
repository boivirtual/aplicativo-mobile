import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  test('listar pesagens_locais do bd 71746307668', () async {
    sqfliteFfiInit();
    final db = await databaseFactoryFfi.openDatabase(
      r'C:\Users\George\AppData\Local\Temp\boivirtual_offline.db',
    );

    final linhas = await db.query(
      'pesagens_locais',
      where: 'bd = ?',
      whereArgs: ['71746307668'],
      orderBy: 'id_local ASC',
    );
    // ignore: avoid_print
    print('Total: ${linhas.length}');
    for (final l in linhas) {
      // ignore: avoid_print
      print(
        'id_local=${l['id_local']} id_servidor=${l['id_servidor']} '
        'fazenda_id=${l['fazenda_id']} lote=${l['lote']} '
        'finalizada=${l['finalizada']} status_sync=${l['status_sync']} '
        'criado_em=${l['criado_em']}',
      );
    }

    await db.close();
  });
}
