// Verifica, de forma concreta (não só lendo o código), que fazer logout
// NÃO apaga o banco local (pesagens/itens/fila de sincronização) — logout
// só limpa o SharedPreferences (sessão: usuário, cnpj, fazendas).
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:boivirtual/data/local_database.dart';
import 'package:boivirtual/data/daos/pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/item_pesagem_local_dao.dart';
import 'package:boivirtual/data/daos/outbox_dao.dart';
import 'package:boivirtual/auth_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfiNoIsolate;
  LocalDatabase.nomeArquivo = 'test_logout_nao_apaga_banco.db';

  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/shared_preferences'),
        (call) async {
          if (call.method == 'getAll') return <String, dynamic>{};
          return true;
        },
      );

  setUp(() async {
    await LocalDatabase.instance.resetarParaTeste();
  });

  test(
    'logout limpa SharedPreferences mas NÃO apaga pesagem/itens/outbox do banco local',
    () async {
      // Simula uma pesagem criada offline, com item pendente de sincronizar
      // (representa os "300 animais digitados" ainda não enviados).
      final idPesagemLocal = await PesagemLocalDao.instance.inserir(
        uuid: 'pesagem-teste-logout',
        bd: '97174041604',
        fazendaId: '57',
        epocaId: '003',
        lote: 'Lote teste',
        qtdAPesar: 1,
        criteriosLista: [],
      );
      await ItemPesagemLocalDao.instance.inserir(
        pesagemIdLocal: idPesagemLocal,
        uuid: 'item-teste-logout',
        numeroItemLocal: 1,
        campos: {
          'id_animal': '900001',
          'codigo_animal': 'B-1',
          'peso': '300',
          'sexo': 'M',
        },
      );
      await OutboxDao.instance.enfileirar(
        tipoOperacao: TipoOperacaoOutbox.salvarItem,
        entidadeUuid: 'item-teste-logout',
        payload: {'algum': 'dado'},
      );

      // Confirma que os dados existem ANTES do logout.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('userCNPJ', '97174041604');
      await prefs.setBool('isLoggedIn', true);

      final pesagensAntes = await PesagemLocalDao.instance
          .listarPendentesLocais('97174041604');
      expect(pesagensAntes.length, 1);
      final itensAntes = await ItemPesagemLocalDao.instance
          .listarPorPesagemLocal(idPesagemLocal);
      expect(itensAntes.length, 1);

      // AÇÃO: logout de verdade, o mesmo método usado pelo botão "Sair".
      await AuthService.logout();

      // SharedPreferences foi limpo (efeito esperado do logout).
      expect(prefs.getBool('isLoggedIn'), isNull);
      expect(prefs.getString('userCNPJ'), isNull);

      // O BANCO LOCAL continua intacto — pesagem, item e a fila de
      // sincronização (outbox) ainda estão lá depois do logout.
      final pesagensDepois = await PesagemLocalDao.instance
          .listarPendentesLocais('97174041604');
      expect(
        pesagensDepois.length,
        1,
        reason: 'pesagem deveria continuar no banco depois do logout',
      );
      final itensDepois = await ItemPesagemLocalDao.instance
          .listarPorPesagemLocal(idPesagemLocal);
      expect(
        itensDepois.length,
        1,
        reason: 'item deveria continuar no banco depois do logout',
      );
      final pendenteOutbox = await OutboxDao.instance.buscarPendentePorEntidade(
        'item-teste-logout',
        TipoOperacaoOutbox.salvarItem,
      );
      expect(
        pendenteOutbox,
        isNotNull,
        reason:
            'operação pendente na fila de sincronização deveria continuar depois do logout',
      );
    },
  );
}
