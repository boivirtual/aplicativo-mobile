import 'dart:convert';
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

    return {
      'tbl_pesagem_id': idServidor ?? -idLocal,
      'tbl_pesagem_codigo_local': row['fazenda_id'],
      'tbl_pesagem_codigo_epoca': row['epoca_id'],
      'tbl_pesagem_lote': row['lote'],
      'tbl_pesagem_qtd_animais_a_pesar': row['qtd_a_pesar'],
      'tbl_pesagem_qtd_animais_pesados': itensLocais.length,
      'tbl_pesagem_filtros': row['filtro_desc'],
      'tbl_pesagem_finalizada': row['finalizada'],
      'tbl_pesagem_criterios_apartacao': criterios.join(', '),
      'tbl_pesagem_data': row['criado_em'],
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
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/list_pendentes.php"),
          body: json.encode({"bd": bd, "fazendas": fazendas}),
        );
        if (response.statusCode == 200) {
          final lista = json.decode(response.body) as List<dynamic>;
          for (final p in lista) {
            await PesagemLocalDao.instance.importarDoServidor(
              p as Map<String, dynamic>,
            );
          }
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

  Future<List<dynamic>> listarFinalizadas({
    required String? bd,
    required List<int> fazendas,
  }) async {
    if (_online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/list_finalizadas.php"),
          body: json.encode({"bd": bd, "fazendas": fazendas}),
        );
        if (response.statusCode == 200) {
          final lista = json.decode(response.body) as List<dynamic>;
          for (final p in lista) {
            await PesagemLocalDao.instance.importarDoServidor(
              p as Map<String, dynamic>,
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

    if (_online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/create_pesagem.php"),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payloadEnvio),
        );
        if (response.statusCode == 200) {
          final resJson = json.decode(response.body);
          if (resJson['success'] == true) {
            final idServidor = int.parse(resJson['pesagem_id'].toString());
            await PesagemLocalDao.instance.confirmarSincronizacao(
              idLocal,
              idServidor,
            );
            return {"success": true, "pesagem_id": idServidor};
          }
        }
      } catch (_) {
        // cai para a fila offline abaixo
      }
    }

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

    if (_online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/update_pesagem.php"),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payloadEnvio),
        );
        if (response.statusCode == 200) {
          final resJson = json.decode(response.body);
          if (resJson['success'] == true) {
            return {
              "success": true,
              "message": resJson['message'] ?? "Pesagem atualizada com sucesso.",
            };
          }
        }
      } catch (_) {
        // cai para a fila offline abaixo
      }
    }

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

  Future<Map<String, dynamic>> buscarPesagemCompleta({
    required String? bd,
    required int idPesagem,
  }) async {
    var local = await PesagemLocalDao.instance.resolverPorIdDeTela(idPesagem);

    if (local == null && idPesagem > 0 && _online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/get_pesagem_completa.php"),
          body: json.encode({"bd": bd, "id_pesagem": idPesagem}),
        );
        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['success'] == true && data['pesagem'] != null) {
            final idLocalImportado = await PesagemLocalDao.instance
                .importarDoServidor(data['pesagem'] as Map<String, dynamic>);
            await ItemPesagemLocalDao.instance.importarDoServidor(
              idLocalImportado,
              (data['itens'] as List<dynamic>?) ?? [],
            );
            local = await PesagemLocalDao.instance.buscarPorIdLocal(
              idLocalImportado,
            );
          }
        }
      } catch (_) {
        // sem conexão de fato ou erro — segue para a checagem abaixo
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

    final idLocalItem = await ItemPesagemLocalDao.instance.inserir(
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

    if (idServidorPesagem != null && _online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/save_item.php"),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payloadEnvio),
        );
        if (response.statusCode == 200) {
          final resJson = json.decode(response.body);
          if (resJson['success'] == true) {
            final numeroServidor = int.parse(
              resJson['numero_item'].toString(),
            );
            await ItemPesagemLocalDao.instance.confirmarSincronizacao(
              idLocalItem,
              numeroServidor,
            );
            return {
              "success": true,
              "pesagem_id": idServidorPesagem,
              "numero_item": numeroServidor,
            };
          }
        }
      } catch (_) {
        // cai para a fila offline abaixo
      }
    }

    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.salvarItem,
      entidadeUuid: itemUuid,
      dependeDeUuid: idServidorPesagem == null
          ? (local['uuid'] as String)
          : null,
      payload: payloadEnvio,
    );

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
      // Nunca sincronizado: cancela a operação pendente em vez de gerar exclusão remota.
      final pendenteSalvar = await OutboxDao.instance.buscarPendentePorEntidade(
        item['uuid'] as String,
        TipoOperacaoOutbox.salvarItem,
      );
      if (pendenteSalvar != null) {
        await OutboxDao.instance.cancelar(pendenteSalvar['id'] as int);
      }
      await ItemPesagemLocalDao.instance.excluir(item['id_local'] as int);
      return {"success": true};
    }

    await ItemPesagemLocalDao.instance.excluir(item['id_local'] as int);

    final payloadEnvio = {
      "bd": bodyMap['bd'],
      "pesagem_id": local['id_servidor'],
      "numero_item": numeroServidor,
    };

    if (_online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/delete_item.php"),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payloadEnvio),
        );
        if (response.statusCode == 200) {
          return {"success": true};
        }
      } catch (_) {
        // cai para a fila offline abaixo
      }
    }

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

    if (_online) {
      try {
        final response = await http.post(
          Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/update_item.php"),
          headers: {"Content-Type": "application/json"},
          body: json.encode(payloadEnvio),
        );
        if (response.statusCode == 200) {
          return {"success": true};
        }
      } catch (_) {
        // cai para a fila offline abaixo
      }
    }

    await OutboxDao.instance.enfileirar(
      tipoOperacao: TipoOperacaoOutbox.editarItem,
      entidadeUuid: item['uuid'] as String,
      payload: payloadEnvio,
    );
    return {"success": true};
  }
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
