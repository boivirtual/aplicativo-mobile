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
}
