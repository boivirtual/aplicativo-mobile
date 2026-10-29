import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'connectivity_service.dart';

/// Dados do servidor usados pelo Resumo Diário da Fazenda.
class ResumoDiarioService {
  ResumoDiarioService._();
  static final instance = ResumoDiarioService._();

  String _chaveResponsaveis(String bd, String fazenda) =>
      'resumo_responsaveis_${bd}_${int.tryParse(fazenda) ?? fazenda}';

  /// Opções do select "Responsável" do Tratamento: usuários ativos com
  /// acesso à fazenda. Com internet busca no servidor e guarda no aparelho;
  /// sem internet (ou se falhar) usa a última lista guardada.
  Future<List<MapEntry<String, String>>> responsaveis(
    String bd,
    String fazenda,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    final chave = _chaveResponsaveis(bd, fazenda);
    if (ConnectivityService.instance.temInternetReal) {
      try {
        final response = await http
            .post(
              Uri.parse(
                "${ApiConfig.baseUrl}/rest/resumo-diario/responsaveis.php",
              ),
              headers: {"Content-Type": "application/json"},
              body: json.encode({'bd': bd, 'fazenda': fazenda}),
            )
            .timeout(const Duration(seconds: 15));
        if (response.statusCode == 200) {
          final dados = json.decode(response.body);
          if (dados is Map && dados['success'] == true) {
            await prefs.setString(
              chave,
              json.encode(dados['responsaveis'] ?? const []),
            );
          }
        }
      } catch (e) {
        debugPrint('[ResumoDiario] responsáveis: falhou -> $e');
      }
    }
    final guardado = prefs.getString(chave);
    if (guardado == null) return [];
    return [
      for (final r in (json.decode(guardado) as List))
        MapEntry((r as Map)['id'].toString(), r['nome'].toString()),
    ];
  }

  static String _diaApi(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// "Registrar Folga" do modal do dia sem resumo: grava o [dia] da
  /// [fazenda] como Folga, com o [usuario]. Só online. Devolve null se
  /// gravou (ou já estava gravado) e a mensagem de erro se não conseguiu.
  Future<String?> registrarFolga(
    String bd,
    String fazenda,
    String usuario,
    DateTime dia,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse("${ApiConfig.baseUrl}/rest/resumo-diario/folga.php"),
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              'bd': bd,
              'fazenda': fazenda,
              'usuario': usuario,
              'data': _diaApi(dia),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final dados = json.decode(response.body);
        if (dados is Map) {
          if (dados['success'] == true) return null;
          final msg = dados['message']?.toString();
          if (msg != null && msg.isNotEmpty) return msg;
        }
      }
    } catch (e) {
      debugPrint('[ResumoDiario] registrar folga: falhou -> $e');
    }
    return 'Não foi possível registrar a folga. Tente novamente.';
  }

  /// Tela inicial: o dia anterior a [data] ficou sem resumo da [fazenda]
  /// (um resumo por data e fazenda)? E a própria [data] já tem registro
  /// (tipoNoDia: 'R' = Resumo, 'F' = Folga, null = livre)? Só online
  /// (consulta direto no servidor). null se não conseguiu conferir (sem
  /// resposta ou resposta com erro).
  Future<({bool pendente, String? tipoNoDia})?> diaAnteriorPendente(
    String bd,
    String fazenda,
    DateTime data,
  ) async {
    final dia = _diaApi(data);
    try {
      final response = await http
          .post(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/resumo-diario/dia_pendente.php",
            ),
            headers: {"Content-Type": "application/json"},
            body: json.encode({'bd': bd, 'fazenda': fazenda, 'data': dia}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final dados = json.decode(response.body);
      if (dados is Map && dados['success'] == true) {
        return dados['pendente'] == true;
      }
    } catch (e) {
      debugPrint('[ResumoDiario] dia pendente: falhou -> $e');
    }
    return null;
  }
}
