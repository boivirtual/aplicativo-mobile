import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';
import '../config/api_config.dart';
import '../services/connectivity_service.dart';
import '../data/daos/pesagem_local_dao.dart';
import '../data/daos/item_pesagem_local_dao.dart';
import '../data/daos/outbox_dao.dart';

/// Camada única de acesso à pesagem — offline-first.
///
/// Toda escrita grava primeiro no banco local (sempre funciona, na hora) e,
/// se não houver internet de verdade ou a chamada falhar, entra na fila de
/// sincronização (outbox) em vez de se perder. Toda leitura relevante à tela
/// de itens vem do banco local, que é a fonte de verdade do que este
/// aparelho já digitou — o servidor só é consultado para importar pesagens
/// que este aparelho ainda não conhece (ex: criadas por outro
/// dispositivo/sistema web) e para atualizar as listas quando há sinal.
class PesagemRepository {
  PesagemRepository._();
  static final PesagemRepository instance = PesagemRepository._();

  final Uuid _uuid = const Uuid();

  bool get _online => ConnectivityService.instance.temInternetReal;

  List<String> _paraListaCriterios(dynamic valor) {
    if (valor is List) return valor.map((e) => e.toString()).toList();
    return <String>[];
  }

  Future<Map<String, dynamic>> _pesagemLocalParaMapaServidor(
    Map<String, dynamic> row,
  ) async {
    final criterios = _paraListaCriterios(
      jsonDecodeSeguro(row['criterios_lista'] as String?),
    );
    final idLocal = row['id_local'] as int;
    final idServidor = row['id_servidor'] as int?;
    final itensLocais = await ItemPesagemLocalDao.instance
        .listarPorPesagemLocal(idLocal);

    // qtd_pesados_servidor é atualizado a cada listagem online (ver
    // PesagemLocalDao.importarDoServidor) — é o número que o SERVIDOR
    // confirma agora, então soma só os itens locais ainda pendentes de
    // sincronizar (esses o servidor não sabe ainda). Contar todos os itens
    // locais direto (como era antes) dava número errado em dois casos: (1)
    // pesagem nunca aberta neste aparelho, itens locais vazios mesmo tendo
    // pesos no servidor; (2) item excluído por fora (sistema web) — o
    // cache local só se limpa quando a pesagem é reaberta, então até lá
    // ficava contando itens que já não existem mais.
    final qtdPesadosServidor = row['qtd_pesados_servidor'] as int?;
    final qtdPesados = qtdPesadosServidor != null
        ? qtdPesadosServidor +
            await ItemPesagemLocalDao.instance.contarPendentes(idLocal)
        : itensLocais.length;

    return {
      'tbl_pesagem_id': idServidor ?? -idLocal,
      'tbl_pesagem_codigo_local': row['fazenda_id'],
      'tbl_pesagem_codigo_epoca': row['epoca_id'],
      'tbl_pesagem_lote': row['lote'],
      'tbl_pesagem_qtd_animais_a_pesar': row['qtd_a_pesar'],
      'tbl_pesagem_qtd_animais_pesados': qtdPesados,
      'tbl_pesagem_filtros': row['filtro_desc'],
      'tbl_pesagem_finalizada': row['finalizada'],
      'tbl_pesagem_criterios_apartacao': criterios.join(', '),
      'tbl_pesagem_data': (row['criado_em'] as String).split('T').first,
      'fazenda_nome': null,
    };
  }

  Map<String, dynamic> _itemLocalParaMapaServidor(Map<String, dynamic> row) {
    final numero = row['numero_item_servidor'] ?? row['numero_item_local'];
    return {
      'tbl_ite_pesagem_numero_id': row['pesagem_id_local'],
      'tbl_ite_pesagem_numero_item': numero,
      'tbl_ite_pesagem_codigo_id_animal': row['id_animal'],
      'tbl_ite_pesagem_codigo_animal': row['codigo_animal'],
      'tbl_ite_pesagem_peso': row['peso'],
      'tbl_ite_pesagem_sexo': row['sexo'],
      'tbl_ite_pesagem_nascimento': row['nascimento'],
      'tbl_ite_pesagem_raca': row['raca'],
      'tbl_ite_pesagem_pelagem': row['pelagem'],
      'tbl_ite_pesagem_mae': row['mae'],
      'tbl_ite_pesagem_observacao': row['obs'],
      'tbl_ite_pesagem_mens_repetido': row['mens_repetido'],
      'tbl_ite_pesagem_id_repetido': row['id_pesagem_repetido'],
      'tbl_ite_pesagem_ultimo_peso': row['ultimo_peso'],
      'tbl_ite_pesagem_criterio_apartacao': row['criterio_apartacao'],
    };
  }

  // ---------------------------------------------------------------------
  // Listas
  // ---------------------------------------------------------------------

  Future<List<dynamic>> listarPendentes({
    required String? bd,
    required List<int> fazendas,
  }) async {
    final bdSeguro = bd ?? '';

    if (_online) {
      try {
        final response = await http
            .post(
              Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/list_pendentes.php"),
              body: json.encode({"bd": bd, "fazendas": fazendas}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final lista = json.decode(response.body) as List<dynamic>;
          final idsServidorAtuais = lista
              .map(
                (p) =>
                    int.tryParse(
                      (p as Map<String, dynamic>)['tbl_pesagem_id']
                          .toString(),
                    ) ??
                    0,
              )
              .toSet();

          for (final p in lista) {
            await PesagemLocalDao.instance.importarDoServidor(
              p as Map<String, dynamic>,
              bd: bdSeguro,
            );
          }

          await _reconciliarSumidosDoServidor(bdSeguro, idsServidorAtuais);

          final locais = await PesagemLocalDao.instance.listarPendentesLocais(
            bdSeguro,
          );
          final naoSincronizadas = locais.where(
            (l) => l['id_servidor'] == null,
          );
          final mapeadas = await Future.wait(
            naoSincronizadas.map(_pesagemLocalParaMapaServidor),
          );
          return [...mapeadas, ...lista];
        }
      } catch (_) {
        // cai para o fallback local abaixo
      }
    }

    final locais = await PesagemLocalDao.instance.listarPendentesLocais(
      bdSeguro,
    );
    return Future.wait(locais.map(_pesagemLocalParaMapaServidor));
  }

  /// Uma pesagem já sincronizada (id_servidor preenchido) que sumiu da
  /// resposta de list_pendentes pode ter sido excluída no sistema web, ou
  /// simplesmente finalizada — sem checar, ela ficava presa no cache local
  /// pra sempre (list_pendentes.php só devolve o que está em aberto), e
  /// reaparecia de forma inconsistente sempre que a tela caía no fallback
  /// offline (que não tem esse filtro). Confirma direto com o servidor
  /// antes de mexer em qualquer coisa — só remove o cache local quando o
  /// servidor afirma explicitamente que a pesagem não existe mais.
  Future<void> _reconciliarSumidosDoServidor(
    String bd,
    Set<int> idsServidorAtuais,
  ) async {
    final suspeitas = await PesagemLocalDao.instance
        .listarSincronizadasNaoFinalizadas(bd);

    for (final local in suspeitas) {
      final idServidor = local['id_servidor'] as int;
      if (idsServidorAtuais.contains(idServidor)) continue;

      try {
        final response = await http
            .post(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/pesagem/get_pesagem_completa.php",
              ),
              body: json.encode({"bd": bd, "id_pesagem": idServidor}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) continue;

        final data = json.decode(response.body);
        if (data['success'] == true) {
          // Ainda existe no servidor (provavelmente só foi finalizada) —
          // reimporta o cabeçalho atualizado em vez de deixar desatualizado.
          if (data['pesagem'] != null) {
            await PesagemLocalDao.instance.importarDoServidor(
              data['pesagem'] as Map<String, dynamic>,
              bd: bd,
            );
          }
          continue;
        }

        // success == false com essa checagem específica confirma exclusão
        // (o mesmo endpoint responde sucesso pra pesagem finalizada, então
        // isso não derruba nada que só esteja fechado).
        final idLocal = local['id_local'] as int;
        await ItemPesagemLocalDao.instance.excluirTodosDaPesagem(idLocal);
        await PesagemLocalDao.instance.excluirPorIdLocal(idLocal);
      } catch (_) {
        // sem confirmação clara do servidor — não mexe, tenta de novo na
        // próxima consulta.
      }
    }
  }

  Future<List<dynamic>> listarFinalizadas({
    required String? bd,
    required List<int> fazendas,
  }) async {
    final bdSeguro = bd ?? '';
    if (_online) {
      try {
        final response = await http
            .post(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/pesagem/list_finalizadas.php",
              ),
              body: json.encode({"bd": bd, "fazendas": fazendas}),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final lista = json.decode(response.body) as List<dynamic>;
          for (final p in lista) {
            await PesagemLocalDao.instance.importarDoServidor(
              p as Map<String, dynamic>,
              bd: bdSeguro,
            );
          }
          return lista;
        }
      } catch (_) {
        // sem fallback local específico para finalizadas: consulta é
        // somente leitura e menos crítica para o cenário de campo.
      }
    }
    return [];
  }

  // ---------------------------------------------------------------------
  // Criar / editar cabeçalho
  // ---------------------------------------------------------------------

  Future<Map<String, dynamic>> criarPesagem(Map<String, dynamic> bodyMap) async {
    final uuid = _uuid.v4();
    final criteriosLista = _paraListaCriterios(bodyMap['criterios_lista']);

    final idLocal = await PesagemLocalDao.instance.inserir(
      uuid: uuid,
      bd: bodyMap['bd']?.toString() ?? '',
      fazendaId: bodyMap['local_id']?.toString() ?? '',
      epocaId: bodyMap['epoca_id']?.toString() ?? '',
      lote: bodyMap['lote']?.toString() ?? '',
      qtdAPesar: int.tryParse(bodyMap['qtd_a_pesar'].toString()) ?? 0,
      filtroDesc: bodyMap['filtro_desc']?.toString(),
      usuario: bodyMap['usuario']?.toString(),
      criteriosLista: criteriosLista,
    );

    final payloadEnvio = Map<String, dynamic>.from(bodyMap)
      ..['uuid_app'] = uuid;

    // Opção 2 (mesma decisão já aplicada em salvarItem, commit 232dd2b):
    // "Iniciar Pesagem" nunca espera rede — grava local e entra na fila
    // sempre, mesmo online. O SyncService sobe pro servidor em segundo
    // plano.
    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.criarPesagem,
      entidadeUuid: uuid,
      payload: payloadEnvio,
    );

    return {"success": true, "pesagem_id": -idLocal};
  }

  Future<Map<String, dynamic>> atualizarPesagem(
    Map<String, dynamic> bodyMap,
  ) async {
    final idTela = int.tryParse(bodyMap['pesagem_id'].toString()) ?? 0;
    final local = await PesagemLocalDao.instance.resolverPorIdDeTela(idTela);
    if (local == null) {
      return {
        "success": false,
        "message": "Pesagem não encontrada localmente.",
      };
    }

    final idLocal = local['id_local'] as int;
    final criteriosLista = _paraListaCriterios(bodyMap['criterios_lista']);

    await PesagemLocalDao.instance.atualizarCabecalho(
      idLocal,
      fazendaId: bodyMap['local_id']?.toString(),
      epocaId: bodyMap['epoca_id']?.toString(),
      lote: bodyMap['lote']?.toString(),
      qtdAPesar: int.tryParse(bodyMap['qtd_a_pesar'].toString()),
      filtroDesc: bodyMap['filtro_desc']?.toString(),
      criteriosLista: criteriosLista,
    );

    final idServidor = local['id_servidor'] as int?;

    if (idServidor == null) {
      // Ainda não sincronizou a criação — só atualiza o payload pendente.
      final pendente = await OutboxDao.instance.buscarPendentePorEntidade(
        local['uuid'] as String,
        TipoOperacaoOutbox.criarPesagem,
      );
      if (pendente != null) {
        final payloadAntigo =
            json.decode(pendente['payload_json'] as String)
                as Map<String, dynamic>;
        final payloadNovo = Map<String, dynamic>.from(payloadAntigo)
          ..['local_id'] = bodyMap['local_id'] ?? payloadAntigo['local_id']
          ..['epoca_id'] = bodyMap['epoca_id'] ?? payloadAntigo['epoca_id']
          ..['lote'] = bodyMap['lote'] ?? payloadAntigo['lote']
          ..['qtd_a_pesar'] =
              bodyMap['qtd_a_pesar'] ?? payloadAntigo['qtd_a_pesar']
          ..['filtro_desc'] =
              bodyMap['filtro_desc'] ?? payloadAntigo['filtro_desc']
          ..['criterios_lista'] = criteriosLista;
        await OutboxDao.instance.reescreverPayload(
          pendente['id'] as int,
          payloadNovo,
        );
      }
      return {"success": true, "message": "Pesagem atualizada."};
    }

    final payloadEnvio = Map<String, dynamic>.from(bodyMap)
      ..['pesagem_id'] = idServidor;

    // Opção 2: nunca espera rede aqui também — grava local (já feito acima)
    // e entra na fila sempre.
    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.editarPesagem,
      entidadeUuid: local['uuid'] as String,
      payload: payloadEnvio,
    );
    return {"success": true, "message": "Pesagem atualizada."};
  }

  // ---------------------------------------------------------------------
  // Itens
  // ---------------------------------------------------------------------

  /// Busca a pesagem+itens no servidor e grava/reconcilia localmente.
  /// Devolve o id_local resultante, ou null se não conseguiu (sem conexão,
  /// erro, ou o servidor não confirmou sucesso).
  Future<int?> _baixarEImportarPesagemCompleta(
    int idServidor, {
    required String? bd,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/pesagem/get_pesagem_completa.php",
            ),
            body: json.encode({"bd": bd, "id_pesagem": idServidor}),
          )
          // Timeout maior que os outros: essa chamada pode trazer centenas
          // de itens de uma vez (já vimos pesagem com 272), uma internet
          // lenta mas funcionando ainda merece a chance de completar antes
          // de desistir.
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      if (data['success'] != true || data['pesagem'] == null) return null;

      final idLocalImportado = await PesagemLocalDao.instance
          .importarDoServidor(
        data['pesagem'] as Map<String, dynamic>,
        bd: bd ?? '',
      );

      final itensServidor = (data['itens'] as List<dynamic>?) ?? [];
      // Remove local o que o servidor não tem mais (ex: excluído pelo
      // sistema web) e corrige o número dos que só foram renumerados —
      // identifica pelo par animal+peso, não pelo numero_item (ver
      // ItemPesagemLocalDao.reconciliarComServidor pro raciocínio
      // completo). Só mexe em item já confirmado; nunca em item ainda
      // pendente de sincronizar, senão perderia peso digitado offline
      // antes mesmo dele ter chance de subir.
      await ItemPesagemLocalDao.instance.reconciliarComServidor(
        idLocalImportado,
        itensServidor,
      );
      await ItemPesagemLocalDao.instance.importarDoServidor(
        idLocalImportado,
        itensServidor,
      );
      return idLocalImportado;
    } catch (_) {
      // sem conexão de fato ou erro — quem chamou decide o fallback
      return null;
    }
  }

  bool _baixandoPendentes = false;

  /// true enquanto há download de itens de pesagens pendentes em andamento
  /// — a tela usa isso pra avisar que ainda não é seguro ir pro pasto sem
  /// sinal (mesmo padrão do AnimalCacheService.baixando).
  final ValueNotifier<bool> baixandoItensPendentes = ValueNotifier(false);

  /// Baixa antecipadamente os itens de toda pesagem em aberto que ainda não
  /// tem nenhum item salvo neste aparelho.
  ///
  /// Sem isso, uma pesagem que já existe no servidor mas nunca foi aberta
  /// neste aparelho fica com os itens vazios pra sempre assim que a
  /// internet cai — o vaqueiro chega no curral sem conseguir ver nem
  /// continuar o que já tinha sido pesado antes. Roda em segundo plano
  /// (quem chama não espera): melhor esforço, pesagem por pesagem, parando
  /// na hora se a internet cair no meio do caminho.
  Future<void> garantirItensDasPendentes(String? bd) async {
    if (_baixandoPendentes || !_online) return;
    _baixandoPendentes = true;
    baixandoItensPendentes.value = true;
    try {
      final locais = await PesagemLocalDao.instance.listarPendentesLocais(
        bd ?? '',
      );
      for (final local in locais) {
        if (!_online) break;
        final idServidor = local['id_servidor'] as int?;
        if (idServidor == null) continue; // ainda só existe neste aparelho

        final idLocal = local['id_local'] as int;
        final temItens = (await ItemPesagemLocalDao.instance
                .listarPorPesagemLocal(idLocal))
            .isNotEmpty;
        if (temItens) continue;

        await _baixarEImportarPesagemCompleta(idServidor, bd: bd);
      }
    } finally {
      _baixandoPendentes = false;
      baixandoItensPendentes.value = false;
    }
  }

  Future<Map<String, dynamic>> buscarPesagemCompleta({
    required String? bd,
    required int idPesagem,
    // true só na abertura inicial da tela — confirma com o servidor se
    // algum item já sincronizado foi excluído por fora do app (sistema web
    // ou outro dispositivo) desde a última vez. Fica false nas atualizações
    // rápidas entre um peso e outro (ex: depois de salvar um item), pra não
    // acrescentar uma chamada de rede extra a cada animal digitado.
    bool reconciliar = false,
  }) async {
    var local = await PesagemLocalDao.instance.resolverPorIdDeTela(idPesagem);

    // Mesmo quando a pesagem já é conhecida localmente (ex: cabeçalho
    // importado pela lista de pendentes), se ainda não tem nenhum item
    // salvo aqui é preciso buscar no servidor — senão a tela fica achando
    // que a pesagem está vazia pra sempre. importarDoServidor dos itens é
    // idempotente, então isso nunca duplica nem sobrescreve item já
    // existente (inclusive pendente de sincronizar).
    final semItensLocais = local != null &&
        (await ItemPesagemLocalDao.instance
                .listarPorPesagemLocal(local['id_local'] as int))
            .isEmpty;

    if ((local == null || semItensLocais || reconciliar) &&
        idPesagem > 0 &&
        _online) {
      final idLocalImportado = await _baixarEImportarPesagemCompleta(
        idPesagem,
        bd: bd,
      );
      if (idLocalImportado != null) {
        local = await PesagemLocalDao.instance.buscarPorIdLocal(
          idLocalImportado,
        );
      }
    }

    if (local == null) {
      return {
        "success": false,
        "message":
            "Pesagem não encontrada localmente e sem conexão para buscar no servidor.",
      };
    }

    final idLocal = local['id_local'] as int;
    final itensLocais = await ItemPesagemLocalDao.instance
        .listarPorPesagemLocal(idLocal);

    return {
      "success": true,
      "pesagem": await _pesagemLocalParaMapaServidor(local),
      "itens": itensLocais.map(_itemLocalParaMapaServidor).toList(),
    };
  }

  Future<Map<String, dynamic>> salvarItem(Map<String, dynamic> bodyMap) async {
    final idTela = int.tryParse(bodyMap['pesagem_id'].toString()) ?? 0;
    var local = await PesagemLocalDao.instance.resolverPorIdDeTela(idTela);

    // Pesagem existe no servidor (idTela > 0) mas ainda não foi cacheada
    // neste aparelho — cria o registro local de emergência para não perder
    // o peso que o vaqueiro acabou de digitar.
    if (local == null) {
      final criteriosLista = _paraListaCriterios(bodyMap['criterios_lista']);
      final idLocalCriado = await PesagemLocalDao.instance.inserir(
        uuid: 'auto-${DateTime.now().microsecondsSinceEpoch}',
        idServidor: idTela > 0 ? idTela : null,
        bd: bodyMap['bd']?.toString() ?? '',
        fazendaId: bodyMap['local_id']?.toString() ?? '',
        epocaId: bodyMap['epoca_id']?.toString() ?? '',
        lote: bodyMap['lote']?.toString() ?? '',
        qtdAPesar: int.tryParse(bodyMap['qtd_a_pesar'].toString()) ?? 0,
        filtroDesc: bodyMap['filtro_desc']?.toString(),
        usuario: bodyMap['usuario']?.toString(),
        criteriosLista: criteriosLista,
        statusSync: idTela > 0
            ? StatusSyncPesagem.sincronizado
            : StatusSyncPesagem.pendente,
      );
      local = await PesagemLocalDao.instance.buscarPorIdLocal(idLocalCriado);
    }

    final idLocalPesagem = local!['id_local'] as int;
    final idServidorPesagem = local['id_servidor'] as int?;
    final itemUuid = _uuid.v4();
    final numeroLocal = await ItemPesagemLocalDao.instance
        .proximoNumeroItemLocal(idLocalPesagem);
    final itemCampos = Map<String, dynamic>.from(
      bodyMap['item'] as Map,
    );

    await ItemPesagemLocalDao.instance.inserir(
      pesagemIdLocal: idLocalPesagem,
      uuid: itemUuid,
      numeroItemLocal: numeroLocal,
      campos: itemCampos,
    );

    final payloadEnvio = Map<String, dynamic>.from(bodyMap)
      ..['pesagem_id'] = idServidorPesagem ?? 0
      ..['uuid_app'] = local['uuid']
      ..['item'] = (Map<String, dynamic>.from(itemCampos)
        ..['uuid_app'] = itemUuid);

    // Opção 2 (decidida em sessão): salvar item NUNCA espera rede, mesmo
    // online — grava local e entra na fila, do mesmo jeito que já
    // acontecia no caminho offline. Numa pesagem com centenas de animais
    // em sequência, até um timeout curto "inteligente" ainda seria um
    // imposto por animal toda vez que a rede estivesse ruim naquele
    // instante exato (imprevisível, e pode se repetir dezenas de vezes
    // com sinal intermitente); só o caminho 100% local remove essa
    // variável por completo — "Confirma" fica sempre instantâneo. A
    // reconciliação por animal+peso que já existe garante que tudo sobe
    // certo depois, mesmo fora de ordem.
    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.salvarItem,
      entidadeUuid: itemUuid,
      dependeDeUuid: idServidorPesagem == null
          ? (local['uuid'] as String)
          : null,
      payload: payloadEnvio,
    );

    // A sincronização em segundo plano (SyncService) já cuida de subir isso
    // sozinha — pelo timer de primeiro plano (30s) ou assim que a
    // conectividade real voltar — sem precisar de um gatilho extra aqui.

    return {
      "success": true,
      "pesagem_id": idServidorPesagem ?? -idLocalPesagem,
      "numero_item": numeroLocal,
    };
  }

  Future<Map<String, dynamic>> excluirItem(Map<String, dynamic> bodyMap) async {
    final idTela = int.tryParse(bodyMap['pesagem_id'].toString()) ?? 0;
    final numero = int.tryParse(bodyMap['numero_item'].toString()) ?? 0;
    final local = await PesagemLocalDao.instance.resolverPorIdDeTela(idTela);
    if (local == null) return {"success": false};

    final idLocalPesagem = local['id_local'] as int;
    final item = await ItemPesagemLocalDao.instance.buscarPorPesagemENumero(
      idLocalPesagem,
      numero,
    );
    if (item == null) return {"success": false};

    final numeroServidor = item['numero_item_servidor'] as int?;

    if (numeroServidor == null) {
      // Nunca sincronizado: cancela a operação pendente em vez de gerar
      // exclusão remota — em qualquer status (pendente, erro ou conflito),
      // senão uma tentativa que já falhou no servidor fica presa pra
      // sempre em "Pendências de revisão" mesmo depois do item excluído.
      await OutboxDao.instance.cancelarPorEntidade(
        item['uuid'] as String,
        TipoOperacaoOutbox.salvarItem,
      );
      await ItemPesagemLocalDao.instance.excluir(item['id_local'] as int);
      return {"success": true};
    }

    await ItemPesagemLocalDao.instance.excluir(item['id_local'] as int);

    final payloadEnvio = {
      "bd": bodyMap['bd'],
      "pesagem_id": local['id_servidor'],
      "numero_item": numeroServidor,
    };

    // Opção 2: nunca espera rede — exclusão local (já feita acima) entra na
    // fila sempre.
    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.excluirItem,
      entidadeUuid: item['uuid'] as String,
      payload: payloadEnvio,
    );
    return {"success": true};
  }

  Future<Map<String, dynamic>> alterarItem(Map<String, dynamic> bodyMap) async {
    final idTela = int.tryParse(bodyMap['pesagem_id'].toString()) ?? 0;
    final numero = int.tryParse(bodyMap['numero_item'].toString()) ?? 0;
    final local = await PesagemLocalDao.instance.resolverPorIdDeTela(idTela);
    if (local == null) return {"success": false};

    final idLocalPesagem = local['id_local'] as int;
    final item = await ItemPesagemLocalDao.instance.buscarPorPesagemENumero(
      idLocalPesagem,
      numero,
    );
    if (item == null) return {"success": false};

    await ItemPesagemLocalDao.instance.atualizarCampos(
      item['id_local'] as int,
      peso: bodyMap['peso']?.toString(),
      obs: bodyMap['obs']?.toString(),
      criterioApartacao: bodyMap['criterio_apartacao']?.toString(),
    );

    final numeroServidor = item['numero_item_servidor'] as int?;

    if (numeroServidor == null) {
      // Ainda não sincronizado: reescreve o payload da operação pendente.
      final pendenteSalvar = await OutboxDao.instance.buscarPendentePorEntidade(
        item['uuid'] as String,
        TipoOperacaoOutbox.salvarItem,
      );
      if (pendenteSalvar != null) {
        final payloadAntigo =
            json.decode(pendenteSalvar['payload_json'] as String)
                as Map<String, dynamic>;
        final itemAntigo = Map<String, dynamic>.from(
          payloadAntigo['item'] as Map,
        );
        itemAntigo['peso'] = bodyMap['peso'];
        itemAntigo['obs'] = bodyMap['obs'];
        itemAntigo['criterio_apartacao'] = bodyMap['criterio_apartacao'];
        payloadAntigo['item'] = itemAntigo;
        payloadAntigo['criterios_lista'] = bodyMap['criterios_lista'];
        await OutboxDao.instance.reescreverPayload(
          pendenteSalvar['id'] as int,
          payloadAntigo,
        );
      }
      return {"success": true};
    }

    final payloadEnvio = {
      "bd": bodyMap['bd'],
      "pesagem_id": local['id_servidor'],
      "numero_item": numeroServidor,
      "peso": bodyMap['peso'],
      "obs": bodyMap['obs'],
      "criterio_apartacao": bodyMap['criterio_apartacao'],
      "criterios_lista": bodyMap['criterios_lista'],
    };

    // Opção 2: nunca espera rede — edição local (já feita acima) entra na
    // fila sempre.
    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.editarItem,
      entidadeUuid: item['uuid'] as String,
      payload: payloadEnvio,
    );
    return {"success": true};
  }

  /// Verifica se o animal já está pesado em OUTRA pesagem aberta (lote
  /// diferente) — olhando só o que já está salvo neste aparelho, sem
  /// depender de rede (ver ItemPesagemLocalDao.buscarPesagemAbertaPorAnimal
  /// pro raciocínio completo). Devolve o nome do lote conflitante, ou null
  /// se não achou nenhum.
  Future<Map<String, dynamic>?> buscarLoteAbertoPorAnimal({
    required String idAnimal,
    required int idPesagemDeTela,
  }) async {
    final local = await PesagemLocalDao.instance.resolverPorIdDeTela(
      idPesagemDeTela,
    );
    return ItemPesagemLocalDao.instance.buscarPesagemAbertaPorAnimal(
      idAnimal,
      excluirPesagemIdLocal: local?['id_local'] as int?,
    );
  }

  // ---------------------------------------------------------------------
  // Pendências de revisão (operações que o servidor recusou)
  // ---------------------------------------------------------------------

  /// Traduz as operações em "conflito" (recusadas explicitamente pelo
  /// servidor) para algo legível na tela — em vez de tipo_operacao/uuid
  /// crus, mostra qual lote e (quando aplicável) qual animal.
  Future<List<Map<String, dynamic>>> listarPendenciasRevisao() async {
    final conflitos = await OutboxDao.instance.listarConflitos();
    final resultado = <Map<String, dynamic>>[];
    for (final c in conflitos) {
      final payload =
          json.decode(c['payload_json'] as String) as Map<String, dynamic>;
      resultado.add(await _descreverPendencia(c, payload));
    }
    return resultado;
  }

  Future<Map<String, dynamic>> _descreverPendencia(
    Map<String, dynamic> outbox,
    Map<String, dynamic> payload,
  ) async {
    final tipo = outbox['tipo_operacao'] as String;
    Map<String, dynamic>? local;
    String? animalCodigo;

    switch (tipo) {
      case TipoOperacaoOutbox.criarPesagem:
      case TipoOperacaoOutbox.editarPesagem:
        local = await PesagemLocalDao.instance.buscarPorUuid(
          outbox['entidade_uuid'] as String,
        );
        break;
      case TipoOperacaoOutbox.salvarItem:
        final uuidPesagem = payload['uuid_app'] as String?;
        if (uuidPesagem != null) {
          local = await PesagemLocalDao.instance.buscarPorUuid(uuidPesagem);
        }
        animalCodigo = (payload['item'] as Map?)?['codigo_animal']
            ?.toString();
        break;
      case TipoOperacaoOutbox.editarItem:
      case TipoOperacaoOutbox.excluirItem:
        final idServidor = int.tryParse(
          payload['pesagem_id']?.toString() ?? '',
        );
        if (idServidor != null) {
          local = await PesagemLocalDao.instance.buscarPorIdServidor(
            idServidor,
          );
        }
        break;
    }

    const rotulos = {
      TipoOperacaoOutbox.criarPesagem: 'Criar pesagem',
      TipoOperacaoOutbox.salvarItem: 'Salvar peso',
      TipoOperacaoOutbox.editarItem: 'Editar peso',
      TipoOperacaoOutbox.excluirItem: 'Excluir peso',
      TipoOperacaoOutbox.editarPesagem: 'Editar pesagem',
    };

    return {
      'id': outbox['id'],
      'tipo': tipo,
      'rotuloTipo': rotulos[tipo] ?? tipo,
      'lote': local?['lote']?.toString() ?? payload['lote']?.toString(),
      'animalCodigo': animalCodigo,
      'mensagemErro':
          outbox['ultimo_erro']?.toString() ?? 'Motivo não informado.',
      'criadoEm': outbox['criado_em'],
    };
  }

  /// Bota a pendência de volta na fila normal de sincronização.
  Future<void> reenviarPendencia(int outboxId) =>
      OutboxDao.instance.reenfileirar(outboxId);

  /// Desiste de enviar essa operação — os dados continuam só neste
  /// aparelho, nunca vão pro servidor. Não apaga nada localmente.
  Future<void> descartarPendencia(int outboxId) =>
      OutboxDao.instance.cancelar(outboxId);
}

/// Decodifica um JSON de lista com segurança, devolvendo lista vazia se nulo/vazio/malformado.
dynamic jsonDecodeSeguro(String? texto) {
  if (texto == null || texto.trim().isEmpty) return [];
  try {
    return jsonDecodeReal(texto);
  } catch (_) {
    return [];
  }
}

dynamic jsonDecodeReal(String texto) => json.decode(texto);
