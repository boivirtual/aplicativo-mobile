/// Regras da "Composição da Descrição do Lote", replicadas de
/// mapa_gados.js (sistema web: popular_situacao, exibir_parametro_3,
/// montar_descricao_lote, confirma_composicao_descricao_lote) — funções
/// puras para poderem ser testadas.
///
/// Os códigos de descrição são fixos no web (tbl_descricao_lote_animais):
/// 01 VACAS, 02 NOVILHAS, 03 BEZERROS, 04 GARROTES, 05 BOIS, 06 TOUROS,
/// 07 VACAS LEITE, 08 NOVILHAS PRECOCE.
class DescricaoLoteComposicao {
  DescricaoLoteComposicao._();

  static const int maxLotes = 6;

  static const _comSituacao = {1, 2, 7, 8};
  static const _comSexo = {3};

  /// Opções do segundo campo (Situação ou Sexo), na ordem do web. Lista
  /// vazia = a descrição não tem segundo campo.
  static List<MapEntry<int, String>> opcoesParametro2(int descricaoId) {
    if (_comSituacao.contains(descricaoId)) {
      return const [
        MapEntry(1, 'VAZIAS'),
        MapEntry(2, 'CHEIAS'),
        MapEntry(3, 'MOJANDO'),
        MapEntry(4, 'PARIDAS'),
        MapEntry(5, 'DESCARTE'),
      ];
    }
    if (_comSexo.contains(descricaoId)) {
      return const [
        MapEntry(3, 'MACHO/FÊMEA'),
        MapEntry(1, 'MACHO'),
        MapEntry(2, 'FÊMEA'),
      ];
    }
    return const [];
  }

  static String rotuloParametro2(int descricaoId) =>
      _comSexo.contains(descricaoId) ? 'Sexo' : 'Situação';

  /// Se mostra a pergunta "Informar Data da Parição/Nascimento?".
  /// Situação VAZIAS (1) e DESCARTE (5) não têm data.
  static bool perguntaData(int descricaoId, int? parametro2) {
    if (parametro2 == null || parametro2 == 0) return false;
    if (_comSituacao.contains(descricaoId)) {
      return parametro2 != 1 && parametro2 != 5;
    }
    return _comSexo.contains(descricaoId);
  }

  static String rotuloData(int descricaoId) =>
      _comSexo.contains(descricaoId) ? 'Nascimento' : 'Parição';

  /// Mês/ano no formato do web: "MM/AA".
  static String formatarMesAno(DateTime d) =>
      '${d.month.toString().padLeft(2, '0')}/${(d.year % 100).toString().padLeft(2, '0')}';

  /// Uma linha (um lote): "DESCRIÇÃO SITUAÇÃO MM/AA-MM/AA". Sem segundo
  /// campo fica "DESCRIÇÃO " (com o espaço no fim, igual ao web — é assim
  /// que está gravado no banco).
  static String montarLinha({
    required String descricao,
    String? parametro2,
    List<DateTime> datas = const [],
  }) {
    var linha = '${descricao.trim()} ${parametro2 ?? ''}';
    if (datas.isNotEmpty) {
      linha += ' ${datas.map(formatarMesAno).join('-')}';
    }
    return linha;
  }

  /// Descrição completa: as linhas preenchidas separadas por "-".
  static String montarDescricao(List<String> linhas) =>
      linhas.where((l) => l.isNotEmpty).join('-');

  /// Mesmas mensagens do web. null = válido.
  static String? validarLinha(int? descricaoId, int? parametro2) {
    if (descricaoId == null || descricaoId == 0) {
      return 'Selecione a Descrição do Lote';
    }
    if ((parametro2 == null || parametro2 == 0) &&
        opcoesParametro2(descricaoId).isNotEmpty) {
      return _comSexo.contains(descricaoId)
          ? 'Selecione o Sexo.'
          : 'Selecione a Situação.';
    }
    return null;
  }
}
