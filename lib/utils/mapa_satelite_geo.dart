import 'dart:convert';

import 'package:latlong2/latlong.dart';

/// Um pasto desenhado no mapa (feature Polygon do GeoJSON do web).
class PoligonoPasto {
  /// Nome em maiúsculas — é por ele que o web liga o desenho ao pasto
  /// cadastrado (tbl_pasto_descricao).
  final String nome;
  final List<LatLng> pontos;
  final LatLng centro;

  const PoligonoPasto({
    required this.nome,
    required this.pontos,
    required this.centro,
  });
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
      poligonos.add(
        PoligonoPasto(
          nome: nome,
          pontos: anel
              .sublist(0, anel.length - 1)
              .map((p) => LatLng(p[1], p[0]))
              .toList(),
          centro: centroide(anel),
        ),
      );
    }
    return poligonos;
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
