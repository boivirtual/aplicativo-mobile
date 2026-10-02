import 'package:flutter/material.dart';

/// Faixa de idade (em meses) de uma categoria — tabela_categoria_idade.
class CategoriaIdadeMapa {
  final int id;
  final int idadeDe;
  final int idadeAte;

  const CategoriaIdadeMapa({
    required this.id,
    required this.idadeDe,
    required this.idadeAte,
  });
}

/// Pasto do tabuleiro, como veio de api/rest/mapa-gado/tabuleiro.php.
class PastoMapa {
  final int id;
  final int fazendaId;
  final String descricao;
  final int modulo;
  final String capim;

  /// tbl_pasto_array_categoria — códigos separados por "!" (ex:
  /// "001!002!003!004!005"). A ordem importa: a primeira categoria da lista
  /// é a que o sistema web conta como bezerro.
  final String categorias;
  final int ordem;

  /// tbl_pasto_descricao_lote — "" quando o pasto não tem descrição.
  final String descricaoLote;

  /// false = módulos 1006 (NÃO UTILIZADO) / 1007 (ÁREA COMUM): não entram
  /// no Tabuleiro, só no Mapa Satélite (igual ao web).
  final bool tabuleiro;

  /// tbl_pasto_data_com_animais / _sem_animais — balão de informações do
  /// Mapa Satélite ("Animais no pasto há N dia(s)").
  final String? dataComAnimais;
  final String? dataSemAnimais;

  /// tbl_pasto_area (ha) — Lotação Kg/Ha.
  final double area;

  /// Número e ano do lote (tbl_pasto_id_lote/_ano_lote) — "L-0012/26";
  /// 0 = sem número (ex: descrição nova ainda não enviada ao servidor).
  final int idLote;
  final int anoLote;

  const PastoMapa({
    required this.id,
    required this.fazendaId,
    required this.descricao,
    required this.modulo,
    required this.capim,
    required this.categorias,
    required this.ordem,
    this.descricaoLote = '',
    this.tabuleiro = true,
    this.dataComAnimais,
    this.dataSemAnimais,
  });
}

/// Animal ativo num pasto (tbl_animal_pasto).
class AnimalPastoMapa {
  final int pastoId;
  final String? sexo;
  final String? nascimento;

  const AnimalPastoMapa({
    required this.pastoId,
    required this.sexo,
    required this.nascimento,
  });
}

/// Um card do tabuleiro já calculado.
class PastoTabuleiro {
  final PastoMapa pasto;
  final int bezerros;
  final int femeas;
  final int machos;
  final Color cor;

  const PastoTabuleiro({
    required this.pasto,
    required this.bezerros,
    required this.femeas,
    required this.machos,
    required this.cor,
  });

  int get total => bezerros + femeas + machos;

  /// Pastos de ENTRADA/SAÍDA — no web saem em branco e sem tipo de capim.
  bool get entradaSaida => pasto.modulo == MapaTabuleiroCalculo.moduloEntradaSaida;
}

/// Regras do Mapa Tabuleiro, replicadas de ler_mapa_gados.php (sistema
/// web) — contagem de bezerros/fêmeas/machos por pasto e a cor de cada
/// card. Funções puras (sem banco, sem tela) para poderem ser testadas
/// contra o resultado do web.
class MapaTabuleiroCalculo {
  MapaTabuleiroCalculo._();

  static const int moduloEntradaSaida = 999;

  /// Mesma paleta do web — muda de cor a cada módulo novo, repetindo depois
  /// da oitava.
  static const List<Color> cores = [
    Color(0xFF7FFFD4),
    Color(0xFF66CDAA),
    Color(0xFF40E0D0),
    Color(0xFF00FF7F),
    Color(0xFF48D1CC),
    Color(0xFF3CB371),
    Color(0xFF00CED1),
    Color(0xFF2E8B57),
  ];

  static const Color corEntradaSaida = Colors.white;

  /// Idade em meses completos — mesmo cálculo do web
  /// (DateTime::diff -> anos * 12 + meses), sempre positivo.
  ///
  /// Casos de borda imitando o PHP: nascimento vazio vira "hoje" (0
  /// meses); data inválida ou "0000-00-00" vira uma idade enorme (cai na
  /// última categoria, como acontece no web).
  static int idadeEmMeses(String? nascimento, DateTime hoje) {
    if (nascimento == null || nascimento.trim().isEmpty) return 0;
    final data = DateTime.tryParse(nascimento.trim());
    if (data == null || data.year <= 0) return 999999;

    var inicio = DateTime(data.year, data.month, data.day);
    var fim = DateTime(hoje.year, hoje.month, hoje.day);
    if (inicio.isAfter(fim)) {
      final t = inicio;
      inicio = fim;
      fim = t;
    }

    var meses = (fim.year - inicio.year) * 12 + (fim.month - inicio.month);
    if (fim.day < inicio.day) meses--;
    return meses < 0 ? 0 : meses;
  }

  /// Monta os cards de uma fazenda, na ordem do tabuleiro.
  static List<PastoTabuleiro> calcular({
    required List<PastoMapa> pastos,
    required List<AnimalPastoMapa> animais,
    required Map<int, CategoriaIdadeMapa> categorias,
    DateTime? hoje,
  }) {
    final dia = hoje ?? DateTime.now();

    final animaisPorPasto = <int, List<AnimalPastoMapa>>{};
    for (final a in animais) {
      animaisPorPasto.putIfAbsent(a.pastoId, () => []).add(a);
    }

    final ordenados = [...pastos]..sort((a, b) => a.ordem.compareTo(b.ordem));

    final resultado = <PastoTabuleiro>[];
    var indiceCor = 0;
    var moduloAnterior = 0;

    for (final pasto in ordenados) {
      final faixas = pasto.categorias
          .split('!')
          .map((c) => categorias[int.tryParse(c.trim()) ?? -1])
          .toList();

      final machosPorFaixa = List<int>.filled(faixas.length, 0);
      final femeasPorFaixa = List<int>.filled(faixas.length, 0);

      for (final animal in animaisPorPasto[pasto.id] ?? const <AnimalPastoMapa>[]) {
        final meses = idadeEmMeses(animal.nascimento, dia);
        for (var i = 0; i < faixas.length; i++) {
          if (!_dentroDaFaixa(meses, faixas[i])) continue;
          if (animal.sexo == 'F') {
            femeasPorFaixa[i]++;
          } else if (animal.sexo == 'M') {
            machosPorFaixa[i]++;
          }
        }
      }

      // Primeira faixa da lista do pasto = bezerros (macho ou fêmea).
      var bezerros = 0, femeas = 0, machos = 0;
      for (var i = 0; i < faixas.length; i++) {
        if (i == 0) {
          bezerros += machosPorFaixa[i] + femeasPorFaixa[i];
        } else {
          machos += machosPorFaixa[i];
          femeas += femeasPorFaixa[i];
        }
      }

      Color cor;
      if (pasto.modulo == moduloEntradaSaida) {
        cor = corEntradaSaida;
      } else {
        if (moduloAnterior != 0 && pasto.modulo > moduloAnterior) {
          indiceCor++;
        }
        if (indiceCor > cores.length - 1) indiceCor = 0;
        cor = cores[indiceCor];
        moduloAnterior = pasto.modulo;
      }

      resultado.add(
        PastoTabuleiro(
          pasto: pasto,
          bezerros: bezerros,
          femeas: femeas,
          machos: machos,
          cor: cor,
        ),
      );
    }

    return resultado;
  }

  /// Código de categoria que não existe (ou está na lixeira) chega ao PHP
  /// com faixa nula, e a comparação com null só é verdadeira para 0 meses —
  /// replicado aqui para o total bater com o web.
  static bool _dentroDaFaixa(int meses, CategoriaIdadeMapa? faixa) {
    if (faixa == null) return meses == 0;
    return meses >= faixa.idadeDe && meses <= faixa.idadeAte;
  }
}
