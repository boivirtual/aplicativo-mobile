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

  test('download completo remove do aparelho os animais que saíram do '
      'servidor; morte aceita inativa o animal na hora', () async {
    Map<String, dynamic> animal(String id, String codigo) => {
      'id': id,
      'fazendaId': '57',
      'codigo': codigo,
      'sexo': 'F',
      'nascimento': '2022-01-15',
      'ativo': 'S',
    };
    Future<List<String>> codigos() async => [
      for (final a in await AnimalCacheDao.instance.buscarPorCodigo('57', '105'))
        a['codigo'].toString(),
    ];

    await AnimalCacheDao.instance.salvarLote([
      animal('000006612', 'B-000001053'),
      animal('000006613', 'B-000001054'),
    ]);
    expect(await codigos(), ['B-000001053', 'B-000001054']);

    // Morte aceita pelo servidor: some da busca sem esperar o download.
    await AnimalCacheDao.instance.marcarInativo(6612);
    expect(await codigos(), ['B-000001054']);

    // Próximo download completo já não traz o 1054 (vendido/baixado).
    await Future.delayed(const Duration(milliseconds: 5));
    await AnimalCacheDao.instance.salvarLote([
      animal('000006614', 'B-000001055'),
    ], removerAusentes: true);
    expect(await codigos(), ['B-000001055']);
    expect(await AnimalCacheDao.instance.contarTotal(), 1);

    // Lote vazio (falha do servidor) não apaga o cadastro.
    await AnimalCacheDao.instance.salvarLote([], removerAusentes: true);
    expect(await AnimalCacheDao.instance.contarTotal(), 1);
  });

  test('Nascimento: lista do Nº Mãe segue os critérios do web (fêmea ativa '
      'da fazenda, com mais de 7 meses, em ordem de número)', () async {
    final hoje = DateTime.now();
    // nascida há exatamente [meses] meses e [dias] dias a menos
    String nasc(int meses, {int diasAMenos = 0}) {
      final d = DateTime(
        hoje.year,
        hoje.month - meses,
        hoje.day,
      ).add(Duration(days: diasAMenos));
      return '${d.year}-${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';
    }

    Map<String, dynamic> animal(
      String id,
      String codigo, {
      String sexo = 'F',
      String fazenda = '57',
      String ativo = 'S',
      String? nascimento,
    }) => {
      'id': id,
      'fazendaId': fazenda,
      'codigo': codigo,
      'sexo': sexo,
      'nascimento': nascimento ?? '2020-01-15',
      'ativo': ativo,
    };

    await AnimalCacheDao.instance.salvarLote([
      animal('1', 'B-000000210'),
      animal('2', '000000021'),
      animal('3', 'C-000000021', sexo: 'M'), // macho
      animal('4', 'D-000000021', fazenda: '58'), // outra fazenda
      animal('5', 'E-000000021', ativo: 'N'), // inativa
      animal('6', 'F-000000021', nascimento: nasc(7)), // 7 meses: não
      animal('7', 'G-000000021', nascimento: nasc(8)), // 8 meses: sim
      // falta 1 dia para completar 8 meses: ainda 7 completos
      animal('8', 'H-000000021', nascimento: nasc(8, diasAMenos: 1)),
    ]);

    final lista = await AnimalCacheDao.instance.buscarFemeasParaNascimento(
      '57',
      '21',
    );
    expect(
      [for (final a in lista) a['codigo']],
      ['000000021', 'G-000000021', 'B-000000210'],
    );
  });
}
