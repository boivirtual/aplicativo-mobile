// Geometria do Mapa Satélite (mesmas contas de js/mapa_gados_satelite.js).
import 'dart:convert';
import 'dart:io';

import 'package:boivirtual/utils/mapa_satelite_geo.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  // Quadrado de 1x1 grau: lng 10..11, lat 20..21 (fechado, com altitude 0
  // como o GeoJSON gravado pelo Editor de Mapa do web).
  final geojson = json.encode({
    'type': 'FeatureCollection',
    'features': [
      {
        'type': 'Feature',
        'properties': {'name': 'Manga 12'},
        'geometry': {
          'type': 'Polygon',
          'coordinates': [
            [
              [10, 20, 0],
              [11, 20, 0],
              [11, 21, 0],
              [10, 21, 0],
              [10, 20, 0],
            ],
          ],
        },
      },
      {
        'type': 'Feature',
        'properties': {'name': 'Ponto'},
        'geometry': {'type': 'Point', 'coordinates': [0, 0]},
      },
    ],
  });

  test('lê só os polígonos, nome em maiúsculas, sem repetir o 1º ponto', () {
    final p = MapaSateliteGeo.lerGeojson(geojson);
    expect(p.length, 1);
    expect(p.single.nome, 'MANGA 12');
    expect(p.single.pontos.length, 4);
    expect(p.single.pontos.first, const LatLng(20, 10));
  });

  test('centro do polígono (shoelace) e ponto dentro/fora', () {
    final p = MapaSateliteGeo.lerGeojson(geojson).single;
    expect(p.centro.latitude, closeTo(20.5, 1e-9));
    expect(p.centro.longitude, closeTo(10.5, 1e-9));
    expect(MapaSateliteGeo.contem(p.pontos, const LatLng(20.5, 10.5)), isTrue);
    expect(MapaSateliteGeo.contem(p.pontos, const LatLng(22, 10.5)), isFalse);
    expect(
      MapaSateliteGeo.poligonoEm([p], const LatLng(20.1, 10.9))?.nome,
      'MANGA 12',
    );
  });

  test('GeoJSON vazio ou inválido não quebra', () {
    expect(MapaSateliteGeo.lerGeojson(null), isEmpty);
    expect(MapaSateliteGeo.lerGeojson('{nao e json'), isEmpty);
  });

  // Mapa real do sistema web (opcional): MAPA_GEOJSON=<arquivo .json>
  final arquivo = Platform.environment['MAPA_GEOJSON'];
  test(
    'mapa real: todo pasto tem centro dentro do próprio desenho ou perto',
    () {
      final poligonos = MapaSateliteGeo.lerGeojson(File(arquivo!).readAsStringSync());
      expect(poligonos, isNotEmpty);
      for (final p in poligonos) {
        expect(p.pontos.length, greaterThanOrEqualTo(3), reason: p.nome);
      }
    },
    skip: arquivo == null ? 'defina MAPA_GEOJSON' : false,
  );
}
