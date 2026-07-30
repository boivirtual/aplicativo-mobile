import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/connectivity_service.dart';
import '../data/daos/animal_cache_dao.dart';
import '../data/daos/item_pesagem_local_dao.dart';

/// Camada única de acesso à API de animais.
///
/// buscarPorCodigo/buscarDetalhes ficam local-first (M4): uma vez que o
/// cache da fazenda foi baixado (AnimalCacheService), autocomplete e ficha
/// do animal funcionam 100% offline. buscarMaePorCodigo/buscarDetalhesMae
/// (busca global de mãe, modal "Consultar Mãe") também são local-first, mas
/// sobre o cache de TODAS as fazendas do usuário (não só a selecionada na
/// tela) — é assim que o "Consultar Mãe" já funciona online, e o cache
/// precisa espelhar essa mesma regra (ver
/// AnimalCacheService.garantirCacheDeTodasFazendas).
class AnimalRepository {
  AnimalRepository._();
  static final AnimalRepository instance = AnimalRepository._();

  bool get _online => ConnectivityService.instance.temInternetReal;

  String _formatarNascimento(dynamic bruto) {
    final texto = bruto?.toString() ?? '';
    final partes = texto.split('-');
    if (partes.length == 3) {
      return "${partes[2]}/${partes[1]}/${partes[0]}";
    }
    return texto;
  }

  Map<String, dynamic> _cacheParaAutocomplete(Map<String, dynamic> row) {
    return {
      'id': row['id_animal'],
      'codigo': row['codigo'],
      'nascimento': row['nascimento'],
    };
  }

  /// Idade em meses <= 7, contando dia do mês (igual ao PHP original:
  /// PERIOD_DIFF por ano/mês, com ajuste de -1 se o dia de hoje ainda não
  /// chegou no dia de nascimento).
  bool _idadeMenorIgual7Meses(String? nascimentoIso) {
    if (nascimentoIso == null || nascimentoIso.isEmpty) return false;
    final nascimento = DateTime.tryParse(nascimentoIso);
    if (nascimento == null) return false;
    final hoje = DateTime.now();
    int meses = (hoje.year - nascimento.year) * 12 + (hoje.month - nascimento.month);
    if (hoje.day < nascimento.day) meses--;
    return meses <= 7;
  }

  bool _jaDesmamado(String? pesoDesmama) {
    if (pesoDesmama == null || pesoDesmama.isEmpty) return false;
    return (double.tryParse(pesoDesmama) ?? 0) > 0;
  }

  /// Regra "mãe com apartação em lote aberto" (mesma do servidor,
  /// AnimalDao::getCriterioApartacaoMaeBezerroNaoDesmamado): só faz sentido
  /// perguntar pela mãe se ESTE animal for um bezerro (<=7 meses, ainda não
  /// desmamado) — a checagem em si é 100% local (ver
  /// ItemPesagemLocalDao.buscarCriterioApartacaoAberta).
  Future<String?> _buscarCriterioApartacaoMae(Map<String, dynamic> row) async {
    final idMae = row['id_mae']?.toString();
    if (idMae == null || idMae.isEmpty || idMae == '0') return null;
    if (!_idadeMenorIgual7Meses(row['nascimento']?.toString())) return null;
    if (_jaDesmamado(row['peso_desmama']?.toString())) return null;

    final item = await ItemPesagemLocalDao.instance
        .buscarCriterioApartacaoAberta(idMae);
    return item?['criterio']?.toString();
  }

  /// Regra "bezerro não desmamado com apartação em lote aberto" (mesma do
  /// servidor, AnimalDao::getBezerroNaoDesmamadoEmPesagemAberta): dado que
  /// ESTE animal é a mãe, procura entre os filhos cacheados (ver
  /// AnimalCacheDao.buscarFilhosPorIdMae) o mais recente que já tenha
  /// apartação registrada em algum lote aberto.
  Future<Map<String, dynamic>?> _buscarBezerroNaoDesmamado(
    String idAnimalMae,
  ) async {
    final filhos = await AnimalCacheDao.instance.buscarFilhosPorIdMae(
      idAnimalMae,
    );

    Map<String, dynamic>? melhor;
    int melhorOrdem = -1;
    for (final filho in filhos) {
      if (!_idadeMenorIgual7Meses(filho['nascimento']?.toString())) continue;
      if (_jaDesmamado(filho['peso_desmama']?.toString())) continue;

      final item = await ItemPesagemLocalDao.instance
          .buscarCriterioApartacaoAberta(filho['id_animal'].toString());
      if (item == null) continue;

      final ordem = (item['pesagem_id_local'] as int) * 1000000 +
          (item['numero_item_local'] as int);
      if (ordem > melhorOrdem) {
        melhorOrdem = ordem;
        melhor = {'codigo': filho['codigo'], 'criterio': item['criterio']};
      }
    }
    return melhor;
  }

  Future<Map<String, dynamic>> _cacheParaFicha(Map<String, dynamic> row) async {
    final criterioApartacaoMae = await _buscarCriterioApartacaoMae(row);
    final bezerroApartacaoMae = await _buscarBezerroNaoDesmamado(
      row['id_animal'].toString(),
    );

    return {
      'id': row['id_animal'],
      'sexo': row['sexo'],
      'nascimento': _formatarNascimento(row['nascimento']),
      'raca': row['raca'],
      'pelagem': row['pelagem'],
      'idMae': row['id_mae'],
      'brincoMae': row['brinco_mae'],
      'ultimoPeso': row['ultimo_peso'],
      'DataUltimo': row['data_ultimo_peso'],
      'estacaoMonta': false,
      // loteAberto/pesagemIdLoteAberto ficam sempre null aqui — quem checa
      // isso é PesagemRepository.buscarLoteAbertoPorAnimal (ver
      // pesagem_itens_screen.dart), que sobrescreve esses campos depois.
      'loteAberto': null,
      'pesagemIdLoteAberto': null,
      'criterioApartacaoMae': criterioApartacaoMae,
      'bezerroApartacaoMae': bezerroApartacaoMae,
      'codigo': row['codigo'],
    };
  }

  Future<List<dynamic>> buscarPorCodigo({
    required String termo,
    required String local,
    required String? bd,
  }) async {
    final temCache = await AnimalCacheDao.instance.temCacheParaFazenda(local);
    if (temCache) {
      final linhas = await AnimalCacheDao.instance.buscarPorCodigo(
        local,
        termo,
      );
      return linhas.map(_cacheParaAutocomplete).toList();
    }

    if (_online) {
      try {
        final response = await http
            .get(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/animal/list.php?id=$termo&local=$local&bd=$bd",
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          return json.decode(response.body) as List<dynamic>;
        }
      } catch (_) {
        // sem conexão de fato (ou internet lenta demais e estourou o
        // tempo limite) — cai para lista vazia abaixo em vez de travar a
        // digitação esperando a rede
      }
    }
    return [];
  }

  Future<Map<String, dynamic>> buscarDetalhes({
    required String id,
    required String local,
    required String? bd,
  }) async {
    final cacheRow = await AnimalCacheDao.instance.buscarPorId(id);
    if (cacheRow != null) {
      return _cacheParaFicha(cacheRow);
    }

    if (_online) {
      try {
        final response = await http
            .get(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/animal/info.php?id=$id&local=$local&bd=$bd",
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        // sem conexão de fato — cai para mapa vazio abaixo
      }
    }
    return {};
  }

  /// Proxy fino pro DAO — pra telas não precisarem importar o DAO
  /// diretamente só pra decidir se mostram "sem internet" quando ainda não
  /// há cache nenhum.
  Future<bool> temCacheDeAlgumaFazenda() =>
      AnimalCacheDao.instance.temCacheGlobal();

  Map<String, dynamic> _cacheParaAutocompleteMae(Map<String, dynamic> row) {
    return {'id': row['id_animal'], 'codigo': row['codigo']};
  }

  Map<String, dynamic> _cacheParaFilho(Map<String, dynamic> row) {
    return {
      'id': row['id_animal'],
      'codigo': row['codigo'],
      'nascimento': _formatarNascimento(row['nascimento']),
      'sexo': row['sexo'],
      'raca': row['raca'],
      'pelagem': row['pelagem'],
      'local_nome': row['fazenda_nome'],
    };
  }

  /// Busca de mãe (fêmeas adultas) em todas as fazendas do usuário — cache
  /// primeiro (ver AnimalCacheDao.buscarPorCodigoGlobalFemeaAdulta), rede só
  /// se ainda não houver cache de nenhuma fazenda.
  Future<List<dynamic>> buscarMaePorCodigo({
    required String termo,
    required String? bd,
  }) async {
    final temCache = await AnimalCacheDao.instance.temCacheGlobal();
    if (temCache) {
      final linhas = await AnimalCacheDao.instance
          .buscarPorCodigoGlobalFemeaAdulta(termo);
      return linhas.map(_cacheParaAutocompleteMae).toList();
    }

    if (_online) {
      try {
        final response = await http
            .get(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/animal/list_mae_global.php?id=$termo&bd=$bd",
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200 && response.body.isNotEmpty) {
          return json.decode(response.body) as List<dynamic>;
        }
      } catch (_) {
        // sem conexão de fato — cai para lista vazia abaixo
      }
    }
    return [];
  }

  /// Ficha da mãe (só os filhos, que é tudo que o modal usa) — cache
  /// primeiro, entre todas as fazendas.
  Future<Map<String, dynamic>> buscarDetalhesMae({
    required String id,
    required String? bd,
  }) async {
    final temCache = await AnimalCacheDao.instance.temCacheGlobal();
    if (temCache) {
      final filhos = await AnimalCacheDao.instance.buscarFilhosPorIdMae(id);
      return {'filhos': filhos.map(_cacheParaFilho).toList()};
    }

    if (_online) {
      try {
        final response = await http
            .get(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/animal/info_mae_global.php?id=$id&bd=$bd",
              ),
            )
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        }
      } catch (_) {
        // sem conexão de fato — cai para mapa vazio abaixo
      }
    }
    return {};
  }
}
