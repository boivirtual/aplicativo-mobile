import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> main() async {
  sqfliteFfiInit();
  final db = await databaseFactoryFfi.openDatabase(
    r'C:\Users\George\AppData\Local\Temp\boivirtual_offline.db',
  );

  final alvo = await db.query(
    'itens_pesagem_locais',
    columns: ['pesagem_id_local', 'codigo_animal'],
    where: 'codigo_animal IN (?, ?)',
    whereArgs: ['B-114', 'B-813'],
  );
  print('Itens-alvo (pra achar o pesagem_id_local): $alvo');

  if (alvo.isEmpty) {
    print('Nao achou B-114/B-813 nesse banco.');
    await db.close();
    return;
  }

  final pesagemIdLocal = alvo.first['pesagem_id_local'];
  print('\n=== pesagem_id_local = $pesagemIdLocal ===\n');

  final ordemNova = await db.query(
    'itens_pesagem_locais',
    columns: [
      'codigo_animal',
      'numero_item_local',
      'numero_item_servidor',
      'criado_em',
      'atualizado_em',
      'status_sync',
    ],
    where: 'pesagem_id_local = ?',
    whereArgs: [pesagemIdLocal],
    orderBy:
        'CASE WHEN numero_item_servidor IS NULL THEN 0 ELSE 1 END ASC, '
        'numero_item_servidor DESC, '
        'numero_item_local DESC',
  );
  print('--- Ordem que o app usa agora (query nova) ---');
  for (final r in ordemNova) {
    print(r);
  }

  await db.close();
}
