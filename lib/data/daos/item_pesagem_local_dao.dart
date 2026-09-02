import 'package:sqflite/sqflite.dart';
import '../local_database.dart';
import 'outbox_dao.dart';

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
      // Item mais recente sempre no topo (mesmo comportamento de quando
      // está digitando). numero_item_local sozinho não é confiável pra
      // isso: uma importação antiga (antes da correção em
      // importarDoServidor) pode ter deixado esse número fora de ordem
      // para itens já confirmados, e não há como "consertar" o que já foi
      // gravado sem reprocessar a pesagem inteira. numero_item_servidor,
      // esse sim é sempre o número real e correto (reconciliarComServidor
      // garante isso) — então pra item já confirmado (numero_item_servidor
      // preenchido) usa ele pra ordenar; item ainda pendente de
      // sincronizar (numero_item_servidor nulo — normalmente é o que
      // acabou de ser digitado) sempre aparece antes de qualquer item já
      // confirmado, e entre pendentes usa numero_item_local (que pra esses
      // continua correto, é atribuído na hora que o próprio app grava).
      orderBy:
          'CASE WHEN numero_item_servidor IS NULL THEN 0 ELSE 1 END ASC, '
          'numero_item_servidor DESC, '
          'numero_item_local DESC',
    );
  }

  /// Quantos itens desta pesagem ainda não foram confirmados pelo servidor
  /// (numero_item_servidor nulo) — usado pra montar a contagem "Pesados"
  /// da lista somando com o total que o servidor já confirmou, em vez de
  /// contar todos os itens locais (que podem estar temporariamente
  /// desatualizados até a próxima reconciliação, ex: item excluído pelo
  /// sistema web).
  Future<int> contarPendentes(int pesagemIdLocal) async {
    final db = await LocalDatabase.instance.database;
    final r = await db.rawQuery(
      'SELECT COUNT(*) as qtd FROM itens_pesagem_locais '
      'WHERE pesagem_id_local = ? AND numero_item_servidor IS NULL',
      [pesagemIdLocal],
    );
    return (r.first['qtd'] as int?) ?? 0;
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

  /// Atualiza a mensagem de "repetido" de um item já sincronizado, a
  /// partir do que o servidor recalculou (o servidor sabe de itens do
  /// mesmo animal em pesagens que nem estão neste aparelho — ex: outro
  /// dispositivo, ou o sistema web). Usado pela reconciliação pós-sync do
  /// SyncService; nunca mexe em item ainda pendente (numero_item_servidor
  /// nulo), porque esse ainda nem existe no servidor pra ter sido
  /// recalculado.
  Future<void> atualizarMensRepetido(
    int pesagemIdLocal,
    int numeroItemServidor, {
    required String mensRepetido,
    required String idPesagemRepetido,
  }) async {
    final db = await LocalDatabase.instance.database;
    await db.update(
      'itens_pesagem_locais',
      {
        'mens_repetido': mensRepetido,
        'id_pesagem_repetido': idPesagemRepetido,
      },
      where: 'pesagem_id_local = ? AND numero_item_servidor = ?',
      whereArgs: [pesagemIdLocal, numeroItemServidor],
    );
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

  /// Normaliza o peso pra comparação (o servidor pode devolver "300" ou
  /// "300.00" dependendo do caminho — sem normalizar, isso quebraria a
  /// chave de comparação por engano).
  String _pesoNormalizado(dynamic peso) {
    final valor = double.tryParse(peso?.toString() ?? '');
    return valor != null ? valor.toStringAsFixed(2) : (peso?.toString() ?? '');
  }

  /// Reconcilia os itens já confirmados com o que o servidor tem agora,
  /// usando ID DO ANIMAL + PESO como chave — nunca numero_item sozinho, e
  /// nunca id do animal sozinho.
  ///
  /// numero_item não serve porque o sistema web, ao salvar qualquer edição
  /// numa pesagem (inclusive excluir 1 item), apaga TODOS os itens dela e
  /// reinsere de novo, renumerando 1..N pela ordem atual na tela
  /// (gravar_pesagem_individual.php) — é só "posição atual na lista", não
  /// um id estável.
  ///
  /// Só o ID do animal também não basta: o mesmo animal pode aparecer mais
  /// de uma vez na mesma pesagem (o app permite — é o próprio cenário do
  /// alerta de "animal repetido"), então duas linhas locais diferentes
  /// teriam a mesma chave. Combinar com o peso resolve isso na prática,
  /// já que duas pesagens de verdade do mesmo bicho quase sempre dão
  /// leituras diferentes. No raro empate de peso idêntico, cai num
  /// pareamento por ordem (FIFO) — não é garantia absoluta, mas é a
  /// melhor informação disponível (o servidor não guarda nenhum id
  /// estável de item que sobreviva a uma gravação pelo sistema web).
  ///
  /// Pra cada item já confirmado neste aparelho (numero_item_servidor
  /// preenchido):
  /// - se a combinação animal+peso não existe mais em [itensServidor], foi
  ///   excluído por fora (web ou outro dispositivo) -> remove local.
  /// - se existe, mas com um número diferente do que salvamos da última
  ///   vez (foi renumerado por causa da exclusão de outro item), corrige o
  ///   número local -> uma futura edição/exclusão feita neste app aponta
  ///   pro item certo, não pro que passou a ocupar aquele número.
  ///
  /// Nunca toca em item ainda pendente de sincronizar
  /// (numero_item_servidor nulo): esse ainda não existe no servidor pra
  /// ter sido excluído/renumerado de lá, é só um peso digitado offline
  /// esperando subir.
  Future<void> reconciliarComServidor(
    int pesagemIdLocal,
    List<dynamic> itensServidor,
  ) async {
    final db = await LocalDatabase.instance.database;

    String chave(String idAnimal, dynamic peso) =>
        '$idAnimal|${_pesoNormalizado(peso)}';

    final numerosPorChave = <String, List<int>>{};
    for (final item in itensServidor) {
      final mapa = item as Map;
      final idAnimal = mapa['tbl_ite_pesagem_codigo_id_animal']?.toString();
      final numero = int.tryParse(
        mapa['tbl_ite_pesagem_numero_item']?.toString() ?? '',
      );
      if (idAnimal == null || numero == null) continue;
      numerosPorChave
          .putIfAbsent(chave(idAnimal, mapa['tbl_ite_pesagem_peso']), () => [])
          .add(numero);
    }
    for (final lista in numerosPorChave.values) {
      lista.sort();
    }

    final confirmados = await db.query(
      'itens_pesagem_locais',
      columns: ['id_local', 'id_animal', 'peso', 'numero_item_servidor'],
      where: 'pesagem_id_local = ? AND numero_item_servidor IS NOT NULL',
      whereArgs: [pesagemIdLocal],
      orderBy: 'numero_item_servidor ASC',
    );

    for (final linha in confirmados) {
      final idAnimal = linha['id_animal']?.toString() ?? '';
      final candidatos = numerosPorChave[chave(idAnimal, linha['peso'])];

      if (candidatos == null || candidatos.isEmpty) {
        await db.delete(
          'itens_pesagem_locais',
          where: 'id_local = ?',
          whereArgs: [linha['id_local']],
        );
        continue;
      }

      final novoNumero = candidatos.removeAt(0);
      if (novoNumero != linha['numero_item_servidor']) {
        await db.update(
          'itens_pesagem_locais',
          {'numero_item_servidor': novoNumero},
          where: 'id_local = ?',
          whereArgs: [linha['id_local']],
        );
      }
    }
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

      // get_pesagem_completa.php manda os itens do mais novo pro mais
      // antigo (numero_item DESC) — é a ordem que a tela de detalhe da
      // pesagem quer pra mostrar. Mas aqui numero_item_local precisa
      // crescer do mais antigo pro mais novo, porque listarPorPesagemLocal
      // exibe em numero_item_local DESC (mais recente no topo). Se
      // processasse na ordem que chegou, o item mais novo pegaria o menor
      // numero_item_local e o mais antigo o maior — invertendo a lista
      // (bug real: item mais antigo aparecendo no topo depois de
      // sincronizar). Por isso ordena por numero_item ASC antes de
      // percorrer, sem depender da ordem em que o servidor mandou.
      final itensOrdenados = itensServidor.toList()
        ..sort((a, b) {
          final numA =
              int.tryParse(
                (a as Map)['tbl_ite_pesagem_numero_item'].toString(),
              ) ??
              0;
          final numB =
              int.tryParse(
                (b as Map)['tbl_ite_pesagem_numero_item'].toString(),
              ) ??
              0;
          return numA.compareTo(numB);
        });

      for (final item in itensOrdenados) {
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
