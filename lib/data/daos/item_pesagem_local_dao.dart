import 'package:sqflite/sqflite.dart';
import '../local_database.dart';

class StatusSyncItem {
  static const pendente = 'pendente';
  static const sincronizado = 'sincronizado';
}

/// DAO da tabela itens_pesagem_locais — itens (pesos) espelhados no
/// dispositivo, fonte de leitura da tela de itens (local-first).
class ItemPesagemLocalDao {
  ItemPesagemLocalDao._();
  static final ItemPesagemLocalDao instance = ItemPesagemLocalDao._();

  Future<int> proximoNumeroItemLocal(int pesagemIdLocal) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COALESCE(MAX(numero_item_local), 0) + 1 as prox FROM itens_pesagem_locais WHERE pesagem_id_local = ?',
      [pesagemIdLocal],
    );
    return (r.first['prox'] as int?) ?? 1;
  }

  Future<int> inserir({
    required int pesagemIdLocal,
    required String uuid,
    required int numeroItemLocal,
    int? numeroItemServidor,
    required Map<String, dynamic> campos,
    String statusSync = StatusSyncItem.pendente,
  }) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();
    return db.insert('itens_pesagem_locais', {
      'pesagem_id_local': pesagemIdLocal,
      'uuid': uuid,
      'numero_item_local': numeroItemLocal,
      'numero_item_servidor': numeroItemServidor,
      'id_animal': campos['id_animal']?.toString(),
      'codigo_animal': campos['codigo_animal']?.toString(),
      'peso': campos['peso']?.toString(),
      'ultimo_peso': campos['ultimo_peso']?.toString(),
      'sexo': campos['sexo']?.toString(),
      'nascimento': campos['nascimento']?.toString(),
      'raca': campos['raca']?.toString(),
      'pelagem': campos['pelagem']?.toString(),
      'mae': campos['mae']?.toString(),
      'obs': campos['obs']?.toString() ?? '',
      'mens_repetido': campos['mens_repetido']?.toString() ?? '',
      'id_pesagem_repetido': campos['id_pesagem_repetido']?.toString() ?? '0',
      'criterio_apartacao': campos['criterio_apartacao']?.toString() ?? '',
      'status_sync': statusSync,
      'criado_em': agora,
      'atualizado_em': agora,
    });
  }

  Future<List<Map<String, dynamic>>> listarPorPesagemLocal(
    int pesagemIdLocal,
  ) async {
    final db = await LocalDatabase.instance.database;
    return db.query(
      'itens_pesagem_locais',
      where: 'pesagem_id_local = ?',
      whereArgs: [pesagemIdLocal],
      orderBy: 'numero_item_local DESC',
    );
  }

  Future<Map<String, dynamic>?> buscarPorUuid(String uuid) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.query(
      'itens_pesagem_locais',
      where: 'uuid = ?',
      whereArgs: [uuid],
      limit: 1,
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  /// Resolve o item pelo número que a tela está usando: pode já ter o número
  /// oficial do servidor, ou ainda ser só o número local (enquanto pendente).
  Future<Map<String, dynamic>?> buscarPorPesagemENumero(
    int pesagemIdLocal,
    int numero,
  ) async {
    final db = await LocalDatabase.instance.database;
    final porServidor = await db.query(
      'itens_pesagem_locais',
      where: 'pesagem_id_local = ? AND numero_item_servidor = ?',
      whereArgs: [pesagemIdLocal, numero],
      limit: 1,
    );
    if (porServidor.isNotEmpty) return porServidor.first;

    final porLocal = await db.query(
      'itens_pesagem_locais',
      where: 'pesagem_id_local = ? AND numero_item_local = ?',
      whereArgs: [pesagemIdLocal, numero],
      limit: 1,
    );
    return porLocal.isEmpty ? null : porLocal.first;
  }

  /// Procura se este animal já tem peso lançado em OUTRA pesagem ainda
  /// aberta (lote diferente) neste mesmo aparelho — base pro alerta
  /// "animal repetido em outro lote". Não depende de rede: um animal só
  /// existe numa fazenda (nunca duplicado entre locais) e os lotes em
  /// andamento de uma fazenda estão sempre no aparelho que está pesando
  /// naquele momento (mesmo quando a pesagem é retomada depois, em outro
  /// celular, os itens pendentes são reimportados nele antes de continuar)
  /// — então o que está salvo localmente já é a fonte de verdade.
  Future<Map<String, dynamic>?> buscarPesagemAbertaPorAnimal(
    String idAnimal, {
    int? excluirPesagemIdLocal,
  }) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.rawQuery(
      '''
      SELECT p.id_local, p.id_servidor, p.lote
      FROM itens_pesagem_locais i
      JOIN pesagens_locais p ON p.id_local = i.pesagem_id_local
      WHERE i.id_animal = ?
        AND p.finalizada = 'N'
        AND p.id_local != ?
      LIMIT 1
      ''',
      [idAnimal, excluirPesagemIdLocal ?? -1],
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  /// Item mais recente deste animal, com apartação preenchida, em alguma
  /// pesagem ainda aberta neste aparelho — base dos alertas de "mãe/bezerro
  /// já com apartação em lote aberto" (ver AnimalRepository). Mesmo
  /// raciocínio 100% local do buscarPesagemAbertaPorAnimal: os lotes em
  /// andamento de uma fazenda estão sempre no aparelho que está pesando.
  Future<Map<String, dynamic>?> buscarCriterioApartacaoAberta(
    String idAnimal,
  ) async {
    final db = await LocalDatabase.instance.database;
    final linhas = await db.rawQuery(
      '''
      SELECT i.criterio_apartacao AS criterio, i.pesagem_id_local, i.numero_item_local
      FROM itens_pesagem_locais i
      JOIN pesagens_locais p ON p.id_local = i.pesagem_id_local
      WHERE i.id_animal = ?
        AND p.finalizada = 'N'
        AND IFNULL(i.criterio_apartacao, '') != ''
      ORDER BY i.pesagem_id_local DESC, i.numero_item_local DESC
      LIMIT 1
      ''',
      [idAnimal],
    );
    return linhas.isEmpty ? null : linhas.first;
  }

  Future<void> confirmarSincronizacao(int idLocal, int numeroItemServidor) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'itens_pesagem_locais',
      {
        'numero_item_servidor': numeroItemServidor,
        'status_sync': StatusSyncItem.sincronizado,
        'atualizado_em': DateTime.now().toIso8601String(),
      },
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> atualizarCampos(
    int idLocal, {
    String? peso,
    String? obs,
    String? criterioApartacao,
    String? mensRepetido,
    String? idPesagemRepetido,
  }) async {
    final db = await LocalDatabase.instance.database;
    final valores = <String, dynamic>{
      'atualizado_em': DateTime.now().toIso8601String(),
    };
    if (peso != null) valores['peso'] = peso;
    if (obs != null) valores['obs'] = obs;
    if (criterioApartacao != null) {
      valores['criterio_apartacao'] = criterioApartacao;
    }
    if (mensRepetido != null) valores['mens_repetido'] = mensRepetido;
    if (idPesagemRepetido != null) {
      valores['id_pesagem_repetido'] = idPesagemRepetido;
    }

    await db.update(
      'itens_pesagem_locais',
      valores,
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  Future<void> excluir(int idLocal) async {
    final db = await LocalDatabase.instance.database;
    await db.delete(
      'itens_pesagem_locais',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
  }

  /// Remove todos os itens de uma pesagem local — usado quando a pesagem
  /// inteira é removida do cache (ex: confirmado que não existe mais no
  /// servidor).
  Future<void> excluirTodosDaPesagem(int pesagemIdLocal) async {
    final db = await LocalDatabase.instance.database;
    await db.delete(
      'itens_pesagem_locais',
      where: 'pesagem_id_local = ?',
      whereArgs: [pesagemIdLocal],
    );
  }

  /// Importa todos os itens de uma vez, numa única transação — tudo ou
  /// nada. Sem isso, uma pesagem com muitos itens (centenas) podia ficar
  /// com uma importação parcial presa pra sempre se o app fosse encerrado/
  /// reiniciado no meio do loop (ex: hot restart durante o teste): as linhas
  /// já inseridas ficavam valendo, e como a tela só rebusca no servidor
  /// quando está com ZERO itens localmente, a contagem incompleta nunca
  /// era corrigida sozinha.
  Future<void> importarDoServidor(
    int pesagemIdLocal,
    List<dynamic> itensServidor,
  ) async {
    final db = await LocalDatabase.instance.database;
    final agora = DateTime.now().toIso8601String();

    await db.transaction((txn) async {
      final existentes = await txn.query(
        'itens_pesagem_locais',
        columns: ['numero_item_servidor'],
        where: 'pesagem_id_local = ? AND numero_item_servidor IS NOT NULL',
        whereArgs: [pesagemIdLocal],
      );
      final numerosExistentes = existentes
          .map((e) => e['numero_item_servidor'] as int)
          .toSet();

      final maxAtual = Sqflite.firstIntValue(
            await txn.rawQuery(
              'SELECT COALESCE(MAX(numero_item_local), 0) FROM itens_pesagem_locais WHERE pesagem_id_local = ?',
              [pesagemIdLocal],
            ),
          ) ??
          0;
      var proximoLocal = maxAtual + 1;

      for (final item in itensServidor) {
        final numeroServidor = int.parse(
          item['tbl_ite_pesagem_numero_item'].toString(),
        );
        if (numerosExistentes.contains(numeroServidor)) continue;

        await txn.insert('itens_pesagem_locais', {
          'pesagem_id_local': pesagemIdLocal,
          'uuid': 'importado-servidor-$pesagemIdLocal-$numeroServidor',
          'numero_item_local': proximoLocal,
          'numero_item_servidor': numeroServidor,
          'id_animal': item['tbl_ite_pesagem_codigo_id_animal']?.toString(),
          'codigo_animal': item['tbl_ite_pesagem_codigo_animal']?.toString(),
          'peso': item['tbl_ite_pesagem_peso']?.toString(),
          'ultimo_peso': item['tbl_ite_pesagem_ultimo_peso']?.toString(),
          'sexo': item['tbl_ite_pesagem_sexo']?.toString(),
          'nascimento': item['tbl_ite_pesagem_nascimento']?.toString(),
          'raca': item['tbl_ite_pesagem_raca']?.toString(),
          'pelagem': item['tbl_ite_pesagem_pelagem']?.toString(),
          'mae': item['tbl_ite_pesagem_mae']?.toString(),
          'obs': item['tbl_ite_pesagem_observacao']?.toString() ?? '',
          'mens_repetido':
              item['tbl_ite_pesagem_mens_repetido']?.toString() ?? '',
          'id_pesagem_repetido':
              item['tbl_ite_pesagem_id_repetido']?.toString() ?? '0',
          'criterio_apartacao':
              item['tbl_ite_pesagem_criterio_apartacao']?.toString() ?? '',
          'status_sync': StatusSyncItem.sincronizado,
          'criado_em': agora,
          'atualizado_em': agora,
        });

        proximoLocal++;
      }
    });
  }
}
