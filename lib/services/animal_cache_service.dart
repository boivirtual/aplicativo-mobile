import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import 'connectivity_service.dart';
import '../data/daos/animal_cache_dao.dart';

/// Baixa o cadastro de animais de uma fazenda para o cache local
/// (animais_cache), permitindo que autocomplete e ficha do animal
/// funcionem offline depois da primeira vez que houver sinal.
class AnimalCacheService {
  AnimalCacheService._();
  static final AnimalCacheService instance = AnimalCacheService._();

  final Set<String> _emAndamento = {};

  /// true enquanto há pelo menos um download de cadastro de animais em
  /// andamento — usado pela tela para mostrar "Baixando dados...".
  final ValueNotifier<bool> baixando = ValueNotifier(false);

  Future<void> garantirCacheDaFazenda(String fazendaId, String? bd) async {
    if (fazendaId.isEmpty || bd == null || bd.isEmpty) return;
    if (_emAndamento.contains(fazendaId)) return;
    if (!ConnectivityService.instance.temInternetReal) return;

    _emAndamento.add(fazendaId);
    baixando.value = true;
    try {
      final response = await http.get(
        Uri.parse(
          "${ApiConfig.baseUrl}/rest/animal/list_fazenda_completo.php?local=$fazendaId&bd=$bd",
        ),
      );
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true) {
          final animais = (data['animais'] as List)
              .map((e) => e as Map<String, dynamic>)
              .toList();
          await AnimalCacheDao.instance.salvarLote(fazendaId, animais);
        }
      }
    } catch (_) {
      // best-effort — não deve travar nenhuma tela se isso falhar
    } finally {
      _emAndamento.remove(fazendaId);
      if (_emAndamento.isEmpty) baixando.value = false;
    }
  }
}
