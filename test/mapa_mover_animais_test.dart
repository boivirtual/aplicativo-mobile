// Mover todos os animais no Mapa de Gado offline: a ação aplica no cache
// na hora (mesmas premissas da descrição do lote do web), entra na fila e
// continua valendo mesmo depois de um download do servidor que ainda não
// a conhece. Também cobre a montagem da Descrição do Lote.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/mapa_gado_dao.dart';
import 'package:boivirtual/services/connectivity_service.dart';
import 'package:boivirtual/services/mapa_gado_sync_service.dart';
import 'package:boivirtual/utils/descricao_lote_composicao.dart';
import 'package:boivirtual/utils/mapa_tabuleiro_calculo.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  LocalDatabase.nomeArquivo = 'test_mapa_mover.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('dev.fluttercommunity.plus/connectivity'),
        (call) async => call.method == 'check' ? ['none'] : null,
      );

  const bd = 'teste_mapa';
  const fazenda = 56;

  Map<String, dynamic> pasto(int id, int ordem, String desc) => {
    'id': id,
    'local': fazenda,
    'descricao': 'P$id',
    'modulo': 1,
    'capim': '',
    'categorias': '001!002!003!004!005',
    'ordem': ordem,
    'descricao_lote': desc,
    'lotes': [desc, '', '', '', '', ''],
  };

  Map<String, dynamic> animal(int item, int pasto) => {
    'local': fazenda,
    'item': item,
    'pasto': pasto,
    'sexo': 'F',
    'nascimento': '2020-01-01',
  };

  // Servidor: P1 (VACAS, 2 animais), P2 (sem descrição, vazio),
  // P3 (BOIS , 1 animal), P4 (TOUROS , vazio).
  Future<void> baixarDoServidor() => MapaGadoDao.instance.salvarDoServidor(
    bd: bd,
    fazendasConsultadas: [fazenda],
    categorias: const [],
    descricoesLote: const [
      {'id': 1, 'descricao': 'VACAS'},
    ],
    pastos: [
      pasto(1, 1, 'VACAS '),
      pasto(2, 2, ''),
      pasto(3, 3, 'BOIS '),
      pasto(4, 4, 'TOUROS '),
    ],
    animais: [animal(1, 1), animal(2, 1), animal(3, 3)],
  );

  Future<Map<int, String>> descricoes() async {
    final p = await MapaGadoDao.instance.pastos(bd, fazenda);
    return {for (final x in p) x.id: x.descricaoLote};
  }

  Future<Map<int, int>> qtdPorPasto() async {
    final a = await MapaGadoDao.instance.animais(bd, fazenda);
    final r = <int, int>{};
    for (final x in a) {
      r[x.pastoId] = (r[x.pastoId] ?? 0) + 1;
    }
    return r;
  }

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
    ConnectivityService.instance.forcarNivelParaTeste(NivelConexao.semInternet);
    await baixarDoServidor();
  });

  test('Premissa 1: destino sem descrição recebe a da origem; origem fica sem', () async {
    await MapaGadoSyncService.instance.transferirTudo(
      bd: bd,
      origem: 1,
      destino: 2,
      usuario: 'Teste',
    );
    expect(await qtdPorPasto(), {2: 2, 3: 1});
    final d = await descricoes();
    expect(d[2], 'VACAS ');
    expect(d[1], '');
    expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 1);
  });

  test('Premissa 6: destino com descrição mantém a dele; origem fica sem', () async {
    await MapaGadoSyncService.instance.transferirTudo(
      bd: bd,
      origem: 1,
      destino: 4,
      usuario: 'Teste',
    );
    final d = await descricoes();
    expect(d[4], 'TOUROS ');
    expect(d[1], '');
    expect(await qtdPorPasto(), {4: 2, 3: 1});
  });

  test('download do servidor não desfaz ações ainda pendentes', () async {
    await MapaGadoSyncService.instance.transferirTudo(
      bd: bd,
      origem: 1,
      destino: 4,
      usuario: 'Teste',
    );
    await MapaGadoSyncService.instance.gravarDescricaoLote(
      bd: bd,
      pasto: 4,
      descricaoLote: 'VACAS PARIDAS 05/26',
      lotes: ['VACAS PARIDAS 05/26'],
      usuario: 'Teste',
    );

    // Servidor ainda não recebeu nada: download traz o estado antigo.
    await baixarDoServidor();

    expect(await qtdPorPasto(), {4: 2, 3: 1});
    final d = await descricoes();
    expect(d[4], 'VACAS PARIDAS 05/26');
    expect(d[1], '');
    expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 2);
  });

  test('editar a Descrição do Lote pelo campo mantém o número do lote; '
      'criar nova zera até o servidor gerar', () async {
    await MapaGadoDao.instance.salvarDoServidor(
      bd: bd,
      fazendasConsultadas: [fazenda],
      categorias: const [],
      descricoesLote: const [],
      pastos: [
        {...pasto(1, 1, 'VACAS '), 'id_lote': 23, 'ano_lote': 2026},
      ],
      animais: [animal(1, 1)],
    );
    Future<PastoMapa> p1() async =>
        (await MapaGadoDao.instance.pastos(bd, fazenda)).first;

    expect(await MapaGadoDao.instance.lotesDoPasto(bd, 1), ['VACAS ']);

    await MapaGadoSyncService.instance.gravarDescricaoLote(
      bd: bd,
      pasto: 1,
      descricaoLote: 'VACAS -BOIS ',
      lotes: ['VACAS ', 'BOIS '],
      usuario: 'Teste',
      manterNumero: true,
    );
    var p = await p1();
    expect(p.descricaoLote, 'VACAS -BOIS ');
    expect(p.idLote, 23);
    expect(p.anoLote, 2026);
    expect(await MapaGadoDao.instance.lotesDoPasto(bd, 1), ['VACAS ', 'BOIS ']);
    expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 1);

    await MapaGadoSyncService.instance.gravarDescricaoLote(
      bd: bd,
      pasto: 1,
      descricaoLote: 'TOUROS ',
      lotes: ['TOUROS '],
      usuario: 'Teste',
    );
    p = await p1();
    expect(p.descricaoLote, 'TOUROS ');
    expect(p.idLote, 0);
  });

  group('transferir por categoria (Confirma da tela do pasto)', () {
    // Idades em 2026-10-06: item 1 = 81 meses (cat 5), item 2 = 80 (cat 5),
    // item 3 = 21 meses (cat 3). Todas fêmeas, no pasto 1 (VACAS, L-23/26).
    Map<String, dynamic> an(int item, int pasto, String nasc) => {
      'local': fazenda,
      'item': item,
      'pasto': pasto,
      'sexo': 'F',
      'nascimento': nasc,
    };

    Future<void> preparar() => MapaGadoDao.instance.salvarDoServidor(
      bd: bd,
      fazendasConsultadas: [fazenda],
      categorias: const [
        {'id': 3, 'de': 13, 'ate': 24},
        {'id': 5, 'de': 37, 'ate': 999999999},
      ],
      descricoesLote: const [],
      pastos: [
        {...pasto(1, 1, 'VACAS '), 'id_lote': 23, 'ano_lote': 2026},
        pasto(2, 2, ''),
        pasto(4, 4, 'TOUROS '),
      ],
      animais: [
        an(1, 1, '2020-01-01'),
        an(2, 1, '2020-02-01'),
        an(3, 1, '2025-01-01'),
        an(9, 4, '2020-01-01'),
      ],
    );

    Future<Map<int, PastoMapa>> pastos() async => {
      for (final p in await MapaGadoDao.instance.pastos(bd, fazenda)) p.id: p,
    };

    Future<void> transferir(int destino, int categoria, int qtd) =>
        MapaGadoSyncService.instance.transferirCategoria(
          bd: bd,
          origem: 1,
          destino: destino,
          categoria: categoria,
          sexo: 'F',
          quantidade: qtd,
          usuario: 'Teste',
        );

    test('parcial: só os animais da categoria vão; descrições não mudam; '
        'Levar copia a descrição e o número para o destino', () async {
      await preparar();
      await transferir(2, 5, 1);
      expect(await qtdPorPasto(), {1: 2, 2: 1, 4: 1});
      var p = await pastos();
      expect(p[1]!.descricaoLote, 'VACAS ');
      expect(p[1]!.idLote, 23);
      expect(p[2]!.descricaoLote, '');

      await MapaGadoSyncService.instance.levarDescricaoLote(
        bd: bd,
        origem: 1,
        destino: 2,
        usuario: 'Teste',
      );
      p = await pastos();
      expect(p[2]!.descricaoLote, 'VACAS ');
      expect(p[2]!.idLote, 23);
      expect(p[1]!.descricaoLote, 'VACAS ');
      expect(p[1]!.idLote, 0); // número novo vem do servidor
      expect(await MapaGadoDao.instance.contar(bd, 'pendente'), 2);

      // o servidor devolve o número novo da origem
      await MapaGadoDao.instance.definirNumeroLote(
        bd: bd,
        pastoId: 1,
        idLote: 31,
        anoLote: 2026,
      );
      expect((await pastos())[1]!.idLote, 31);
    });

    test('origem fica vazia, destino sem descrição: descrição vai junto '
        '(Premissa 1)', () async {
      await preparar();
      await transferir(2, 5, 2);
      await transferir(2, 3, 1);
      expect(await qtdPorPasto(), {2: 3, 4: 1});
      final p = await pastos();
      expect(p[1]!.descricaoLote, '');
      expect(p[2]!.descricaoLote, 'VACAS ');
      expect(p[2]!.idLote, 23);
    });

    test('origem fica vazia, destino com descrição: destino mantém a dele '
        '(Premissa 6)', () async {
      await preparar();
      await transferir(4, 5, 2);
      await transferir(4, 3, 1);
      expect(await qtdPorPasto(), {4: 4});
      final p = await pastos();
      expect(p[1]!.descricaoLote, '');
      expect(p[4]!.descricaoLote, 'TOUROS ');
    });

    test('download do servidor não desfaz a transferência pendente', () async {
      await preparar();
      await transferir(2, 5, 1);
      await preparar(); // servidor ainda com o estado antigo
      expect(await qtdPorPasto(), {1: 2, 2: 1, 4: 1});
    });

    test('opções do select trazem categoria, sexo e quantidade', () {
      final opcoes = PastoMovimentacaoCalculo.opcoesTransferencia(
        animaisDoPasto: const [
          AnimalPastoMapa(pastoId: 1, sexo: 'F', nascimento: '2020-01-01'),
          AnimalPastoMapa(pastoId: 1, sexo: 'F', nascimento: '2020-02-01'),
          AnimalPastoMapa(pastoId: 1, sexo: 'M', nascimento: '2025-01-01'),
          AnimalPastoMapa(pastoId: 1, sexo: 'M', nascimento: '2026-08-01'),
        ],
        categorias: const {
          1: CategoriaIdadeMapa(id: 1, idadeDe: 0, idadeAte: 7),
          3: CategoriaIdadeMapa(id: 3, idadeDe: 13, idadeAte: 24),
          5: CategoriaIdadeMapa(id: 5, idadeDe: 37, idadeAte: 999999999),
        },
        hoje: DateTime(2026, 10, 6),
      );
      expect(
        [for (final o in opcoes) '${o.categoria}|${o.sexo}|${o.quantidade}|${o.rotulo}'],
        [
          '1||1|00 a 07 meses',
          '3|M|1|13 a 24 meses - Macho',
          '5|F|2|> 36 meses - Fêmea',
        ],
      );
    });
  });

  group('montagem da Descrição do Lote (igual ao web)', () {
    test('linhas e descrição completa', () {
      expect(
        DescricaoLoteComposicao.montarLinha(descricao: 'BOIS'),
        'BOIS ',
      );
      expect(
        DescricaoLoteComposicao.montarLinha(
          descricao: 'VACAS',
          parametro2: 'PARIDAS',
          datas: [DateTime(2026, 5), DateTime(2026, 7)],
        ),
        'VACAS PARIDAS 05/26-07/26',
      );
      expect(
        DescricaoLoteComposicao.montarDescricao(['VACAS CHEIAS', '', 'BOIS ']),
        'VACAS CHEIAS-BOIS ',
      );
    });

    test('situação/sexo e pergunta de data', () {
      expect(DescricaoLoteComposicao.opcoesParametro2(1).length, 5);
      expect(DescricaoLoteComposicao.opcoesParametro2(3).first.value, 'MACHO/FÊMEA');
      expect(DescricaoLoteComposicao.opcoesParametro2(5), isEmpty);
      expect(DescricaoLoteComposicao.perguntaData(1, 1), isFalse); // VAZIAS
      expect(DescricaoLoteComposicao.perguntaData(1, 5), isFalse); // DESCARTE
      expect(DescricaoLoteComposicao.perguntaData(1, 4), isTrue); // PARIDAS
      expect(DescricaoLoteComposicao.perguntaData(3, 1), isTrue);
      expect(DescricaoLoteComposicao.perguntaData(5, null), isFalse);
    });

    test('validação com as mensagens do web', () {
      expect(DescricaoLoteComposicao.validarLinha(null, null), 'Selecione a Descrição do Lote');
      expect(DescricaoLoteComposicao.validarLinha(1, null), 'Selecione a Situação.');
      expect(DescricaoLoteComposicao.validarLinha(3, null), 'Selecione o Sexo.');
      expect(DescricaoLoteComposicao.validarLinha(5, null), isNull);
    });
  });
}
