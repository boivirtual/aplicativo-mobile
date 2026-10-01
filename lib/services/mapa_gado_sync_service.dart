import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../data/daos/mapa_gado_dao.dart';
import 'connectivity_service.dart';

/// Download do cache do Mapa de Gado (Tabuleiro) — mesmo papel do
/// ChuvaSyncService.baixar, isolado da fila da pesagem. Por enquanto só
/// leitura: não há nada lançado offline para subir.
class MapaGadoSyncService {
  MapaGadoSyncService._();
  static final MapaGadoSyncService instance = MapaGadoSyncService._();

  bool _baixando = false;

  /// Baixa o tabuleiro de todas as fazendas do usuário. Melhor esforço:
  /// sem internet ou com erro, mantém o cache anterior e devolve false.
  Future<bool> baixar(String? bd, List<int> fazendas) async {
    if (bd == null || bd.isEmpty) return false;
    final ids = fazendas.where((f) => f > 0).toSet().toList();
    if (ids.isEmpty) return false;
    if (!ConnectivityService.instance.temInternetReal) return false;
    if (_baixando) return false;

    _baixando = true;
    try {
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/mapa-gado/tabuleiro.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({"bd": bd, "fazendas": ids}),
          )
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) return false;

      final data = json.decode(response.body);
      if (data['success'] != true) return false;

      List<Map<String, dynamic>> lista(String chave) =>
          ((data[chave] as List?) ?? const [])
              .map((e) => e as Map<String, dynamic>)
              .toList();

      await MapaGadoDao.instance.salvarDoServidor(
        bd: bd,
        fazendasConsultadas: ids,
        categorias: lista('categorias'),
        pastos: lista('pastos'),
        animais: lista('animais'),
      );
      return true;
    } catch (e) {
      debugPrint('[MapaGadoSync] baixar: falhou -> $e');
      return false;
    } finally {
      _baixando = false;
    }
  }
}
