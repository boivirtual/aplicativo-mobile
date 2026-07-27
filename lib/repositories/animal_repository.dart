import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../services/connectivity_service.dart';
import '../data/daos/animal_cache_dao.dart';

/// Camada única de acesso à API de animais.
///
/// buscarPorCodigo/buscarDetalhes ficam local-first (M4): uma vez que o
/// cache da fazenda foi baixado (AnimalCacheService), autocomplete e ficha
/// do animal funcionam 100% offline. buscarMaePorCodigo/buscarDetalhesMae
/// (busca global de mãe, modal "Consultar Mãe") continuam só online — cache-
/// ar o cadastro de TODAS as fazendas do usuário para essa busca é escopo
/// maior, fora desta entrega.
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

  Map<String, dynamic> _cacheParaFicha(Map<String, dynamic> row) {
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
      'loteAberto': row['lote_aberto'],
      'pesagemIdLoteAberto':
          int.tryParse(row['pesagem_id_lote_aberto']?.toString() ?? '') ?? 0,
      // Não disponíveis offline nesta entrega (dependem de consultas
      // adicionais que ainda não fazem parte do cache local) — degradam
      // graciosamente em vez de travar a tela.
      'criterioApartacaoMae': null,
      'bezerroApartacaoMae': null,
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
        final response = await http.get(
          Uri.parse(
            "${ApiConfig.baseUrl}/rest/animal/list.php?id=$termo&local=$local&bd=$bd",
          ),
        );
        if (response.statusCode == 200) {
          return json.decode(response.body) as List<dynamic>;
        }
      } catch (_) {
        // sem conexão de fato — cai para lista vazia abaixo
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

  Future<http.Response> buscarMaePorCodigo({
    required String termo,
    required String? bd,
  }) {
    return http.get(
      Uri.parse(
        "${ApiConfig.baseUrl}/rest/animal/list_mae_global.php?id=$termo&bd=$bd",
      ),
    );
  }

  Future<http.Response> buscarDetalhesMae({
    required String id,
    required String? bd,
  }) {
    return http.get(
      Uri.parse(
        "${ApiConfig.baseUrl}/rest/animal/info_mae_global.php?id=$id&bd=$bd",
      ),
    );
  }
}
