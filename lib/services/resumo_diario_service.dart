import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import 'connectivity_service.dart';

/// Atividades já registradas no sistema para a fazenda no dia (Seção 1 do
/// Resumo): chuvaMm null = não choveu; mudouPasto = teve transferência de
/// animais entre pastos; nutricao = teve nutrição; nascimentos, abortos
/// (Aborto, Absorção e Natimorto) e mortes = quantos registros no dia;
/// pesados = quantos animais foram pesados no dia (Seção 4).
typedef AtividadesDoDia = ({
  double? chuvaMm,
  bool mudouPasto,
  bool nutricao,
  int nascimentos,
  int abortos,
  int mortes,
  int pesados,
});

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

  /// Seção 1: atividades já registradas no sistema para a [fazenda] no [dia]
  /// (ver [AtividadesDoDia]). Só online. null se não conseguiu consultar.
  Future<AtividadesDoDia?> atividadesDoDia(
    String bd,
    String fazenda,
    DateTime dia,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/resumo-diario/atividades_dia.php",
            ),
            headers: {"Content-Type": "application/json"},
            body: json.encode({
              'bd': bd,
              'fazenda': fazenda,
              'data': _diaApi(dia),
            }),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final dados = json.decode(response.body);
      if (dados is Map && dados['success'] == true) {
        final mm = dados['chuva_mm'];
        int qtd(String campo) {
          final v = dados[campo];
          return v is num ? v.toInt() : 0;
        }

        return (
          chuvaMm: mm is num ? mm.toDouble() : null,
          mudouPasto: dados['mudou_pasto'] == true,
          nutricao: dados['nutricao'] == true,
          nascimentos: qtd('nascimentos'),
          abortos: qtd('abortos'),
          mortes: qtd('mortes'),
          pesados: qtd('pesados'),
        );
      }
    } catch (e) {
      debugPrint('[ResumoDiario] atividades do dia: falhou -> $e');
    }
    return null;
  }

  /// Seção 3: animais ativos da [fazenda], no total e por pasto (id do pasto
  /// -> quantidade; pasto sem animais não vem), e quantas vacas prenhas ela
  /// tem. Só online. null se não conseguiu consultar.
  Future<({int total, int prenhas, Map<int, int> porPasto})?> animaisDaFazenda(
    String bd,
    String fazenda,
  ) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              "${ApiConfig.baseUrl}/rest/resumo-diario/animais_pastos.php",
            ),
            headers: {"Content-Type": "application/json"},
            body: json.encode({'bd': bd, 'fazenda': fazenda}),
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) return null;
      final dados = json.decode(response.body);
      if (dados is Map && dados['success'] == true) {
        final pastos = dados['pastos'];
        return (
          total: (dados['total'] as num?)?.toInt() ?? 0,
          prenhas: (dados['prenhas'] as num?)?.toInt() ?? 0,
          porPasto: <int, int>{
            if (pastos is Map)
              for (final e in pastos.entries)
                int.tryParse(e.key.toString()) ?? 0: (e.value as num).toInt(),
          },
        );
      }
    } catch (e) {
      debugPrint('[ResumoDiario] animais da fazenda: falhou -> $e');
    }
    return null;
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
        final tipo = dados['tipo_no_dia']?.toString();
        return (
          pendente: dados['pendente'] == true,
          tipoNoDia: tipo == null || tipo.isEmpty ? null : tipo,
        );
      }
    } catch (e) {
      debugPrint('[ResumoDiario] dia pendente: falhou -> $e');
    }
    return null;
  }
}
