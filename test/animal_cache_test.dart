// Valida que o autocomplete/ficha do animal funcionam 100% offline depois
// que o cache da fazenda foi baixado — sem precisar de emulador Android.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/animal_cache_dao.dart';
import 'package:boivirtual/repositories/animal_repository.dart';
import 'package:boivirtual/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  // Nome de arquivo próprio — evita "database is locked" quando o
  // `flutter test` roda vários arquivos de teste em paralelo, cada um
  // abrindo o mesmo banco físico.
  LocalDatabase.nomeArquivo = 'test_animal_cache.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null,
      );

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
  });

  test('autocomplete e ficha do animal vêm do cache local quando offline', () async {
    ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.semInternet);

    await AnimalCacheDao.instance.salvarLote([
      {
        'id': '900001',
        'fazendaId': '57',
        'codigo': 'B-000000001',
        'sexo': 'F',
        'nascimento': '2022-01-15',
        'raca': 'Nelore',
        'pelagem': 'Branca',
        'idMae': '900099',
        'brincoMae': '99',
        'ultimoPeso': '300.000',
        'DataUltimo': '2026-01-01 00:00:00',
      },
      {
        'id': '900002',
        'fazendaId': '57',
        'codigo': 'B-000000002',
        'sexo': 'M',
        'nascimento': '2021-03-20',
        'raca': 'Nelore',
        'pelagem': 'Vermelha',
      },
    ]);

    final sugestoes = await AnimalRepository.instance.buscarPorCodigo(
      termo: '0000001',
      local: '57',
      bd: 'teste_offline_pesagem',
    );
    expect(sugestoes.length, 1);
    expect(sugestoes.first['id'], '900001');

    final ficha = await AnimalRepository.instance.buscarDetalhes(
      id: '900001',
      local: '57',
      bd: 'teste_offline_pesagem',
    );
    expect(ficha['sexo'], 'F');
    expect(ficha['nascimento'], '15/01/2022');
    expect(ficha['raca'], 'Nelore');
    expect(ficha['brincoMae'], '99');

    // Busca por um animal que não existe nem no cache -> lista vazia, sem
    // tentar rede (estamos "offline"), sem travar/lançar exceção.
    final semResultado = await AnimalRepository.instance.buscarPorCodigo(
      termo: '9999999',
      local: '57',
      bd: 'teste_offline_pesagem',
    );
    expect(semResultado, isEmpty);
  });
}
