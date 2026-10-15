import 'dart:convert';
import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

/// Um pasto desenhado no mapa (feature Polygon do GeoJSON do web).
class PoligonoPasto {
  /// Nome em maiúsculas — é por ele que o web liga o desenho ao pasto
  /// cadastrado (tbl_pasto_descricao).
  final String nome;
  final List<LatLng> pontos;
  final LatLng centro;

  /// Ponto DENTRO do pasto mais afastado das bordas (o "centro visual",
  /// ver [MapaSateliteGeo.pontoInterno]): é onde ficam o nome e o selo.
  final LatLng ponto;

  /// Raio do maior círculo que cabe no pasto em volta de [ponto], em graus
  /// de latitude (0 = polígono degenerado).
  final double raio;

  PoligonoPasto({
    required this.nome,
    required this.pontos,
    required this.centro,
    LatLng? ponto,
    this.raio = 0,
  }) : ponto = ponto ?? centro;
}

/// Geometria do Mapa Satélite, replicada de js/mapa_gados_satelite.js
/// (sistema web) — funções puras para poderem ser testadas.
class MapaSateliteGeo {
  MapaSateliteGeo._();

  /// Polígonos do GeoJSON. Igual ao web: só features "Polygon", anel
  /// externo, sem o último ponto (que repete o primeiro).
  static List<PoligonoPasto> lerGeojson(String? geojson) {
    if (geojson == null || geojson.isEmpty) return const [];
    final dynamic dados;
    try {
      dados = json.decode(geojson);
    } catch (_) {
      return const [];
    }
    final features = (dados is Map ? dados['features'] : null) as List?;
    if (features == null) return const [];

    final poligonos = <PoligonoPasto>[];
    for (final f in features) {
      if (f is! Map) continue;
      final geometria = f['geometry'];
      if (geometria is! Map || geometria['type'] != 'Polygon') continue;
      final aneis = geometria['coordinates'] as List?;
      if (aneis == null || aneis.isEmpty) continue;
      final anel = (aneis.first as List)
          .whereType<List>()
          .where((p) => p.length >= 2)
          .map((p) => [(p[0] as num).toDouble(), (p[1] as num).toDouble()])
          .toList();
      if (anel.length < 4) continue;

      final nome = (((f['properties'] as Map?)?['name']) ?? '')
          .toString()
          .toUpperCase();
      final interno = pontoInterno(anel);
      poligonos.add(
        PoligonoPasto(
          nome: nome,
          pontos: anel
              .sublist(0, anel.length - 1)
              .map((p) => LatLng(p[1], p[0]))
              .toList(),
          centro: centroide(anel),
          ponto: interno.$1,
          raio: interno.$2,
        ),
      );
    }
    return poligonos;
  }

  /// Ponto DENTRO do pasto o mais afastado possível das bordas (o "centro
  /// visual") e a distância dele até a borda mais próxima (raio do maior
  /// círculo inscrito, em graus de latitude) — mesma conta de
  /// mapa_gado_satelite_ponto_interno() do web (busca em grade com
  /// refinamento, ideia do polylabel). O centroide comum cai fora de pastos
  /// em "L" ou "U". anel: [lng, lat] com o último ponto repetindo o
  /// primeiro.
  static (LatLng, double) pontoInterno(List<List<double>> anel) {
    final qtd = anel.length - 1;
    double lat0 = 0;
    for (var i = 0; i < qtd; i++) {
      lat0 += anel[i][1];
    }
    lat0 = lat0 / qtd;

    // plano local: x em "graus de longitude" corrigidos pela latitude
    final k = math.cos(lat0 * math.pi / 180);
    final pts = <List<double>>[];
    var minX = double.infinity, maxX = -double.infinity;
    var minY = double.infinity, maxY = -double.infinity;
    for (var j = 0; j < qtd; j++) {
      final x = anel[j][0] * k, y = anel[j][1];
      pts.add([x, y]);
      minX = math.min(minX, x);
      maxX = math.max(maxX, x);
      minY = math.min(minY, y);
      maxY = math.max(maxY, y);
    }

    bool dentro(double px, double py) {
      var d = false;
      for (var a = 0, b = qtd - 1; a < qtd; b = a++) {
        if (((pts[a][1] > py) != (pts[b][1] > py)) &&
            (px <
                (pts[b][0] - pts[a][0]) * (py - pts[a][1]) /
                        (pts[b][1] - pts[a][1]) +
                    pts[a][0])) {
          d = !d;
        }
      }
      return d;
    }

    double distanciaBorda(double px, double py) {
      var menor = double.infinity;
      for (var a = 0, b = qtd - 1; a < qtd; b = a++) {
        final ax = pts[a][0], ay = pts[a][1], bx = pts[b][0], by = pts[b][1];
        final dx = bx - ax, dy = by - ay;
        final t = (dx == 0 && dy == 0)
            ? 0.0
            : (((px - ax) * dx + (py - ay) * dy) / (dx * dx + dy * dy))
                  .clamp(0.0, 1.0);
        final ex = px - (ax + t * dx), ey = py - (ay + t * dy);
        menor = math.min(menor, math.sqrt(ex * ex + ey * ey));
      }
      return menor;
    }

    List<double>? melhor; // [x, y, dist]
    var passo = math.max(maxX - minX, maxY - minY) / 12;
    var x0 = minX, x1 = maxX, y0 = minY, y1 = maxY;
    for (var volta = 0; volta < 4 && passo > 0; volta++) {
      for (var gx = x0; gx <= x1; gx += passo) {
        for (var gy = y0; gy <= y1; gy += passo) {
          if (dentro(gx, gy)) {
            final dist = distanciaBorda(gx, gy);
            if (melhor == null || dist > melhor[2]) melhor = [gx, gy, dist];
          }
        }
      }
      if (melhor == null) break;
      // refina em volta do melhor ponto encontrado
      x0 = melhor[0] - passo;
      x1 = melhor[0] + passo;
      y0 = melhor[1] - passo;
      y1 = melhor[1] + passo;
      passo = passo / 4;
    }

    if (melhor == null) return (centroide(anel), 0);
    return (LatLng(melhor[1], melhor[0] / k), melhor[2]);
  }

  /// Centro geométrico (fórmula do "shoelace") — mesma conta do web.
  /// anel: [lng, lat] com o último ponto repetindo o primeiro.
  static LatLng centroide(List<List<double>> anel) {
    double area = 0, cx = 0, cy = 0;
    for (var i = 0; i < anel.length - 1; i++) {
      final cruz = anel[i][0] * anel[i + 1][1] - anel[i + 1][0] * anel[i][1];
      area += cruz;
      cx += (anel[i][0] + anel[i + 1][0]) * cruz;
      cy += (anel[i][1] + anel[i + 1][1]) * cruz;
    }
    area = area / 2;

    if (area.abs() < 1e-12) {
      // polígono degenerado: média simples dos pontos
      double somaLat = 0, somaLng = 0;
      final qtd = anel.length - 1;
      for (var j = 0; j < qtd; j++) {
        somaLng += anel[j][0];
        somaLat += anel[j][1];
      }
      return LatLng(somaLat / qtd, somaLng / qtd);
    }
    return LatLng(cy / (6 * area), cx / (6 * area));
  }

  /// Ponto dentro do polígono (ray casting).
  static bool contem(List<LatLng> pontos, LatLng p) {
    var dentro = false;
    for (var i = 0, j = pontos.length - 1; i < pontos.length; j = i++) {
      final a = pontos[i], b = pontos[j];
      final cruza = (a.latitude > p.latitude) != (b.latitude > p.latitude) &&
          p.longitude <
              (b.longitude - a.longitude) *
                      (p.latitude - a.latitude) /
                      (b.latitude - a.latitude) +
                  a.longitude;
      if (cruza) dentro = !dentro;
    }
    return dentro;
  }

  /// Polígono sob o ponto (o último desenhado ganha, como no mapa).
  static PoligonoPasto? poligonoEm(List<PoligonoPasto> poligonos, LatLng p) {
    for (final poligono in poligonos.reversed) {
      if (contem(poligono.pontos, p)) return poligono;
    }
    return null;
  }
}
