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

    test('PesagemLocalDao: importarDoServidor atualiza finalizada ao reimportar uma '
        'pesagem já conhecida (bug real: pesagem finalizada no servidor continuava '
        '"aberta" no cache local, disparando alerta de animal repetido à toa)', () async {
      final pesagemAberta = {
        'tbl_pesagem_id': '919',
        'tbl_pesagem_codigo_local': '57',
        'tbl_pesagem_codigo_epoca': '003',
        'tbl_pesagem_lote': 'Venda Edson Elias',
        'tbl_pesagem_qtd_animais_a_pesar': '1',
        'tbl_pesagem_filtros': 'FAZENDA PEDRA BONITA -> Venda',
        'tbl_pesagem_finalizada': 'N',
        'tbl_pesagem_criterios_apartacao': '',
      };

      final idLocal = await PesagemLocalDao.instance.importarDoServidor(
        pesagemAberta,
        bd: '71746307668',
      );
      final antes = await PesagemLocalDao.instance.buscarPorIdLocal(idLocal);
      expect(antes!['finalizada'], 'N');

      final pesagemFinalizada = Map<String, dynamic>.from(pesagemAberta)
        ..['tbl_pesagem_finalizada'] = 'S';
      final idLocalDeNovo = await PesagemLocalDao.instance.importarDoServidor(
        pesagemFinalizada,
        bd: '71746307668',
      );
      expect(idLocalDeNovo, idLocal, reason: 'mesma pesagem, não deve duplicar');

      final depois = await PesagemLocalDao.instance.buscarPorIdLocal(idLocal);
      expect(depois!['finalizada'], 'S');
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

    test(
      'ItemPesagemLocalDao: atualizarMensRepetido só mexe no item já confirmado pelo servidor',
      () async {
        final idLocalPesagem = await PesagemLocalDao.instance.inserir(
          uuid: 'uuid-mens-repetido',
          bd: '97174041604',
          fazendaId: '57',
          epocaId: '011',
          lote: 'Lote Repetido',
          qtdAPesar: 1,
          criteriosLista: [],
        );

        final idLocalItem = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-uuid-repetido',
          numeroItemLocal: 1,
          campos: {'id_animal': '900001', 'codigo_animal': 'C-87', 'peso': '300'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(
          idLocalItem,
          42,
        );

        await ItemPesagemLocalDao.instance.atualizarMensRepetido(
          idLocalPesagem,
          42,
          mensRepetido: 'Repetido em: Lote B',
          idPesagemRepetido: '914',
        );

        final atualizado = await ItemPesagemLocalDao.instance
            .buscarPorPesagemENumero(idLocalPesagem, 42);
        expect(atualizado!['mens_repetido'], 'Repetido em: Lote B');
        expect(atualizado['id_pesagem_repetido'], '914');

        // numero_item_servidor que não existe -> não atualiza nada, não lança erro.
        await ItemPesagemLocalDao.instance.atualizarMensRepetido(
          idLocalPesagem,
          999,
          mensRepetido: 'não deveria aplicar',
          idPesagemRepetido: '0',
        );
        final inalterado = await ItemPesagemLocalDao.instance
            .buscarPorPesagemENumero(idLocalPesagem, 42);
        expect(inalterado!['mens_repetido'], 'Repetido em: Lote B');
      },
    );

    test(
      'ItemPesagemLocalDao: reconciliarComServidor identifica pelo ID do '
      'animal, não pelo número (que o sistema web reatribui a cada '
      'exclusão) — reproduz o bug real: excluir o item do meio não pode '
      'apagar nem confundir os itens seguintes',
      () async {
        final idLocalPesagem = await PesagemLocalDao.instance.inserir(
          uuid: 'uuid-reconciliacao-item',
          bd: '71746307668',
          fazendaId: '56',
          epocaId: '003',
          lote: 'Transferencia',
          qtdAPesar: 4,
          criteriosLista: [],
        );

        // 4 itens confirmados, numerados 1..4 na ordem original.
        final idA = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-animal-A',
          numeroItemLocal: 1,
          campos: {'id_animal': 'A', 'codigo_animal': 'B-1620', 'peso': '160'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(idA, 1);

        final idB = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-animal-B',
          numeroItemLocal: 2,
          campos: {'id_animal': 'B', 'codigo_animal': 'B-1662', 'peso': '200'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(idB, 2);

        final idC = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-animal-C',
          numeroItemLocal: 3,
          campos: {'id_animal': 'C', 'codigo_animal': 'B-187', 'peso': '300'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(idC, 3);

        final idD = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-animal-D',
          numeroItemLocal: 4,
          campos: {'id_animal': 'D', 'codigo_animal': 'B-1672', 'peso': '150'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(idD, 4);

        // Item pendente offline (peso digitado agora, nunca sincronizou) —
        // não pode ser tocado de jeito nenhum.
        await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-pendente-offline',
          numeroItemLocal: 5,
          campos: {'id_animal': 'E', 'codigo_animal': 'B-999', 'peso': '250'},
        );

        // Sistema web exclui o animal B (numero 2, o do meio) e reinsere
        // tudo renumerado: A continua 1, C (era 3) vira 2, D (era 4) vira 3.
        await ItemPesagemLocalDao.instance.reconciliarComServidor(
          idLocalPesagem,
          [
            {
              'tbl_ite_pesagem_codigo_id_animal': 'A',
              'tbl_ite_pesagem_numero_item': '1',
              'tbl_ite_pesagem_peso': '160',
            },
            {
              'tbl_ite_pesagem_codigo_id_animal': 'C',
              'tbl_ite_pesagem_numero_item': '2',
              'tbl_ite_pesagem_peso': '300',
            },
            {
              'tbl_ite_pesagem_codigo_id_animal': 'D',
              'tbl_ite_pesagem_numero_item': '3',
              'tbl_ite_pesagem_peso': '150',
            },
          ],
        );

        final restantes = await ItemPesagemLocalDao.instance
            .listarPorPesagemLocal(idLocalPesagem);

        // B foi removido de verdade.
        expect(restantes.any((i) => i['id_animal'] == 'B'), isFalse);

        // A, C e D continuam, cada um com o NÚMERO NOVO do servidor — não
        // com o número velho, e não confundidos entre si.
        Map<String, dynamic> porAnimal(String id) =>
            restantes.firstWhere((i) => i['id_animal'] == id);
        expect(porAnimal('A')['numero_item_servidor'], 1);
        expect(porAnimal('C')['numero_item_servidor'], 2);
        expect(porAnimal('D')['numero_item_servidor'], 3);

        // O item ainda pendente (nunca sincronizado) sobrevive intocado.
        expect(restantes.any((i) => i['id_animal'] == 'E'), isTrue);

        expect(restantes.length, 4);
      },
    );

    test(
      'ItemPesagemLocalDao: reconciliarComServidor não confunde o mesmo '
      'animal pesado 2x na mesma pesagem (usa peso pra distinguir)',
      () async {
        final idLocalPesagem = await PesagemLocalDao.instance.inserir(
          uuid: 'uuid-mesmo-animal-2x',
          bd: '71746307668',
          fazendaId: '56',
          epocaId: '003',
          lote: 'Reteste',
          qtdAPesar: 2,
          criteriosLista: [],
        );

        // Animal X pesado duas vezes por engano (vaqueiro cantou errado,
        // bicho voltou pra fila) — pesos diferentes nas duas leituras.
        final idPrimeiraPesagem = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-X-primeira-leitura',
          numeroItemLocal: 1,
          campos: {'id_animal': 'X', 'codigo_animal': 'B-1', 'peso': '180'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(
          idPrimeiraPesagem,
          1,
        );

        final idSegundaPesagem = await ItemPesagemLocalDao.instance.inserir(
          pesagemIdLocal: idLocalPesagem,
          uuid: 'item-X-segunda-leitura',
          numeroItemLocal: 2,
          campos: {'id_animal': 'X', 'codigo_animal': 'B-1', 'peso': '183'},
        );
        await ItemPesagemLocalDao.instance.confirmarSincronizacao(
          idSegundaPesagem,
          2,
        );

        // Sistema web exclui um item de OUTRO lugar antes desse (nada a
        // ver com o animal X) — os dois registros do X são renumerados
        // juntos: quem era 1 e 2 vira 1 e 2 mesmo (sem exclusão entre
        // eles), mas simula que os números vieram deslocados por uma
        // exclusão anterior na lista (eram 5 e 6, viram 1 e 2).
        await ItemPesagemLocalDao.instance.reconciliarComServidor(
          idLocalPesagem,
          [
            {
              'tbl_ite_pesagem_codigo_id_animal': 'X',
              'tbl_ite_pesagem_numero_item': '1',
              'tbl_ite_pesagem_peso': '180',
            },
            {
              'tbl_ite_pesagem_codigo_id_animal': 'X',
              'tbl_ite_pesagem_numero_item': '2',
              'tbl_ite_pesagem_peso': '183',
            },
          ],
        );

        final itemPrimeira = await ItemPesagemLocalDao.instance
            .buscarPorUuid('item-X-primeira-leitura');
        final itemSegunda = await ItemPesagemLocalDao.instance
            .buscarPorUuid('item-X-segunda-leitura');

        // Cada leitura continua associada ao número certo pro SEU peso —
        // não trocaram de identidade entre si.
        expect(itemPrimeira!['numero_item_servidor'], 1);
        expect(itemSegunda!['numero_item_servidor'], 2);
      },
    );

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

    test('excluirItem de um item cujo envio já bateu em conflito no servidor '
        'também cancela a pendência (bug real: ficava órfã em Pendências '
        'de revisão mesmo depois do item excluído)', () async {
      final resCriar = await PesagemRepository.instance.criarPesagem({
        'bd': '97174041604',
        'local_id': '57',
        'epoca_id': '011',
        'lote': 'Lote Conflito',
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
        'lote': 'Lote Conflito',
        'filtro_desc': '',
        'usuario': 'Teste',
        'qtd_a_pesar': '5',
        'criterios_lista': [],
        'item': {
          'id_animal': '56',
          'codigo_animal': 'B-56',
          'peso': '300+100',
          'sexo': 'Macho',
        },
      });

      // Simula o que o SyncService faz quando o servidor rejeita o envio
      // (ex: peso num formato que o servidor não aceita) — a operação vira
      // "conflito", não "erro".
      final pendenteAntes = await OutboxDao.instance.listarPendentes();
      final salvarItemId = pendenteAntes
          .firstWhere((o) => o['tipo_operacao'] == TipoOperacaoOutbox.salvarItem)['id']
          as int;
      await OutboxDao.instance.marcarConflito(
        salvarItemId,
        'Erro ao gravar item da pesagem.',
      );

      await PesagemRepository.instance.excluirItem({
        'bd': '97174041604',
        'pesagem_id': idPesagemTela,
        'numero_item': 1,
      });

      final conflitos = await OutboxDao.instance.listarConflitos();
      expect(
        conflitos.any((o) => o['id'] == salvarItemId),
        isFalse,
        reason: 'operação em conflito deve ter sido cancelada junto com a exclusão do item',
      );
    });
  });
}
