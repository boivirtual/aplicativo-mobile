import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/pesagem_local_dao.dart';

void main() {
  test('excluir a pesagem presa (id_local=13, lote teste, 27/08/2026)', () async {
    sqfliteFfiInit();
    // Faz o LocalDatabase apontar pro arquivo puxado do celular, em vez de
    // um banco de teste novo — assim a exclusão usa o DAO de verdade (mesmo
    // código do app) só que sobre o arquivo real.
    LocalDatabase.nomeArquivo = 'boivirtual_offline.db';
    await databaseFactoryFfi.setDatabasesPath(
      r'C:\Users\George\AppData\Local\Temp',
    );

    final db = await LocalDatabase.instance.database;

    final antes = await db.query(
      'pesagens_locais',
      where: 'id_local = ?',
      whereArgs: [13],
    );
    expect(antes.length, 1);
    expect(antes.first['lote'], 'teste');
    expect(antes.first['finalizada'], 'N');
    // ignore: avoid_print
    print('Confirmado antes de excluir: ${antes.first}');

    await PesagemLocalDao.instance.excluirPorIdLocal(13);

    final depois = await db.query(
      'pesagens_locais',
      where: 'id_local = ?',
      whereArgs: [13],
    );
    expect(depois, isEmpty);
    // ignore: avoid_print
    print('Excluída com sucesso.');

    await db.close();
  });
}
