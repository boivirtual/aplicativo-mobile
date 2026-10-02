import 'mapa_tabuleiro_calculo.dart';

/// Uma linha da tabela MACHOS | FÊMEAS | BEZERROS M/F (null = célula vazia).
class LinhaAnimaisPasto {
  final String? faixaMacho;
  final int? qtdMacho;
  final String? faixaFemea;
  final int? qtdFemea;
  final String? faixaBezerro;
  final int? qtdBezerro;

  const LinhaAnimaisPasto({
    this.faixaMacho,
    this.qtdMacho,
    this.faixaFemea,
    this.qtdFemea,
    this.faixaBezerro,
    this.qtdBezerro,
  });
}

/// Regras da tela do pasto ("Mapa de Gado - Movimentações"), replicadas de
/// form_mapa_gados_movimentacao.php, popular_select_categoria_sexo.php,
/// popular_select_pasto.php e funcao_kg_ha_pasto.php (sistema web) —
/// funções puras para poderem ser testadas.
class PastoMovimentacaoCalculo {
  PastoMovimentacaoCalculo._();

  static const _faixaBezerro = '00 a 07 meses';

  /// Texto da faixa: "08 a 12 meses"; a última faixa (até 999999999) é
  /// "> 36 meses" (o web usa "m"; o modelo do app usa "meses").
  static String rotuloFaixa(CategoriaIdadeMapa? c) {
    if (c == null) return '';
    if (c.idadeAte == 999999999) return '> 36 meses';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(c.idadeDe)} a ${dois(c.idadeAte)} meses';
  }

  /// Tabela da tela, igual ao web: conta por faixa da lista de categorias
  /// do pasto; bezerros = categoria 001 (machos + fêmeas) na 1ª linha; as
  /// demais faixas (posições 2 a 5 da lista) só aparecem quando têm animal,
  /// uma por linha, machos e fêmeas preenchendo cada um a sua coluna.
  static List<LinhaAnimaisPasto> linhas({
    required PastoMapa pasto,
    required List<AnimalPastoMapa> animaisDoPasto,
    required Map<int, CategoriaIdadeMapa> categorias,
    DateTime? hoje,
  }) {
    final dia = hoje ?? DateTime.now();
    final codigos = pasto.categorias
        .split('!')
        .map((c) => int.tryParse(c.trim()) ?? -1)
        .toList();
    final faixas = codigos.map((c) => categorias[c]).toList();

    final machos = List<int>.filled(faixas.length, 0);
    final femeas = List<int>.filled(faixas.length, 0);
    for (final a in animaisDoPasto) {
      final meses = MapaTabuleiroCalculo.idadeEmMeses(a.nascimento, dia);
      for (var i = 0; i < faixas.length; i++) {
        final f = faixas[i];
        final dentro = f == null
            ? meses == 0
            : meses >= f.idadeDe && meses <= f.idadeAte;
        if (!dentro) continue;
        if (a.sexo == 'F') {
          femeas[i]++;
        } else if (a.sexo == 'M') {
          machos[i]++;
        }
      }
    }

    var bezerros = 0;
    for (var i = 0; i < codigos.length; i++) {
      if (codigos[i] == 1) bezerros += femeas[i] + machos[i];
    }

    // Posições 1..4 da lista (a 0 é a dos bezerros), na ordem.
    final faixasMacho = <int>[];
    final faixasFemea = <int>[];
    for (var j = 1; j <= 4 && j < faixas.length; j++) {
      if (machos[j] != 0) faixasMacho.add(j);
      if (femeas[j] != 0) faixasFemea.add(j);
    }

    final linhas = <LinhaAnimaisPasto>[];
    for (var i = 0; i < 4; i++) {
      final m = i < faixasMacho.length ? faixasMacho[i] : null;
      final f = i < faixasFemea.length ? faixasFemea[i] : null;
      final temBezerro = i == 0 && bezerros > 0;
      if (m == null && f == null && !temBezerro) continue;
      linhas.add(
        LinhaAnimaisPasto(
          faixaMacho: m == null ? null : rotuloFaixa(faixas[m]),
          qtdMacho: m == null ? null : machos[m],
          faixaFemea: f == null ? null : rotuloFaixa(faixas[f]),
          qtdFemea: f == null ? null : femeas[f],
          faixaBezerro: temBezerro ? _faixaBezerro : null,
          qtdBezerro: temBezerro ? bezerros : null,
        ),
      );
    }
    return linhas;
  }

  /// Dias entre hoje e a data (com animais / sem animais), como o
  /// DateTime::diff()->days do web.
  static int dias(String? data, {DateTime? agora}) {
    final d = data == null ? null : DateTime.tryParse(data);
    if (d == null) return 0;
    return (agora ?? DateTime.now()).difference(d).inDays.abs();
  }

  /// Idade em meses como o TIMESTAMPDIFF(MONTH, ...) do MySQL, nunca
  /// negativa (GREATEST(..., 0)) e nascimento vazio = hoje.
  static int _mesesSql(String? nascimento, DateTime hoje) {
    final d = nascimento == null ? null : DateTime.tryParse(nascimento);
    if (d == null || d.isAfter(hoje)) return 0;
    var meses = (hoje.year - d.year) * 12 + (hoje.month - d.month);
    if (hoje.day < d.day) meses--;
    return meses < 0 ? 0 : meses;
  }

  /// Lotação (Kg/Ha) do pasto — funcao_kg_ha_pasto.php: cada animal vale o
  /// peso médio da fazenda para a sua categoria (todas as categorias) +
  /// sexo; soma dividida pela área, arredondada. null = sem área, sem
  /// animal ou sem peso (o web não mostra).
  static int? kgHa({
    required List<AnimalPastoMapa> animaisDoPasto,
    required Map<int, CategoriaIdadeMapa> categorias,
    required Map<String, int> pesosMedios,
    required double area,
    DateTime? hoje,
  }) {
    if (animaisDoPasto.isEmpty || area <= 0) return null;
    final dia = hoje ?? DateTime.now();
    var kg = 0;
    for (final a in animaisDoPasto) {
      final meses = _mesesSql(a.nascimento, dia);
      for (final c in categorias.values) {
        if (meses >= c.idadeDe && meses <= c.idadeAte) {
          kg += pesosMedios['${c.id}|${a.sexo}'] ?? 0;
        }
      }
    }
    if (kg <= 0) return null;
    return (kg / area).round();
  }

  /// 3306 -> "3.306"
  static String milhar(int n) {
    final s = n.abs().toString();
    final b = StringBuffer(n < 0 ? '-' : '');
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
      b.write(s[i]);
    }
    return b.toString();
  }

  /// "BEZERROS  L-0012/26" — descrição do lote + número/ano (igual ao web:
  /// sempre com um espaço entre os dois).
  static String descricaoLoteComId(PastoMapa p) {
    final id = p.idLote != 0
        ? 'L-${p.idLote.toString().padLeft(4, '0')}/${(p.anoLote % 100).toString().padLeft(2, '0')}'
        : '';
    return '${p.descricaoLote} $id'.trim().isEmpty ? '' : '${p.descricaoLote} $id';
  }

  /// Opções de "Categoria e Sexo" (popular_select_categoria_sexo.php):
  /// bezerros (categoria 001, os dois sexos) e depois as categorias 002 a
  /// 005 de machos e de fêmeas que têm animal no pasto.
  static List<String> opcoesCategoriaSexo({
    required List<AnimalPastoMapa> animaisDoPasto,
    required Map<int, CategoriaIdadeMapa> categorias,
    DateTime? hoje,
  }) {
    final dia = hoje ?? DateTime.now();
    final machos = <int, int>{};
    final femeas = <int, int>{};
    for (final a in animaisDoPasto) {
      final meses = MapaTabuleiroCalculo.idadeEmMeses(a.nascimento, dia);
      for (final c in categorias.values) {
        if (meses < c.idadeDe || meses > c.idadeAte) continue;
        final mapa = a.sexo == 'F' ? femeas : (a.sexo == 'M' ? machos : null);
        if (mapa != null) mapa[c.id] = (mapa[c.id] ?? 0) + 1;
      }
    }

    const rotulos = {
      2: '08 a 12 meses',
      3: '13 a 24 meses',
      4: '25 a 36 meses',
      5: '> 36 meses',
    };
    final opcoes = <String>[];
    if ((femeas[1] ?? 0) + (machos[1] ?? 0) > 0) opcoes.add('00 a 07 meses');
    for (var c = 2; c <= 5; c++) {
      if ((machos[c] ?? 0) > 0) opcoes.add('${rotulos[c]} - Macho');
    }
    for (var c = 2; c <= 5; c++) {
      if ((femeas[c] ?? 0) > 0) opcoes.add('${rotulos[c]} - Fêmea');
    }
    return opcoes;
  }
}
