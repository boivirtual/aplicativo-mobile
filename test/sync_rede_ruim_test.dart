// Testes de rede ruim de propósito (proposta item 5): usam um servidor HTTP
// local de mentira (pacote `shelf`, dev-only) que dá pra derrubar e
// reerguer no meio do teste, simulando queda de conexão de verdade — não só
// "sem internet desde o início" (que os testes de
// offline_pesagem_test.dart já cobrem sobejamente).
//
// Rodar com: flutter test test/sync_rede_ruim_test.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/config/api_config.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/outbox_dao.dart';
import 'package:boivirtual/repositories/pesagem_repository.dart';
import 'package:boivirtual/services/connectivity_service.dart';
import 'package:boivirtual/services/sync_service.dart';

/// Servidor de mentira que imita só o suficiente das rotas de
/// api/rest/pesagem/*.php pra exercitar o SyncService de verdade — com
/// idempotência por uuid_app, igual ao PesagemDao.php real (branch
/// offline-pesagem).
class ServidorDeMentira {
  HttpServer? _http;
  int _proximoIdPesagem = 500;
  int _proximoNumeroItem = 1;

  final Map<String, int> _pesagemIdPorUuid = {};
  final Map<String, int> _itemNumeroPorUuid = {};

  /// Quando true, save_item.php responde numero_item: null no PRIMEIRO
  /// salvamento de cada item — reproduz de propósito o bug real encontrado
  /// (servidor desatualizado sem uuid_app, resposta malformada) pra provar
  /// que a correção de hoje (sync_service.dart) não duplica ao repetir.
  bool modoRespostaMalformada = false;

  final Set<String> _itensJaTentados = {};

  /// Quando true, o servidor se derruba sozinho logo DEPOIS de responder o
  /// próximo create_pesagem.php — simula a conexão caindo bem no meio de
  /// uma rodada de sincronização, entre confirmar o cabeçalho e salvar o
  /// item, de um jeito determinístico (sem depender de cronometrar de
  /// fora).
  bool derrubarAposProximaCriacaoDePesagem = false;

  Future<int> get porta async => (await _garantirIniciado())?.port ?? 0;

  Future<HttpServer?> _garantirIniciado() async => _http;

  Future<void> iniciar() async {
    final handler = const Pipeline().addHandler(_rotear);
    _http = await shelf_io.serve(handler, 'localhost', 0);
  }

  Future<void> derrubar() async {
    await _http?.close(force: true);
    _http = null;
  }

  Future<Response> _rotear(Request request) async {
    final corpo = await request.readAsString();
    final Map<String, dynamic> dados = corpo.isEmpty
        ? {}
        : json.decode(corpo) as Map<String, dynamic>;

    if (request.url.path.endsWith('create_pesagem.php')) {
      return _criarPesagem(dados);
    }
    if (request.url.path.endsWith('save_item.php')) {
      return _salvarItem(dados);
    }
    if (request.url.path.endsWith('update_pesagem.php') ||
        request.url.path.endsWith('update_item.php') ||
        request.url.path.endsWith('delete_item.php')) {
      return Response.ok(json.encode({"success": true}));
    }
    if (request.url.path.endsWith('list_pendentes.php') ||
        request.url.path.endsWith('list_finalizadas.php')) {
      return Response.ok(json.encode([]));
    }
    return Response.notFound(json.encode({"success": false}));
  }

  Response _criarPesagem(Map<String, dynamic> dados) {
    final uuid = dados['uuid_app']?.toString();
    final int id;
    if (uuid != null && _pesagemIdPorUuid.containsKey(uuid)) {
      id = _pesagemIdPorUuid[uuid]!;
    } else {
      id = _proximoIdPesagem++;
      if (uuid != null) _pesagemIdPorUuid[uuid] = id;
    }

    if (derrubarAposProximaCriacaoDePesagem) {
      derrubarAposProximaCriacaoDePesagem = false;
      // Agenda a queda pra depois desta resposta já ter sido enviada —
      // simula o sinal caindo bem no instante seguinte, não no meio desta
      // chamada.
      Future.microtask(derrubar);
    }

    return Response.ok(json.encode({"success": true, "pesagem_id": id}));
  }

  Response _salvarItem(Map<String, dynamic> dados) {
    final item = dados['item'] as Map<String, dynamic>?;
    final uuid = item?['uuid_app']?.toString();

    // Reenvio idempotente: uuid já visto antes -> devolve o número já
    // atribuído, nunca duplica (igual ao PesagemDao.php real).
    if (uuid != null && _itemNumeroPorUuid.containsKey(uuid)) {
      return Response.ok(
        json.encode({
          "success": true,
          "pesagem_id": dados['pesagem_id'],
          "numero_item": _itemNumeroPorUuid[uuid],
        }),
      );
    }

    final numero = _proximoNumeroItem++;
    if (uuid != null) _itemNumeroPorUuid[uuid] = numero;

    if (modoRespostaMalformada &&
        uuid != null &&
        !_itensJaTentados.contains(uuid)) {
      // Simula o bug real: o item JÁ foi gravado do lado do servidor
      // (uuid registrado acima), mas a resposta não traz o número —
      // reproduz exatamente o "numero_item: null" que travou a Claudia.
      _itensJaTentados.add(uuid);
      return Response.ok(
        json.encode({
          "success": true,
          "pesagem_id": dados['pesagem_id'],
          "numero_item": null,
        }),
      );
    }

    return Response.ok(
      json.encode({
        "success": true,
        "pesagem_id": dados['pesagem_id'],
        "numero_item": numero,
      }),
    );
  }

  int get totalItensGravados => _itemNumeroPorUuid.length;
}

/// TestWidgetsFlutterBinding, sozinho, faz TODA chamada HTTP real devolver
/// status 400 sem chegar na rede de verdade — proteção padrão do Flutter
/// contra teste acidentalmente bater na internet. Esses testes PRECISAM de
/// HTTP de verdade (só que contra localhost, nunca a internet), então
/// devolvemos o HttpClient real de propósito.
class _HttpOverridesReais extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return HttpClient(context: context);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _HttpOverridesReais();
  // O lookup DNS que ConnectivityService faz pra confirmar "internet de
  // verdade" não pode depender de internet real nem do domínio de
  // produção dentro do ambiente de teste — aponta pro loopback, que
  // sempre resolve na hora, local, sem rede nenhuma envolvida.
  ConnectivityService.hostParaChecagem = 'localhost';
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null,
      );

  final servidor = ServidorDeMentira();
  late String baseUrlOriginal;

  setUpAll(() {
    baseUrlOriginal = ApiConfig.baseUrl;
  });

  tearDownAll(() {
    ApiConfig.baseUrl = baseUrlOriginal;
  });

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
    servidor.modoRespostaMalformada = false;
  });

  tearDown(() async {
    await servidor.derrubar();
  });

  group('Sincronização com servidor real ligando/desligando', () {
    test(
      'cria pesagem e salva item com o servidor FORA DO AR, sincroniza tudo '
      'quando ele volta, sem duplicar num segundo sincronizarAgora()',
      () async {
        // Servidor nem chegou a subir ainda — simula "sem sinal no curral".
        final resCriar = await PesagemRepository.instance.criarPesagem({
          'bd': '97174041604',
          'local_id': '57',
          'epoca_id': '011',
          'lote': 'Lote Rede Ruim',
          'filtro_desc': 'Fazenda X -> Motivo Y',
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
          'lote': 'Lote Rede Ruim',
          'filtro_desc': 'Fazenda X -> Motivo Y',
          'usuario': 'Teste',
          'qtd_a_pesar': '5',
          'criterios_lista': [],
          'item': {
            'id_animal': '321',
            'codigo_animal': 'B-321',
            'peso': '250',
            'sexo': 'Macho',
          },
        });

        var pendentes = await OutboxDao.instance.listarPendentes();
        expect(pendentes.length, 2, reason: 'CRIAR_PESAGEM + SALVAR_ITEM');

        // "A internet volta" — sobe o servidor de mentira e aponta o app
        // pra ele.
        await servidor.iniciar();
        ApiConfig.baseUrl = 'http://localhost:${await servidor.porta}';

        // ignore: avoid_print
        print('DEBUG baseUrl=${ApiConfig.baseUrl}');
        await ConnectivityService.instance.verificarAgora();
        // ignore: avoid_print
        print(
          'DEBUG nivel=${ConnectivityService.instance.nivelAtual} '
          'temInternetReal=${ConnectivityService.instance.temInternetReal}',
        );

        final resultado1 = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        expect(resultado1.processadas, 2);
        expect(resultado1.comErro, 0);

        pendentes = await OutboxDao.instance.listarPendentes();
        expect(pendentes, isEmpty, reason: 'tudo confirmado, fila vazia');
        expect(servidor.totalItensGravados, 1);

        // Repete a sincronização (ex: o timer automático disparando de
        // novo) — não deve duplicar nada no servidor.
        final resultado2 = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        expect(resultado2.processadas, 0, reason: 'nada pendente pra tentar');
        expect(servidor.totalItensGravados, 1, reason: 'sem duplicar');
      },
    );

    test(
      'servidor cai DEPOIS de confirmar a pesagem mas ANTES do item — item '
      'não se perde, sincroniza sozinho quando o servidor volta',
      () async {
        final resCriar = await PesagemRepository.instance.criarPesagem({
          'bd': '97174041604',
          'local_id': '57',
          'epoca_id': '011',
          'lote': 'Lote Queda no Meio',
          'filtro_desc': 'Fazenda X -> Motivo Y',
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
          'lote': 'Lote Queda no Meio',
          'filtro_desc': 'Fazenda X -> Motivo Y',
          'usuario': 'Teste',
          'qtd_a_pesar': '5',
          'criterios_lista': [],
          'item': {
            'id_animal': '654',
            'codigo_animal': 'B-654',
            'peso': '310',
            'sexo': 'Fêmea',
          },
        });

        await servidor.iniciar();
        ApiConfig.baseUrl = 'http://localhost:${await servidor.porta}';
        // O servidor se derruba sozinho logo depois de confirmar a
        // criação da pesagem — a rodada de sincronização abaixo processa
        // CRIAR_PESAGEM com sucesso e já encontra o servidor fora do ar na
        // hora de tentar o SALVAR_ITEM, de forma determinística.
        servidor.derrubarAposProximaCriacaoDePesagem = true;

        final resultadoComQueda = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        expect(
          resultadoComQueda.processadas,
          1,
          reason: 'CRIAR_PESAGEM confirmou antes da queda',
        );
        expect(
          resultadoComQueda.comErro,
          greaterThan(0),
          reason: 'item não consegue sincronizar com o servidor fora do ar',
        );

        final pendentesDepoisDaQueda = await OutboxDao.instance
            .listarPendentes();
        expect(
          pendentesDepoisDaQueda.length,
          1,
          reason: 'item continua na fila, não foi perdido',
        );

        // Servidor volta.
        await servidor.iniciar();
        ApiConfig.baseUrl = 'http://localhost:${await servidor.porta}';

        final resultadoFinal = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        expect(resultadoFinal.processadas, 1);
        expect(await OutboxDao.instance.listarPendentes(), isEmpty);
        expect(servidor.totalItensGravados, 1, reason: 'sem duplicar');
      },
    );

    test(
      'servidor responde numero_item NULO (bug real do deploy desatualizado) '
      '— não trava em loop nem duplica, recupera sozinho quando o servidor '
      'corrige a resposta',
      () async {
        final resCriar = await PesagemRepository.instance.criarPesagem({
          'bd': '97174041604',
          'local_id': '57',
          'epoca_id': '011',
          'lote': 'Lote Resposta Ruim',
          'filtro_desc': 'Fazenda X -> Motivo Y',
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
          'lote': 'Lote Resposta Ruim',
          'filtro_desc': 'Fazenda X -> Motivo Y',
          'usuario': 'Teste',
          'qtd_a_pesar': '5',
          'criterios_lista': [],
          'item': {
            'id_animal': '789',
            'codigo_animal': 'B-789',
            'peso': '400',
            'sexo': 'Fêmea',
          },
        });

        servidor.modoRespostaMalformada = true;
        await servidor.iniciar();
        ApiConfig.baseUrl = 'http://localhost:${await servidor.porta}';

        final resultado1 = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        // A pesagem confirma normal; o item bate na resposta malformada e
        // fica marcado como erro (não crasha, não duplica, não fica preso
        // num loop silencioso sem backoff — ver correção em
        // sync_service.dart).
        expect(resultado1.comErro, greaterThan(0));

        final pendentesAposMalformada = await OutboxDao.instance
            .listarPendentes();
        expect(pendentesAposMalformada.length, 1);
        expect(
          pendentesAposMalformada.first['status'],
          StatusOutbox.erro,
          reason: 'marcado erro de propósito, com backoff — não em loop',
        );
        // O item já FOI gravado do lado do servidor (uuid registrado),
        // mesmo com a resposta malformada.
        expect(servidor.totalItensGravados, 1);

        // Tentativa de novo (ex: "Sincronizar agora" manual) — dessa vez a
        // resposta vem certa, e por já ter uuid_app registrado o servidor
        // devolve o número existente em vez de duplicar.
        final resultado2 = await SyncService.instance.sincronizarAgora(
          ignorarRecuo: true,
        );
        expect(resultado2.processadas, 1);
        expect(await OutboxDao.instance.listarPendentes(), isEmpty);
        expect(
          servidor.totalItensGravados,
          1,
          reason: 'idempotência por uuid_app evitou duplicar',
        );
      },
    );
  });
}
