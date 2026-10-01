import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../utils/mapa_satelite_geo.dart';
import '../utils/mapa_tabuleiro_calculo.dart';

/// Mapa de Gado — visão Mapa Satélite, igual ao web
/// (js/mapa_gados_satelite.js): imagem de satélite da Esri, cada pasto
/// desenhado com a cor do seu módulo, nome no centro e o selo com
/// bezerros/fêmeas/machos e total dos pastos com animais.
///
///   - Busca: destaca em amarelo os pastos que combinam e dá zoom no
///     primeiro encontrado.
///   - Arrastar: segurar o selo do pasto (o celular vibra) e soltar em
///     cima de outro pasto -> [onMover] (mesma confirmação do Tabuleiro).
///   - Mover por toque: com [modoToque], tocar no pasto chama
///     [onTocarPasto] (a tela decide origem/destino, igual ao Tabuleiro);
///     a origem fica com a borda laranja tracejada.
///   - Toque fora do modo toque: balão com as informações do pasto.
///
/// Offline: os desenhos vêm do cache local; as imagens de satélite já
/// vistas ficam guardadas em [pastaCacheImagens] (ver build do TileLayer).
class MapaSateliteWidget extends StatefulWidget {
  final List<PoligonoPasto> poligonos;

  /// Pastos cadastrados, pelo nome em maiúsculas (é assim que o web liga
  /// o desenho ao cadastro).
  final Map<String, PastoTabuleiro> pastoPorNome;

  /// Cor de cada módulo ("#RRGGBB").
  final Map<int, String> coresModulos;

  /// Coordenada da fazenda — centro do mapa quando não há pasto desenhado.
  final LatLng? centroFazenda;

  final String termoBusca;
  final bool modoToque;
  final int? origemToqueId;
  final String pastaCacheImagens;
  final ValueChanged<PastoTabuleiro> onTocarPasto;
  final void Function(PastoTabuleiro origem, PastoTabuleiro destino) onMover;

  const MapaSateliteWidget({
    super.key,
    required this.poligonos,
    required this.pastoPorNome,
    required this.coresModulos,
    required this.centroFazenda,
    required this.termoBusca,
    required this.modoToque,
    required this.origemToqueId,
    required this.pastaCacheImagens,
    required this.onTocarPasto,
    required this.onMover,
  });

  @override
  State<MapaSateliteWidget> createState() => _MapaSateliteWidgetState();
}

class _MapaSateliteWidgetState extends State<MapaSateliteWidget> {
  static const _corSemCadastro = Color(0xFF9E9E9E);
  static const _corBusca = Color(0xFFFFEB3B);
  static const _corArraste = Color(0xFF128CB8);
  static const _corOrigemToque = Color(0xFFFF8F00);

  final _mapController = MapController();
  late final TileProvider _tileProvider = NetworkTileProvider(
    silenceExceptions: true,
    // Guarda as imagens já vistas por 1 ano numa pasta do app (a pasta de
    // cache padrão o Android pode limpar). Sem o "frescor" longo, uma
    // imagem considerada velha sem internet não aparecia.
    cachingProvider: BuiltInMapCachingProvider.getOrCreateInstance(
      cacheDirectory: widget.pastaCacheImagens,
      overrideFreshAge: const Duration(days: 365),
    ),
  );

  // Arrastar
  PastoTabuleiro? _origemArraste;
  PoligonoPasto? _poligonoSobArraste;

  // Balão de informações
  PoligonoPasto? _balaoPoligono;
  LatLng? _balaoPonto;

  @override
  void didUpdateWidget(covariant MapaSateliteWidget antigo) {
    super.didUpdateWidget(antigo);
    if (antigo.termoBusca != widget.termoBusca) _zoomNaBusca();
    if (widget.modoToque && _balaoPoligono != null) {
      _balaoPoligono = null;
      _balaoPonto = null;
    }
  }

  // ---------------------------------------------------------------------
  // Câmera
  // ---------------------------------------------------------------------

  /// Igual ao web: enquadra todos os pastos; se isso deixar o zoom muito
  /// aberto (pasto isolado longe do resto), fica no zoom 15 para continuar
  /// legível. Sem pastos desenhados, centraliza na fazenda (zoom 13).
  void _enquadrarFazenda() {
    final pontos = [for (final p in widget.poligonos) ...p.pontos];
    if (pontos.isNotEmpty) {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(pontos),
          padding: const EdgeInsets.all(20),
          maxZoom: 17,
        ),
      );
      final camera = _mapController.camera;
      if (camera.zoom < 15) _mapController.move(camera.center, 15);
    } else if (widget.centroFazenda != null) {
      _mapController.move(widget.centroFazenda!, 13);
    }
    _zoomNaBusca();
  }

  void _zoomNaBusca() {
    final termo = widget.termoBusca.toUpperCase();
    if (termo.isEmpty) return;
    for (final p in widget.poligonos) {
      if (p.nome.contains(termo)) {
        _mapController.fitCamera(
          CameraFit.bounds(
            bounds: LatLngBounds.fromPoints(p.pontos),
            maxZoom: 17,
          ),
        );
        return;
      }
    }
  }

  // ---------------------------------------------------------------------
  // Toques e arraste
  // ---------------------------------------------------------------------

  void _aoTocarMapa(LatLng ponto) {
    final poligono = MapaSateliteGeo.poligonoEm(widget.poligonos, ponto);

    if (widget.modoToque) {
      final pasto = poligono == null ? null : widget.pastoPorNome[poligono.nome];
      // pasto sem cadastro não participa (igual ao web)
      if (pasto != null) widget.onTocarPasto(pasto);
      return;
    }

    setState(() {
      _balaoPoligono = poligono;
      _balaoPonto = poligono == null ? null : ponto;
    });
  }

  void _aoMoverDedo(PointerMoveEvent e) {
    if (_origemArraste == null) return;
    final ponto = _mapController.camera.screenOffsetToLatLng(e.localPosition);
    final poligono = MapaSateliteGeo.poligonoEm(widget.poligonos, ponto);
    final destino = poligono == null ? null : widget.pastoPorNome[poligono.nome];
    final valido = destino != null && destino.pasto.id != _origemArraste!.pasto.id;
    final novo = valido ? poligono : null;
    if (novo != _poligonoSobArraste) setState(() => _poligonoSobArraste = novo);
  }

  void _aoSoltarDedo() {
    final origem = _origemArraste;
    final alvo = _poligonoSobArraste;
    if (origem == null) return;
    setState(() {
      _origemArraste = null;
      _poligonoSobArraste = null;
    });
    final destino = alvo == null ? null : widget.pastoPorNome[alvo.nome];
    if (destino != null && destino.pasto.id != origem.pasto.id) {
      widget.onMover(origem, destino);
    }
  }

  // ---------------------------------------------------------------------
  // Desenho
  // ---------------------------------------------------------------------

  Color _corModulo(PoligonoPasto p) {
    final pasto = widget.pastoPorNome[p.nome];
    if (pasto == null) return _corSemCadastro;
    final hex = widget.coresModulos[pasto.pasto.modulo];
    if (hex == null || !RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(hex)) {
      return _corSemCadastro;
    }
    return Color(int.parse('FF${hex.substring(1)}', radix: 16));
  }

  Polygon _poligono(PoligonoPasto p) {
    final pasto = widget.pastoPorNome[p.nome];
    final termo = widget.termoBusca.toUpperCase();

    var borda = Colors.white;
    double largura = 1;
    var tracejado = false;

    if (pasto != null && widget.origemToqueId == pasto.pasto.id) {
      borda = _corOrigemToque;
      largura = 4;
      tracejado = true;
    } else if (identical(p, _poligonoSobArraste)) {
      borda = _corArraste;
      largura = 4;
    } else if (termo.isNotEmpty && p.nome.contains(termo)) {
      borda = _corBusca;
      largura = 3;
    }

    return Polygon(
      points: p.pontos,
      color: _corModulo(p).withValues(alpha: 0.5),
      borderColor: borda,
      borderStrokeWidth: largura,
      pattern: tracejado
          ? StrokePattern.dashed(segments: const [8, 6])
          : const StrokePattern.solid(),
    );
  }

  Marker _rotulo(PoligonoPasto p) {
    final pasto = widget.pastoPorNome[p.nome];
    final temAnimais = pasto != null && pasto.total > 0;
    return Marker(
      point: p.centro,
      width: 180,
      height: 140,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0,
            right: 0,
            top: 62,
            child: IgnorePointer(
              child: Text(
                p.nome,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.visible,
                softWrap: false,
                style: _textoBranco(10),
              ),
            ),
          ),
          if (temAnimais)
            Positioned(
              left: 0,
              right: 0,
              top: 78,
              child: Center(child: _seloArrastavel(pasto)),
            ),
        ],
      ),
    );
  }

  Widget _seloArrastavel(PastoTabuleiro pasto) {
    final selo = _Selo(pasto: pasto);
    // No modo toque o selo não arrasta (igual ao Tabuleiro).
    if (widget.modoToque) return IgnorePointer(child: selo);
    return LongPressDraggable<PastoTabuleiro>(
      data: pasto,
      hapticFeedbackOnStart: true,
      onDragStarted: () => setState(() {
        _origemArraste = pasto;
        _balaoPoligono = null;
      }),
      feedback: Material(color: Colors.transparent, child: selo),
      childWhenDragging: Opacity(opacity: 0.35, child: selo),
      child: selo,
    );
  }

  Marker? _balao() {
    final p = _balaoPoligono;
    final ponto = _balaoPonto;
    if (p == null || ponto == null) return null;
    final pasto = widget.pastoPorNome[p.nome];

    final linhas = <String>[p.nome];
    if (pasto == null) {
      linhas.add('Este pasto não existe no sistema');
    } else {
      if (pasto.total != 0) {
        linhas.add('${pasto.total} animais');
        linhas.add('Animais no pasto há ${_dias(pasto.pasto.dataComAnimais)} dia(s)');
      } else {
        linhas.add('Pasto vazio há ${_dias(pasto.pasto.dataSemAnimais)} dia(s)');
      }
      if (pasto.pasto.capim.isNotEmpty) linhas.add(pasto.pasto.capim);
    }

    return Marker(
      point: ponto,
      width: 240,
      height: 130,
      alignment: Alignment.topCenter,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: GestureDetector(
          onTap: () => setState(() => _balaoPoligono = null),
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 6)],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < linhas.length; i++)
                  Text(
                    linhas[i],
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      color: const Color(0xFF333333),
                      fontWeight: i == 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static int _dias(String? data) {
    final d = data == null ? null : DateTime.tryParse(data);
    if (d == null) return 0;
    return DateTime.now().difference(d).inDays.abs();
  }

  @override
  Widget build(BuildContext context) {
    final balao = _balao();
    final inicio = widget.poligonos.isNotEmpty
        ? widget.poligonos.first.centro
        : (widget.centroFazenda ?? const LatLng(-15.8, -47.9));

    return Listener(
      onPointerMove: _aoMoverDedo,
      onPointerUp: (_) => _aoSoltarDedo(),
      onPointerCancel: (_) => setState(() {
        _origemArraste = null;
        _poligonoSobArraste = null;
      }),
      child: FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: inicio,
          initialZoom: 13,
          maxZoom: 20,
          backgroundColor: const Color(0xFF263238),
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: _enquadrarFazenda,
          onTap: (_, ponto) => _aoTocarMapa(ponto),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
            maxNativeZoom: 18,
            maxZoom: 20,
            userAgentPackageName: 'com.example.boivirtual',
            tileProvider: _tileProvider,
          ),
          PolygonLayer(polygons: [for (final p in widget.poligonos) _poligono(p)]),
          MarkerLayer(markers: [for (final p in widget.poligonos) _rotulo(p)]),
          if (balao != null) MarkerLayer(markers: [balao]),
          const SimpleAttributionWidget(
            source: Text('Imagens © Esri, Maxar, Earthstar Geographics'),
          ),
        ],
      ),
    );
  }
}

TextStyle _textoBranco(double tamanho) => TextStyle(
  fontSize: tamanho,
  fontWeight: FontWeight.bold,
  color: Colors.white,
  shadows: const [
    Shadow(color: Colors.black, blurRadius: 1.5),
    Shadow(color: Colors.black, blurRadius: 1.5),
  ],
);

/// Selo do pasto no satélite — igual ao web (.satelite-pasto-badge): uma
/// linha por categoria com animal (ícone num círculo colorido + qtde),
/// divisor e o total.
class _Selo extends StatelessWidget {
  final PastoTabuleiro pasto;
  const _Selo({required this.pasto});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (pasto.bezerros > 0)
                _linha('mapa_bezerro.png', const Color(0xFF9C7239), pasto.bezerros),
              if (pasto.femeas > 0)
                _linha('mapa_vaca.png', const Color(0xFFB71C1C), pasto.femeas),
              if (pasto.machos > 0)
                _linha('mapa_gado.png', const Color(0xFF212121), pasto.machos),
            ],
          ),
          const SizedBox(width: 6),
          Container(
            width: 2,
            decoration: const BoxDecoration(
              color: Color(0xBFFFFFFF),
              boxShadow: [BoxShadow(color: Colors.black, blurRadius: 1.5)],
            ),
          ),
          const SizedBox(width: 6),
          Center(child: Text('${pasto.total}', style: _textoBranco(22))),
        ],
      ),
    );
  }

  Widget _linha(String imagem, Color cor, int qtd) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 20,
            height: 20,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: cor,
              shape: BoxShape.circle,
              border: Border.all(color: const Color(0xE6FFFFFF), width: 1.5),
              boxShadow: const [BoxShadow(color: Color(0xD9000000), blurRadius: 2)],
            ),
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: Image.asset('assets/images/$imagem', width: 12),
            ),
          ),
          const SizedBox(width: 4),
          Text('$qtd', style: _textoBranco(13)),
        ],
      ),
    );
  }
}
