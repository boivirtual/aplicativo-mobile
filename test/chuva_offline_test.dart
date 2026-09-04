// Valida que a tela de Chuva funciona 100% offline: lançamento grava no
// cache local na hora (sem esperar rede), os gráficos agregam certo a
// partir do cache, e a sincronização com o servidor nunca sobrescreve um
// lançamento local ainda pendente de confirmação.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/chuva_dao.dart';
import 'package:boivirtual/repositories/chuva_repository.dart';
import 'package:boivirtual/services/connectivity_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  LocalDatabase.nomeArquivo = 'test_chuva_offline.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['none'] : null,
      );

  const bd = 'teste_offline_chuva';
  const fazenda = '57';

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
    ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.semInternet);
  });

  test(
    'gravar offline salva local, entra como pendente e aparece no gráfico mensal',
    () async {
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 1, 15),
        volume: 40,
        usuario: 'Teste',
      );
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 1, 20),
        volume: 10,
        usuario: 'Teste',
      );

      expect(await ChuvaDao.instance.contarPendentes(bd), 2);

      final mensal = await ChuvaRepository.instance.graficoMensal(
        bd: bd,
        fazendaId: fazenda,
        ano: 2026,
      );
      expect(
        mensal.length,
        12,
      ); // sempre 12 meses, mesmo sem lançamento nos outros

      final janeiro = mensal.firstWhere((m) => m['mes'] == 1);
      expect(janeiro['mm'], 50); // 40 + 10
      expect(janeiro['dias'], 2);

      final fevereiro = mensal.firstWhere((m) => m['mes'] == 2);
      expect(fevereiro['mm'], 0);
      expect(fevereiro['dias'], 0);
    },
  );

  test(
    'gravar de novo na mesma data sobrescreve (mesma regra do servidor: 1 registro por dia/fazenda)',
    () async {
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 3, 10),
        volume: 15,
      );
      final existenteAntes = await ChuvaRepository.instance
          .buscarVolumeExistente(
            bd: bd,
            fazendaId: fazenda,
            data: DateTime(2026, 3, 10),
          );
      expect(existenteAntes, 15);

      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 3, 10),
        volume: 22,
      );
      final existenteDepois = await ChuvaRepository.instance
          .buscarVolumeExistente(
            bd: bd,
            fazendaId: fazenda,
            data: DateTime(2026, 3, 10),
          );
      expect(existenteDepois, 22);

      // continua 1 registro só, não duplicou
      final marco = await ChuvaRepository.instance.graficoMensal(
        bd: bd,
        fazendaId: fazenda,
        ano: 2026,
      );
      expect(marco.firstWhere((m) => m['mes'] == 3)['dias'], 1);
    },
  );

  test(
    'sincronização do servidor NÃO sobrescreve lançamento local ainda pendente',
    () async {
      // Usuário lança 25mm offline num dia.
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 5, 5),
        volume: 25,
      );

      // Chega uma sincronização com o servidor trazendo um valor diferente
      // pra esse mesmo dia (ex: versão antiga, ainda sem o lançamento deste
      // aparelho) — não pode apagar o que o usuário acabou de digitar.
      await ChuvaDao.instance.salvarLoteDoServidor(bd, [
        {
          "id": 999,
          "local": int.parse(fazenda),
          "data": "2026-05-05",
          "volume": 5.0,
        },
      ]);

      final valor = await ChuvaRepository.instance.buscarVolumeExistente(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 5, 5),
      );
      expect(valor, 25); // o lançamento local pendente prevaleceu
      expect(
        await ChuvaDao.instance.contarPendentes(bd),
        1,
      ); // continua pendente
    },
  );

  test(
    'sincronização do servidor atualiza normalmente o que NÃO está pendente',
    () async {
      await ChuvaDao.instance.salvarLoteDoServidor(bd, [
        {
          "id": 1,
          "local": int.parse(fazenda),
          "data": "2026-06-01",
          "volume": 12.0,
        },
      ]);

      expect(await ChuvaDao.instance.contarPendentes(bd), 0);
      final valor = await ChuvaRepository.instance.buscarVolumeExistente(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 6, 1),
      );
      expect(valor, 12);
    },
  );

  test(
    'gráfico anual sempre traz 5 anos (ano-4..ano), com zero nos anos sem lançamento',
    () async {
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2026, 2, 1),
        volume: 100,
      );
      await ChuvaRepository.instance.gravar(
        bd: bd,
        fazendaId: fazenda,
        data: DateTime(2024, 2, 1),
        volume: 50,
      );

      final anual = await ChuvaRepository.instance.graficoAnual(
        bd: bd,
        fazendaId: fazenda,
        anoFinal: 2026,
      );
      expect(anual.length, 5);
      expect(anual.map((a) => a['ano']), [2022, 2023, 2024, 2025, 2026]);
      expect(anual.firstWhere((a) => a['ano'] == 2026)['mm'], 100);
      expect(anual.firstWhere((a) => a['ano'] == 2024)['mm'], 50);
      expect(anual.firstWhere((a) => a['ano'] == 2023)['mm'], 0);
    },
  );
}
