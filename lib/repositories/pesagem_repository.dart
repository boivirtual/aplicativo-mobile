import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// Camada única de acesso à API de pesagem.
///
/// Nesta etapa (M2) é um proxy 1:1: cada método faz exatamente a mesma
/// chamada HTTP que antes estava embutida na tela, sem nenhuma lógica local
/// ainda — a tela continua tratando statusCode/json.decode/exceções do jeito
/// que já tratava. Isso isola o risco do refactor (mover onde a chamada mora)
/// do risco da lógica offline (que entra depois, na M3).
class PesagemRepository {
  PesagemRepository._();
  static final PesagemRepository instance = PesagemRepository._();

  Future<http.Response> listarPendentes({
    required String? bd,
    required List<int> fazendas,
  }) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/list_pendentes.php"),
      body: json.encode({"bd": bd, "fazendas": fazendas}),
    );
  }

  Future<http.Response> listarFinalizadas({
    required String? bd,
    required List<int> fazendas,
  }) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/list_finalizadas.php"),
      body: json.encode({"bd": bd, "fazendas": fazendas}),
    );
  }

  Future<http.Response> criarPesagem(Map<String, dynamic> bodyMap) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/create_pesagem.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(bodyMap),
    );
  }

  Future<http.Response> atualizarPesagem(Map<String, dynamic> bodyMap) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/update_pesagem.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(bodyMap),
    );
  }

  Future<http.Response> buscarPesagemCompleta({
    required String? bd,
    required int idPesagem,
  }) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/get_pesagem_completa.php"),
      body: json.encode({"bd": bd, "id_pesagem": idPesagem}),
    );
  }

  Future<http.Response> salvarItem(Map<String, dynamic> bodyMap) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/save_item.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(bodyMap),
    );
  }

  Future<http.Response> excluirItem(Map<String, dynamic> bodyMap) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/delete_item.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(bodyMap),
    );
  }

  Future<http.Response> alterarItem(Map<String, dynamic> bodyMap) {
    return http.post(
      Uri.parse("${ApiConfig.baseUrl}/rest/pesagem/update_item.php"),
      headers: {"Content-Type": "application/json"},
      body: json.encode(bodyMap),
    );
  }
}
