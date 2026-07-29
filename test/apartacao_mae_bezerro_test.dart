// Valida os alertas de "mãe/bezerro com apartação em lote aberto" (ficha
// do animal), que dependem só do banco local — sem precisar de emulador
// Android nem de rede.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/animal_cache_dao.dart';
import 'package:boivirtual/data/daos/pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/item_pesagem_local_dao.dart';
import 'package:boivirtual/repositories/animal_repository.dart';
import 'package:boivirtual/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null,
      );

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
  });

  String isoHaMeses(int meses) {
    final agora = DateTime.now();
    return DateTime(agora.year, agora.month - meses, agora.day)
        .toIso8601String()
        .split('T')
        .first;
  }

  test(
    'mãe pesada com apartação em outro lote aparece na ficha do bezerro',
    () async {
      ConnectivityService.instance.forcarNivelParaTeste(
        NivelConexao.semInternet,
      );

      await AnimalCacheDao.instance.salvarLote('56', [
        {
          'id': '900001',
          'codigo': 'C-000000087',
          'sexo': 'F',
          'nascimento': '2013-01-01',
          'raca': 'Nelore',
          'pelagem': 'Salira Pintada',
        },
        {
          'id': '900002',
          'codigo': 'B-000001129',
          'sexo': 'F',
          'nascimento': isoHaMeses(2),
          'raca': 'Nelore',
          'pelagem': 'Mestiça Pintada',
          'idMae': '900001',
          'brincoMae': 'C-87',
        },
      ]);

      final idLoteMae = await PesagemLocalDao.instance.inserir(
        uuid: 'pesagem-mae',
        bd: '71746307668',
        fazendaId: '56',
        epocaId: '003',
        lote: 'Desmama',
        qtdAPesar: 2,
        criteriosLista: [],
      );
      await ItemPesagemLocalDao.instance.inserir(
        pesagemIdLocal: idLoteMae,
        uuid: 'item-mae',
        numeroItemLocal: 1,
        campos: {
          'id_animal': '900001',
          'codigo_animal': 'C-87',
          'peso': '495',
          'criterio_apartacao': '4',
        },
      );

      // Digitando o bezerro (900002): tem que mostrar a apartação da mãe.
      final fichaBezerro = await AnimalRepository.instance.buscarDetalhes(
        id: '900002',
        local: '56',
        bd: '71746307668',
      );
      expect(fichaBezerro['criterioApartacaoMae'], '4');
      expect(fichaBezerro['bezerroApartacaoMae'], isNull);
    },
  );

  test(
    'bezerro não desmamado pesado com apartação em outro lote aparece na ficha da mãe',
    () async {
      ConnectivityService.instance.forcarNivelParaTeste(
        NivelConexao.semInternet,
      );

      await AnimalCacheDao.instance.salvarLote('56', [
        {
          'id': '900001',
          'codigo': 'C-000000087',
          'sexo': 'F',
          'nascimento': '2013-01-01',
          'raca': 'Nelore',
          'pelagem': 'Salira Pintada',
        },
        {
          'id': '900002',
          'codigo': 'B-000001129',
          'sexo': 'F',
          'nascimento': isoHaMeses(2),
          'raca': 'Nelore',
          'pelagem': 'Mestiça Pintada',
          'idMae': '900001',
          'brincoMae': 'C-87',
        },
      ]);

      final idLoteBezerro = await PesagemLocalDao.instance.inserir(
        uuid: 'pesagem-bezerro',
        bd: '71746307668',
        fazendaId: '56',
        epocaId: '003',
        lote: 'Venda',
        qtdAPesar: 2,
        criteriosLista: [],
      );
      await ItemPesagemLocalDao.instance.inserir(
        pesagemIdLocal: idLoteBezerro,
        uuid: 'item-bezerro',
        numeroItemLocal: 1,
        campos: {
          'id_animal': '900002',
          'codigo_animal': 'B-1129',
          'peso': '44',
          'criterio_apartacao': '1',
        },
      );

      // Digitando a mãe (900001): tem que mostrar o bezerro e a apartação dele.
      final fichaMae = await AnimalRepository.instance.buscarDetalhes(
        id: '900001',
        local: '56',
        bd: '71746307668',
      );
      expect(fichaMae['criterioApartacaoMae'], isNull);
      expect(fichaMae['bezerroApartacaoMae'], {
        'codigo': 'B-000001129',
        'criterio': '1',
      });
    },
  );

  test(
    'bezerro já desmamado (peso_desmama preenchido) não gera alerta',
    () async {
      ConnectivityService.instance.forcarNivelParaTeste(
        NivelConexao.semInternet,
      );

      await AnimalCacheDao.instance.salvarLote('56', [
        {
          'id': '900001',
          'codigo': 'C-000000087',
          'sexo': 'F',
          'nascimento': '2013-01-01',
        },
        {
          'id': '900002',
          'codigo': 'B-000001129',
          'sexo': 'F',
          'nascimento': isoHaMeses(2),
          'idMae': '900001',
          'pesoDesmama': '180',
        },
      ]);

      final idLote = await PesagemLocalDao.instance.inserir(
        uuid: 'pesagem-desmamado',
        bd: '71746307668',
        fazendaId: '56',
        epocaId: '003',
        lote: 'Venda',
        qtdAPesar: 1,
        criteriosLista: [],
      );
      await ItemPesagemLocalDao.instance.inserir(
        pesagemIdLocal: idLote,
        uuid: 'item-desmamado',
        numeroItemLocal: 1,
        campos: {
          'id_animal': '900002',
          'codigo_animal': 'B-1129',
          'peso': '180',
          'criterio_apartacao': '1',
        },
      );

      final fichaMae = await AnimalRepository.instance.buscarDetalhes(
        id: '900001',
        local: '56',
        bd: '71746307668',
      );
      expect(fichaMae['bezerroApartacaoMae'], isNull);
    },
  );
}
