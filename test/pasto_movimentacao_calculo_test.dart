// Tela do pasto ("Mapa de Gado - Movimentações"): mesmas regras de
// form_mapa_gados_movimentacao.php e funcao_kg_ha_pasto.php (sistema web).
import 'dart:convert';
import 'dart:io';

import 'package:boivirtual/utils/mapa_tabuleiro_calculo.dart';
import 'package:boivirtual/utils/pasto_movimentacao_calculo.dart';
import 'package:flutter_test/flutter_test.dart';

const _categorias = {
  1: CategoriaIdadeMapa(id: 1, idadeDe: 0, idadeAte: 7),
  2: CategoriaIdadeMapa(id: 2, idadeDe: 8, idadeAte: 12),
  3: CategoriaIdadeMapa(id: 3, idadeDe: 13, idadeAte: 24),
  4: CategoriaIdadeMapa(id: 4, idadeDe: 25, idadeAte: 36),
  5: CategoriaIdadeMapa(id: 5, idadeDe: 37, idadeAte: 999999999),
};

AnimalPastoMapa _a(String sexo, String nasc) =>
    AnimalPastoMapa(pastoId: 1, sexo: sexo, nascimento: nasc);

void main() {
  final hoje = DateTime(2026, 10, 2);
  const pasto = PastoMapa(
    id: 1,
    fazendaId: 56,
    descricao: 'P. BOMBA 03',
    modulo: 1,
    capim: 'MOMBAÇA',
    categorias: '001!002!003!004!005',
    ordem: 1,
    descricaoLote: 'BEZERROS ',
    idLote: 12,
    anoLote: 2026,
    area: 2,
  );

  test('tabela: bezerros na 1ª linha, só faixas com animal, compactadas', () {
    final linhas = PastoMovimentacaoCalculo.linhas(
      pasto: pasto,
      animaisDoPasto: [
        _a('M', '2026-06-01'), // bezerro
        _a('F', '2026-06-01'), // bezerro
        _a('F', '2026-06-01'), // bezerro
        _a('M', '2025-12-01'), // 08 a 12
        _a('F', '2025-12-01'), // 08 a 12
        _a('F', '2025-12-01'), // 08 a 12
        _a('F', '2025-12-01'), // 08 a 12
        _a('F', '2025-06-01'), // 13 a 24
        _a('M', '2020-01-01'), // > 36
      ],
      categorias: _categorias,
      hoje: hoje,
    );
    expect(linhas.length, 2);
    expect(linhas[0].faixaMacho, '08 a 12 meses');
    expect(linhas[0].qtdMacho, 1);
    expect(linhas[0].faixaFemea, '08 a 12 meses');
    expect(linhas[0].qtdFemea, 3);
    expect(linhas[0].faixaBezerro, '00 a 07 meses');
    expect(linhas[0].qtdBezerro, 3);
    expect(linhas[1].faixaMacho, '> 36 meses');
    expect(linhas[1].faixaFemea, '13 a 24 meses');
    expect(linhas[1].faixaBezerro, isNull);
  });

  test('lote "L-0012/26", milhar e dias', () {
    expect(PastoMovimentacaoCalculo.descricaoLoteComId(pasto), 'BEZERROS  L-0012/26');
    expect(PastoMovimentacaoCalculo.milhar(3306), '3.306');
    expect(PastoMovimentacaoCalculo.milhar(15660), '15.660');
    expect(PastoMovimentacaoCalculo.milhar(99), '99');
    expect(
      PastoMovimentacaoCalculo.dias('2026-09-25 10:00:00', agora: DateTime(2026, 10, 2, 11)),
      7,
    );
  });

  test('Kg/Ha: peso médio da categoria+sexo / área', () {
    final kg = PastoMovimentacaoCalculo.kgHa(
      animaisDoPasto: [_a('M', '2025-12-01'), _a('F', '2025-12-01')],
      categorias: _categorias,
      pesosMedios: {'2|M': 236, '2|F': 221},
      area: 2,
      hoje: hoje,
    );
    expect(kg, ((236 + 221) / 2).round());
    expect(
      PastoMovimentacaoCalculo.kgHa(
        animaisDoPasto: const [],
        categorias: _categorias,
        pesosMedios: const {},
        area: 2,
      ),
      isNull,
    );
  });

  test('opções de Categoria e Sexo (popular_select_categoria_sexo.php)', () {
    final opcoes = PastoMovimentacaoCalculo.opcoesCategoriaSexo(
      animaisDoPasto: [
        _a('F', '2026-06-01'),
        _a('M', '2025-12-01'),
        _a('F', '2020-01-01'),
      ],
      categorias: _categorias,
      hoje: hoje,
    );
    expect(opcoes, ['00 a 07 meses', '08 a 12 meses - Macho', '> 36 meses - Fêmea']);
  });

  // Dados reais (opcional):
  //   MAPA_TABULEIRO_JSON = saída do api/rest/mapa-gado/tabuleiro.php
  //   MAPA_KGHA_JSON      = {pasto: kg_ha} de calcular_kg_ha_pastos() do web
  final tab = Platform.environment['MAPA_TABULEIRO_JSON'];
  final esperadoKg = Platform.environment['MAPA_KGHA_JSON'];
  test(
    'Kg/Ha bate com funcao_kg_ha_pasto.php em dados reais',
    () {
      final dados = json.decode(File(tab!).readAsStringSync());
      final esperado = (json.decode(File(esperadoKg!).readAsStringSync()) as Map)
          .map((k, v) => MapEntry(int.parse(k.toString()), v as int));
      final categorias = {
        for (final c in dados['categorias'])
          c['id'] as int: CategoriaIdadeMapa(id: c['id'], idadeDe: c['de'], idadeAte: c['ate']),
      };
      final pesos = <int, Map<String, int>>{};
      for (final p in dados['pesos_medios']) {
        pesos.putIfAbsent(p['local'] as int, () => {})['${p['categoria']}|${p['sexo']}'] =
            p['peso'] as int;
      }
      final animaisPorPasto = <int, List<AnimalPastoMapa>>{};
      for (final a in dados['animais']) {
        animaisPorPasto.putIfAbsent(a['pasto'] as int, () => []).add(
          AnimalPastoMapa(pastoId: a['pasto'], sexo: a['sexo'], nascimento: a['nascimento']),
        );
      }

      var conferidos = 0;
      for (final p in dados['pastos']) {
        final calculado = PastoMovimentacaoCalculo.kgHa(
          animaisDoPasto: animaisPorPasto[p['id']] ?? const [],
          categorias: categorias,
          pesosMedios: pesos[p['local']] ?? const {},
          area: (p['area'] as num).toDouble(),
        );
        expect(calculado, esperado[p['id']], reason: 'pasto ${p['id']} ${p['descricao']}');
        conferidos++;
      }
      expect(conferidos, greaterThan(0));
    },
    skip: tab == null || esperadoKg == null
        ? 'defina MAPA_TABULEIRO_JSON e MAPA_KGHA_JSON'
        : false,
  );
}
