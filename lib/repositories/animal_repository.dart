import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Camada única de acesso à API de animais. Proxy 1:1 nesta etapa (M2) — o
/// cache local (M4) entra depois, sem mudar a assinatura destes métodos.
class AnimalRepository {
  AnimalRepository._();
  static final AnimalRepository instance = AnimalRepository._();

  Future<http.Response> buscarPorCodigo({
    required String termo,
    required String local,
    required String? bd,
  }) {
    return http.get(
      Uri.parse(
        "${ApiConfig.baseUrl}/rest/animal/list.php?id=$termo&local=$local&bd=$bd",
      ),
    );
  }

  Future<http.Response> buscarDetalhes({
    required String id,
    required String local,
    required String? bd,
  }) {
    return http
        .get(
          Uri.parse(
            "${ApiConfig.baseUrl}/rest/animal/info.php?id=$id&local=$local&bd=$bd",
          ),
        )
        .timeout(const Duration(seconds: 8));
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
