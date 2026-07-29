// Valida a tela "Pendências de revisão": tradução das operações recusadas
// pelo servidor pra algo legível, e as ações de reenviar/descartar.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/outbox_dao.dart';
import 'package:boivirtual/repositories/pesagem_repository.dart';
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
    ConnectivityService.instance.forcarNivelParaTeste(
      NivelConexao.semInternet,
    );
  });

  test(
    'operação SALVAR_ITEM em conflito aparece traduzida com lote e animal',
    () async {
      final idLocal = await PesagemLocalDao.instance.inserir(
        uuid: 'pesagem-conflito',
        bd: '71746307668',
        fazendaId: '56',
        epocaId: '003',
        lote: 'Venda II',
        qtdAPesar: 1,
        criteriosLista: [],
      );
      await PesagemLocalDao.instance.confirmarSincronizacao(idLocal, 909);

      final outboxId = await OutboxDao.instance.enfileirar(
        tipoOperacao: TipoOperacaoOutbox.salvarItem,
        entidadeUuid: 'item-uuid-1',
        payload: {
          'bd': '71746307668',
          'uuid_app': 'pesagem-conflito',
          'item': {'codigo_animal': 'C-87', 'uuid_app': 'item-uuid-1'},
        },
      );
      await OutboxDao.instance.marcarConflito(
        outboxId,
        'Pesagem não encontrada ou não pertence ao aplicativo.',
      );

      final pendencias = await PesagemRepository.instance
          .listarPendenciasRevisao();
      expect(pendencias.length, 1);
      expect(pendencias.first['lote'], 'Venda II');
      expect(pendencias.first['animalCodigo'], 'C-87');
      expect(
        pendencias.first['mensagemErro'],
        'Pesagem não encontrada ou não pertence ao aplicativo.',
      );

      // Tentar de novo: volta pra pendente, some da lista de conflitos.
      await PesagemRepository.instance.reenviarPendencia(outboxId);
      final aposReenvio = await PesagemRepository.instance
          .listarPendenciasRevisao();
      expect(aposReenvio, isEmpty);
      final naFilaNormal = await OutboxDao.instance.listarPendentes();
      expect(naFilaNormal.any((o) => o['id'] == outboxId), isTrue);
    },
  );

  test('descartar remove a pendência sem mexer nos dados locais', () async {
    final idLocal = await PesagemLocalDao.instance.inserir(
      uuid: 'pesagem-conflito-2',
      bd: '71746307668',
      fazendaId: '56',
      epocaId: '003',
      lote: 'Teste',
      qtdAPesar: 1,
      criteriosLista: [],
    );

    final outboxId = await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.criarPesagem,
      entidadeUuid: 'pesagem-conflito-2',
      payload: {'lote': 'Teste'},
    );
    await OutboxDao.instance.marcarConflito(outboxId, 'Erro ao criar pesagem');

    await PesagemRepository.instance.descartarPendencia(outboxId);

    final pendencias = await PesagemRepository.instance
        .listarPendenciasRevisao();
    expect(pendencias, isEmpty);

    // O registro local da pesagem continua existindo (descartar não apaga
    // dado nenhum, só desiste de tentar enviar).
    final local = await PesagemLocalDao.instance.buscarPorIdLocal(idLocal);
    expect(local, isNotNull);
  });
}
