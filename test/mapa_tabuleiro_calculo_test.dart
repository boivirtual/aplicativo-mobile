import 'dart:convert';
import 'dart:io';

import 'package:boivirtual/utils/mapa_tabuleiro_calculo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _categorias = {
  1: CategoriaIdadeMapa(id: 1, idadeDe: 0, idadeAte: 7),
  2: CategoriaIdadeMapa(id: 2, idadeDe: 8, idadeAte: 12),
  3: CategoriaIdadeMapa(id: 3, idadeDe: 13, idadeAte: 24),
  4: CategoriaIdadeMapa(id: 4, idadeDe: 25, idadeAte: 36),
  5: CategoriaIdadeMapa(id: 5, idadeDe: 37, idadeAte: 999999999),
};

PastoMapa _pasto(int id, int modulo, int ordem, {String cats = '001!002!003!004!005'}) =>
    PastoMapa(
      id: id,
      fazendaId: 56,
      descricao: 'P$id',
      modulo: modulo,
      capim: '',
      categorias: cats,
      ordem: ordem,
    );

void main() {
  final hoje = DateTime(2026, 10, 1);

  group('idadeEmMeses (igual ao DateTime::diff do PHP)', () {
    test('meses completos, descontando o dia', () {
      expect(MapaTabuleiroCalculo.idadeEmMeses('2026-04-01', hoje), 6);
      expect(MapaTabuleiroCalculo.idadeEmMeses('2026-04-02', hoje), 5);
      expect(MapaTabuleiroCalculo.idadeEmMeses('2024-10-01', hoje), 24);
    });
    test('vazio = 0; inválido = idade enorme', () {
      expect(MapaTabuleiroCalculo.idadeEmMeses(null, hoje), 0);
      expect(MapaTabuleiroCalculo.idadeEmMeses('0000-00-00', hoje) > 37, isTrue);
    });
  });

  test('primeira categoria do pasto = bezerros; resto por sexo', () {
    final cards = MapaTabuleiroCalculo.calcular(
      pastos: [_pasto(1, 1, 1)],
      animais: const [
        AnimalPastoMapa(pastoId: 1, sexo: 'M', nascimento: '2026-06-01'),
        AnimalPastoMapa(pastoId: 1, sexo: 'F', nascimento: '2026-06-01'),
        AnimalPastoMapa(pastoId: 1, sexo: 'F', nascimento: '2020-01-01'),
        AnimalPastoMapa(pastoId: 1, sexo: 'M', nascimento: '2025-01-01'),
      ],
      categorias: _categorias,
      hoje: hoje,
    );
    expect(cards.single.bezerros, 2);
    expect(cards.single.femeas, 1);
    expect(cards.single.machos, 1);
    expect(cards.single.total, 4);
  });

  test('cores: 999 branco; troca a cada módulo novo e repete após 8', () {
    final pastos = [
      _pasto(46, 999, 1),
      _pasto(1, 1, 2),
      _pasto(2, 1, 3),
      for (var m = 2; m <= 9; m++) _pasto(m + 10, m, m + 2),
    ];
    final cards = MapaTabuleiroCalculo.calcular(
      pastos: pastos,
      animais: const [],
      categorias: _categorias,
      hoje: hoje,
    );
    const cores = MapaTabuleiroCalculo.cores;
    expect(cards[0].cor, Colors.white);
    expect(cards[1].cor, cores[0]);
    expect(cards[2].cor, cores[0]);
    expect(cards[3].cor, cores[1]); // módulo 2
    expect(cards.last.cor, cores[0]); // módulo 9 = nona cor -> volta à 1ª
  });

  // Comparação com dados reais: rode com
  //   MAPA_TABULEIRO_JSON=<saída do tabuleiro.php>
  //   MAPA_ESPERADO_JSON=<mesma lógica do ler_mapa_gados.php>
  // (arquivos fora do repositório — têm dados de clientes).
  final caminhoTabuleiro = Platform.environment['MAPA_TABULEIRO_JSON'];
  final caminhoEsperado = Platform.environment['MAPA_ESPERADO_JSON'];
  test(
    'bate com o sistema web em dados reais',
    () {
      final tab = json.decode(File(caminhoTabuleiro!).readAsStringSync());
      final esperado = (json.decode(File(caminhoEsperado!).readAsStringSync()) as List)
          .cast<Map<String, dynamic>>();

      final categorias = {
        for (final c in tab['categorias'])
          c['id'] as int: CategoriaIdadeMapa(
            id: c['id'],
            idadeDe: c['de'],
            idadeAte: c['ate'],
          ),
      };
      final pastos = [
        for (final p in tab['pastos'])
          PastoMapa(
            id: p['id'],
            fazendaId: p['local'],
            descricao: p['descricao'],
            modulo: p['modulo'],
            capim: p['capim'],
            categorias: p['categorias'],
            ordem: p['ordem'],
          ),
      ];
      final animais = [
        for (final a in tab['animais'])
          AnimalPastoMapa(
            pastoId: a['pasto'],
            sexo: a['sexo'],
            nascimento: a['nascimento'],
          ),
      ];

      final porFazenda = <int, List<PastoTabuleiro>>{};
      for (final f in pastos.map((p) => p.fazendaId).toSet()) {
        porFazenda[f] = MapaTabuleiroCalculo.calcular(
          pastos: pastos.where((p) => p.fazendaId == f).toList(),
          animais: animais,
          categorias: categorias,
        );
      }
      final calculados = [for (final l in porFazenda.values) ...l];

      final esperadoPastos = esperado.where((e) => e.containsKey('id')).toList();
      expect(calculados.length, esperadoPastos.length);
      for (var i = 0; i < esperadoPastos.length; i++) {
        final e = esperadoPastos[i];
        final c = calculados[i];
        final corHex =
            '#${(c.cor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
        expect(
          [c.pasto.id, c.bezerros, c.femeas, c.machos, c.total, corHex],
          [e['id'], e['bezerros'], e['femeas'], e['machos'], e['total'], e['cor']],
          reason: 'pasto ${e['id']} (posição $i)',
        );
      }
      for (final e in esperado.where((e) => e.containsKey('fazenda'))) {
        final total = porFazenda[e['fazenda']]!.fold<int>(0, (s, c) => s + c.total);
        expect(total, e['total_fazenda'], reason: 'fazenda ${e['fazenda']}');
      }
    },
    skip: caminhoTabuleiro == null || caminhoEsperado == null
        ? 'defina MAPA_TABULEIRO_JSON e MAPA_ESPERADO_JSON'
        : false,
  );
}
