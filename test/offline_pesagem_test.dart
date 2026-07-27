// Teste de verificação manual (não faz parte do CI) da persistência local e
// da lógica offline-first do módulo de Pesagem. Roda no desktop via
// sqflite_common_ffi, sem precisar de emulador Android.
//
// Rodar com: flutter test test/offline_pesagem_test.dart
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/item_pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/outbox_dao.dart';
import 'package:boivirtual/repositories/pesagem_repository.dart';
import 'package:boivirtual/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  // O plugin connectivity_plus não tem implementação nativa no ambiente de
  // teste (sem device/emulador) — sem esse mock, o construtor do
  // ConnectivityService dispara uma MissingPluginException assíncrona que
  // "vaza" para o próximo teste. O nível real é sobrescrito por
  // forcarNivelParaTeste() em cada teste que precisa dele de qualquer forma.
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null,
      );

  setUp(() async {
    // Limpa todas as tabelas antes de cada teste, para isolar os casos
    // (o LocalDatabase é um singleton com a mesma conexão durante todo o
    // arquivo de teste — resetarParaTeste() existe exatamente para isso).
    await LocalDatabase.instance.resetarParaTeste();
  });

  group('DAOs locais', () {
    test('PesagemLocalDao: inserir, buscar por uuid/id local/id servidor', () async {
      final idLocal = await PesagemLocalDao.instance.inserir(
        uuid: 'uuid-1',
        bd: '97174041604',
        fazendaId: '57',
        epocaId: '011',
        lote: 'Lote Teste',
        qtdAPesar: 10,
        criteriosLista: ['Apartar'],
      );

      final porUuid = await PesagemLocalDao.instance.buscarPorUuid('uuid-1');
      expect(porUuid, isNotNull);
      expect(porUuid!['id_local'], idLocal);
      expect(porUuid['id_servidor'], isNull);
      expect(porUuid['status_sync'], StatusSyncPesagem.pendente);

      await PesagemLocalDao.instance.confirmarSincronizacao(idLocal, 999);
      final porServidor = await PesagemLocalDao.instance.buscarPorIdServidor(999);
      expect(porServidor, isNotNull);
      expect(porServidor!['status_sync'], StatusSyncPesagem.sincronizado);

      final porTelaPositivo = await PesagemLocalDao.instance.resolverPorIdDeTela(999);
      expect(porTelaPositivo!['id_local'], idLocal);

      final idLocal2 = await PesagemLocalDao.instance.inserir(
        uuid: 'uuid-2',
        bd: '97174041604',
        fazendaId: '57',
        epocaId: '011',
        lote: 'Lote 2',
        qtdAPesar: 5,
        criteriosLista: [],
      );
      final porTelaNegativo = await PesagemLocalDao.instance.resolverPorIdDeTela(-idLocal2);
      expect(porTelaNegativo!['id_local'], idLocal2);
    });

    test('ItemPesagemLocalDao: numeração sequencial local e resolução por número', () async {
      final idLocalPesagem = await PesagemLocalDao.instance.inserir(
        uuid: 'uuid-item-pesagem',
        bd: '97174041604',
        fazendaId: '57',
        epocaId: '011',
        lote: 'Lote Item',
        qtdAPesar: 3,
        criteriosLista: [],
      );

      final n1 = await ItemPesagemLocalDao.instance.proximoNumeroItemLocal(idLocalPesagem);
      expect(n1, 1);

      await ItemPesagemLocalDao.instance.inserir(
        pesagemIdLocal: idLocalPesagem,
        uuid: 'item-uuid-1',
        numeroItemLocal: n1,
        campos: {'id_animal': '1', 'codigo_animal': 'B-1', 'peso': '300'},
      );

      final n2 = await ItemPesagemLocalDao.instance.proximoNumeroItemLocal(idLocalPesagem);
      expect(n2, 2);

      final itens = await ItemPesagemLocalDao.instance.listarPorPesagemLocal(idLocalPesagem);
      expect(itens.length, 1);

      final resolvido = await ItemPesagemLocalDao.instance.buscarPorPesagemENumero(idLocalPesagem, 1);
      expect(resolvido, isNotNull);
      expect(resolvido!['codigo_animal'], 'B-1');
    });

    test('OutboxDao: enfileirar, listar, marcar erro com backoff, marcar concluido', () async {
      final id = await OutboxDao.instance.enfileirar(
        tipoOperacao: TipoOperacaoOutbox.criarPesagem,
        entidadeUuid: 'uuid-outbox-1',
        payload: {'foo': 'bar'},
      );

      var pendentes = await OutboxDao.instance.listarPendentes();
      expect(pendentes.length, 1);
      expect(pendentes.first['status'], StatusOutbox.pendente);

      await OutboxDao.instance.marcarErro(id, 'timeout de rede');
      final buscado = await OutboxDao.instance.buscarPendentePorEntidade(
        'uuid-outbox-1',
        TipoOperacaoOutbox.criarPesagem,
      );
      expect(buscado, isNotNull);
      expect(buscado!['status'], StatusOutbox.erro);
      expect(buscado['tentativas'], 1);
      expect(OutboxDao.instance.podeTentarAgora(buscado), isFalse);

      await OutboxDao.instance.marcarConcluido(id);
      final aposConcluido = await OutboxDao.instance.buscarPendentePorEntidade(
        'uuid-outbox-1',
        TipoOperacaoOutbox.criarPesagem,
      );
      expect(aposConcluido, isNull);
    });
  });

  group('PesagemRepository offline (sem tocar na rede real)', () {
    setUp(() {
      // Força o serviço de conectividade a reportar "sem internet", para
      // garantir que o repositório caia no caminho local/outbox e nunca
      // tente uma chamada HTTP de verdade durante o teste.
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.semInternet);
    });

    test('criarPesagem grava local e enfileira CRIAR_PESAGEM', () async {
      final resultado = await PesagemRepository.instance.criarPesagem({
        'bd': '97174041604',
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Offline',
        'filtro_desc': 'Fazenda X -> Motivo Y',
        'qtd_a_pesar': '10',
        'criterios_lista': ['Apartar'],
        'usuario': 'Teste',
      });

      expect(resultado['success'], true);
      final idPesagemTela = resultado['pesagem_id'] as int;
      expect(idPesagemTela, lessThan(0), reason: 'offline deve devolver id negativo (id local)');

      final pendentes = await OutboxDao.instance.listarPendentes();
      expect(pendentes.length, 1);
      expect(pendentes.first['tipo_operacao'], TipoOperacaoOutbox.criarPesagem);
    });

    test('salvarItem grava local, enfileira SALVAR_ITEM dependente da pesagem, e numero_item local funciona', () async {
      final resCriar = await PesagemRepository.instance.criarPesagem({
        'bd': '97174041604',
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Offline 2',
        'filtro_desc': 'Fazenda X -> Motivo Y',
        'qtd_a_pesar': '10',
        'criterios_lista': [],
        'usuario': 'Teste',
      });
      final idPesagemTela = resCriar['pesagem_id'] as int;

      final resItem = await PesagemRepository.instance.salvarItem({
        'bd': '97174041604',
        'pesagem_id': idPesagemTela,
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Offline 2',
        'filtro_desc': 'Fazenda X -> Motivo Y',
        'usuario': 'Teste',
        'qtd_a_pesar': '10',
        'criterios_lista': [],
        'item': {
          'id_animal': '123',
          'codigo_animal': 'B-123',
          'peso': '280',
          'ultimo_peso': 0,
          'sexo': 'Fêmea',
          'nascimento': '2023-01-01',
          'raca': 'Nelore',
          'pelagem': 'Branca',
          'mae': 'Não inf.',
          'obs': '',
          'mens_repetido': '',
          'id_pesagem_repetido': 0,
          'criterio_apartacao': '',
        },
      });

      expect(resItem['success'], true);
      expect(resItem['numero_item'], 1);

      final outbox = await OutboxDao.instance.listarPendentes();
      // 1 operação CRIAR_PESAGEM + 1 operação SALVAR_ITEM
      expect(outbox.length, 2);
      final opSalvarItem = outbox.firstWhere(
        (o) => o['tipo_operacao'] == TipoOperacaoOutbox.salvarItem,
      );
      expect(opSalvarItem['depende_de_uuid'], isNotNull);

      // Reabrir a pesagem (simulando fechar e abrir o app de novo) deve
      // trazer o item de volta a partir do banco local.
      final completa = await PesagemRepository.instance.buscarPesagemCompleta(
        bd: '97174041604',
        idPesagem: idPesagemTela,
      );
      expect(completa['success'], true);
      final itens = completa['itens'] as List;
      expect(itens.length, 1);
      expect(itens.first['tbl_ite_pesagem_codigo_animal'], 'B-123');
      expect(itens.first['tbl_ite_pesagem_numero_item'], 1);
    });

    test('excluirItem de um item nunca sincronizado cancela a operação pendente (não vira EXCLUIR_ITEM)', () async {
      final resCriar = await PesagemRepository.instance.criarPesagem({
        'bd': '97174041604',
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Exclusao',
        'filtro_desc': '',
        'qtd_a_pesar': '5',
        'criterios_lista': [],
        'usuario': 'Teste',
      });
      final idPesagemTela = resCriar['pesagem_id'] as int;

      await PesagemRepository.instance.salvarItem({
        'bd': '97174041604',
        'pesagem_id': idPesagemTela,
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Exclusao',
        'filtro_desc': '',
        'usuario': 'Teste',
        'qtd_a_pesar': '5',
        'criterios_lista': [],
        'item': {
          'id_animal': '55',
          'codigo_animal': 'B-55',
          'peso': '200',
          'sexo': 'Macho',
        },
      });

      await PesagemRepository.instance.excluirItem({
        'bd': '97174041604',
        'pesagem_id': idPesagemTela,
        'numero_item': 1,
      });

      final outbox = await OutboxDao.instance.listarPendentes();
      final temSalvarItem = outbox.any(
        (o) => o['tipo_operacao'] == TipoOperacaoOutbox.salvarItem,
      );
      final temExcluirItem = outbox.any(
        (o) => o['tipo_operacao'] == TipoOperacaoOutbox.excluirItem,
      );
      expect(temSalvarItem, isFalse, reason: 'operação SALVAR_ITEM pendente deve ter sido cancelada');
      expect(temExcluirItem, isFalse, reason: 'não deve gerar EXCLUIR_ITEM para item nunca sincronizado');

      final completa = await PesagemRepository.instance.buscarPesagemCompleta(
        bd: '97174041604',
        idPesagem: idPesagemTela,
      );
      expect((completa['itens'] as List).length, 0);
    });
  });
}
