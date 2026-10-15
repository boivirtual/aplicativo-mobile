// Ponta a ponta contra um servidor de verdade (WAMP local), opcional:
//   MAPA_API_LOCAL=http://localhost/reproducao/sistema/api
//   MAPA_BD_TESTE=teste_offline_pesagem
//   MAPA_FAZENDA=56  MAPA_ORIGEM=<pasto com animais>  MAPA_DESTINO=<pasto>
// ALTERA o banco informado — use só banco de teste, com backup.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/config/api_config.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/mapa_gado_dao.dart';
import 'package:boivirtual/services/connectivity_service.dart';
import 'package:boivirtual/services/mapa_gado_sync_service.dart';

/// TestWidgetsFlutterBinding bloqueia HTTP real (tudo vira 400) — mesmo
/// contorno de sync_rede_ruim_test.dart.
class _HttpOverridesReais extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _HttpOverridesReais();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  LocalDatabase.nomeArquivo = 'test_mapa_mover_servidor.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['wifi'] : null,
      );

  final env = Platform.environment;
  final api = env['MAPA_API_LOCAL'];

  test(
    'mover offline, enviar quando volta a internet e o servidor confirmar',
    () async {
      ApiConfig.baseUrl = api!;
      final bd = env['MAPA_BD_TESTE']!;
      final fazenda = int.parse(env['MAPA_FAZENDA']!);
      final origem = int.parse(env['MAPA_ORIGEM']!);
      final destino = int.parse(env['MAPA_DESTINO']!);

      await LocalDatabase.instance.resetarParaTeste();
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.internetOk);
      expect(await MapaGadoSyncService.instance.baixar(bd, [fazenda]), isTrue);

      Future<int> qtd(int pasto) async => (await MapaGadoDao.instance.animais(
        bd,
        fazenda,
      )).where((a) => a.pastoId == pasto).length;

      final antesOrigem = await qtd(origem);
      final antesDestino = await qtd(destino);
      expect(antesOrigem, greaterThan(0));

      // Offline: aplica local e fica pendente.
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.semInternet);
      await MapaGadoSyncService.instance.transferirTudo(
        bd: bd,
        origem: origem,
        destino: destino,
        usuario: 'Teste App',
      );
      expect(await qtd(origem), 0);
      expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 1);

      // Volta a internet: envia, baixa de novo e o servidor confirma.
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.internetOk);
      expect(await MapaGadoSyncService.instance.baixar(bd, [fazenda]), isTrue);
      expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 0);
      expect(await MapaGadoDao.instance.contar(bd, 'erro'), 0);
      expect(await qtd(origem), 0);
      expect(await qtd(destino), antesDestino + antesOrigem);

      // Nova descrição do lote com internet: o número gerado pelo servidor
      // já vem para o cache no envio (sem esperar o próximo download).
      await MapaGadoSyncService.instance.gravarDescricaoLote(
        bd: bd,
        pasto: destino,
        descricaoLote: 'BOIS ',
        lotes: ['BOIS '],
        usuario: 'Teste App',
      );
      // o envio já começou sozinho em segundo plano (online): espera a fila
      for (var i = 0; i < 50; i++) {
        if (await MapaGadoDao.instance.contar(bd, 'pendente') == 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      await Future.delayed(const Duration(milliseconds: 200));
      final pasto = (await MapaGadoDao.instance.pastos(
        bd,
        fazenda,
      )).firstWhere((p) => p.id == destino);
      expect(pasto.descricaoLote, 'BOIS ');
      expect(pasto.idLote, greaterThan(0));
      expect(pasto.anoLote, DateTime.now().year);
    },
    skip: api == null ? 'defina MAPA_API_LOCAL (ver topo do arquivo)' : false,
  );

  // Nutrição, do app até o servidor: MAPA_NUTRI_PASTO=<pasto>
  final nutriPasto = env['MAPA_NUTRI_PASTO'];
  test(
    'nutrição: inclui, o servidor devolve o id, exclui e some',
    () async {
      ApiConfig.baseUrl = api!;
      final bd = env['MAPA_BD_TESTE']!;
      final fazenda = int.parse(env['MAPA_FAZENDA']!);
      final pasto = int.parse(nutriPasto!);
      final hoje = DateTime.now().toIso8601String().substring(0, 10);

      await LocalDatabase.instance.resetarParaTeste();
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.internetOk);
      expect(await MapaGadoSyncService.instance.baixar(bd, [fazenda]), isTrue);

      final dao = MapaGadoDao.instance;
      final cochos = await dao.scoresCocho(bd);
      final produtos = await dao.produtosNutricao(bd);
      expect(cochos, isNotEmpty);
      expect(produtos, isNotEmpty);

      Future<void> esperarFila() async {
        for (var i = 0; i < 80; i++) {
          if (await dao.contar(bd, 'pendente') == 0) break;
          await Future.delayed(const Duration(milliseconds: 100));
        }
        await Future.delayed(const Duration(milliseconds: 300));
      }

      final antes = (await dao.nutricoesDoPasto(bd, pasto, hoje)).length;
      await MapaGadoSyncService.instance.incluirNutricao(
        bd: bd,
        fazenda: fazenda,
        pasto: pasto,
        data: hoje,
        produto: produtos.first['id'] as int,
        produtoDescricao: produtos.first['descricao'].toString(),
        unidade: produtos.first['unidade'].toString(),
        quantidade: 12.5,
        qtdAnimais: 5,
        cocho: cochos.last.key,
        usuario: 'Teste App',
      );
      await esperarFila();
      expect(await dao.contar(bd, 'erro'), 0);
      var linhas = await dao.nutricoesDoPasto(bd, pasto, hoje);
      expect(linhas.length, antes + 1);
      expect(linhas.last['id'], greaterThan(0));

      // a busca do dia no servidor traz a mesma linha (sem duplicar)
      expect(
        await MapaGadoSyncService.instance.buscarNutricoesDoDia(
          bd: bd,
          fazenda: fazenda,
          pasto: pasto,
          data: hoje,
        ),
        isTrue,
      );
      linhas = await dao.nutricoesDoPasto(bd, pasto, hoje);
      expect(linhas.length, antes + 1);

      await MapaGadoSyncService.instance.excluirNutricao(
        bd: bd,
        chave: linhas.last['chave'] as String,
        id: linhas.last['id'] as int,
        usuario: 'Teste App',
      );
      await esperarFila();
      expect(await dao.contar(bd, 'erro'), 0);
      await MapaGadoSyncService.instance.buscarNutricoesDoDia(
        bd: bd,
        fazenda: fazenda,
        pasto: pasto,
        data: hoje,
      );
      expect((await dao.nutricoesDoPasto(bd, pasto, hoje)).length, antes);
    },
    skip: api == null || nutriPasto == null
        ? 'defina MAPA_API_LOCAL e MAPA_NUTRI_PASTO (ver comentário)'
        : false,
  );

  // Morte de um animal, do app até o servidor:
  //   MAPA_MORTE_ANIMAL=<tbl_animal_codigo_id>  MAPA_MORTE_PASTO=<pasto>
  //   MAPA_MORTE_SEXO=F  MAPA_MORTE_NASC=2019-12-01
  final morteAnimal = env['MAPA_MORTE_ANIMAL'];
  test(
    'morte: baixa os extras, grava na fila e o servidor aceita',
    () async {
      ApiConfig.baseUrl = api!;
      final bd = env['MAPA_BD_TESTE']!;
      final fazenda = int.parse(env['MAPA_FAZENDA']!);
      final pasto = int.parse(env['MAPA_MORTE_PASTO']!);

      await LocalDatabase.instance.resetarParaTeste();
      ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.internetOk);
      expect(await MapaGadoSyncService.instance.baixar(bd, [fazenda]), isTrue);

      final dao = MapaGadoDao.instance;
      expect(await dao.controleEstoque(bd), 'I');
      expect(await dao.motivosMorte(bd), isNotEmpty);

      Future<int> qtd() async => (await dao.animais(
        bd,
        fazenda,
      )).where((a) => a.pastoId == pasto).length;
      final antes = await qtd();

      expect(
        await dao.validarMorte(
          bd: bd,
          fazenda: fazenda,
          pasto: pasto,
          sexo: env['MAPA_MORTE_SEXO']!,
          nascimento: env['MAPA_MORTE_NASC']!,
        ),
        isNull,
      );
      await MapaGadoSyncService.instance.registrarMorte(
        bd: bd,
        fazenda: fazenda,
        pasto: pasto,
        animal: int.parse(morteAnimal!),
        codigo: '',
        sexo: env['MAPA_MORTE_SEXO']!,
        nascimento: env['MAPA_MORTE_NASC']!,
        motivo: (await dao.motivosMorte(bd)).first.key,
        dataMorte: DateTime.now().toIso8601String().substring(0, 10),
        observacao: 'TESTE APP',
        usuario: 'Teste App',
      );
      expect(await qtd(), antes - 1);

      for (var i = 0; i < 80; i++) {
        if (await dao.contar(bd, 'pendente') == 0) break;
        await Future.delayed(const Duration(milliseconds: 100));
      }
      expect(await dao.contar(bd, 'pendente'), 0);
      expect(await dao.contar(bd, 'erro'), 0);

      // o download depois do envio confirma o estado do servidor
      await Future.delayed(const Duration(seconds: 2));
      expect(await MapaGadoSyncService.instance.baixar(bd, [fazenda]), isTrue);
      expect(await qtd(), antes - 1);
    },
    skip: api == null || morteAnimal == null
        ? 'defina MAPA_API_LOCAL e MAPA_MORTE_ANIMAL (ver comentário)'
        : false,
  );

  // Confirmar do Nascimento, do app até o servidor (roda o script do web):
  //   MAPA_NASC=1 (usa a mãe B-986 da Pedra Bonita, pasto FUNDAÇA 01)
  final nasc = env['MAPA_NASC'];
  test(
    'nascimento: grava pelo script do web e valida como o web',
    () async {
      ApiConfig.baseUrl = api!;
      final bd = env['MAPA_BD_TESTE']!;
      final s = MapaGadoSyncService.instance;
      Map<String, String?> campos({String? sexo, String mae = '000006408'}) => {
        'grupo_usuario': '01',
        'tipo_gravacao': '0',
        'num_mov_nascimento': '0',
        'codigo_mae_animal': mae,
        'dias_nascimento': '269',
        'cobertura_id': '000000430',
        'item_cobertura': '0023',
        'tipo_cobertura': 'C',
        'data_prenhes': '2026-01-17',
        'estacao_monta_id': '000000017',
        'data_inseminacao': '2026-01-17',
        'local_id': '57',
        'pasto_id': '52',
        'opcao_nascimento': 'N',
        'nascimento_animal': DateTime.now().toIso8601String().substring(0, 10),
        'codigo_mae_consulta': 'B-986 - Mestiça',
        'codigo_pai_animal': '900000068',
        'alfa_animal': 'B',
        'codigo_animal_id': '',
        'codigo_numerico_animal': '1738',
        'qtd_animal': '',
        'sexo_animal': sexo,
        'raca_id': '001',
        'pelagem_id': '',
        'peso_animal': '30.5',
      };

      // sem sexo: a mesma mensagem do web
      var r = await s.gravarNascimento(
        acao: 'gravar_nascimento',
        bd: bd,
        usuario: 'Teste App',
        campos: campos(),
      );
      expect(r?['message'], 'Informe o Sexo.');

      // sem a mãe validada
      r = await s.gravarNascimento(
        acao: 'gravar_nascimento',
        bd: bd,
        usuario: 'Teste App',
        campos: campos(sexo: 'M', mae: ''),
      );
      expect(r?['message'], startsWith('FALTA VALIDAR O Nº DA MÃE'));

      r = await s.gravarNascimento(
        acao: 'gravar_nascimento',
        bd: bd,
        usuario: 'Teste App',
        campos: campos(sexo: 'M'),
      );
      expect(r?['success'], isTrue);
      expect(r?['message'], 'Registro incluído com sucesso.');
      expect(r?['descricao_pasto'], 'FUNDAÇA 01');
    },
    skip: api == null || nasc == null
        ? 'defina MAPA_API_LOCAL e MAPA_NASC (ver comentário)'
        : false,
  );
}
