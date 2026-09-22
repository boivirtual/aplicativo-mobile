import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main(List<String> args) async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(args[0]);
  final rows = await db.rawQuery(
    "SELECT id_local, id_servidor, bd, fazenda_id, epoca_id, lote, criado_em, finalizada, status_sync "
    "FROM pesagens_locais WHERE criado_em LIKE '2026-08-27%'",
  );
  for (final r in rows) {
    print(r);
  }
  await db.close();
}
