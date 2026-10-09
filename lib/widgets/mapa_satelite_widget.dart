import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
///   - Toque fora do modo toque: abre a tela do pasto ([onAbrirPasto]);
///     desenho sem pasto cadastrado mostra o balão do web.
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
  final ValueChanged<PastoTabuleiro> onAbrirPasto;
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
    required this.onAbrirPasto,
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
  Offset? _dedo; // posição do dedo durante o arraste
  Timer? _timerBorda; // rola o mapa com o dedo perto da borda
  PoligonoPasto? _poligonoSobArraste;

  // Balão de informações
  PoligonoPasto? _balaoPoligono;
  LatLng? _balaoPonto;

  // Zoom atual (arredondado em 0.1) — nomes e selos acompanham o zoom.
  double _zoom = 13;

  // Largura (em graus de longitude) de cada desenho, para saber se o nome
  // cabe dentro do pasto na tela.
  final _larguraGraus = Expando<double>();

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

  /// Enquadra todos os pastos ocupando a tela (fazenda inteira visível) —
  /// os nomes e selos diminuem com o zoom (igual ao web), então não
  /// embolam. Sem pastos desenhados,
  /// centraliza na fazenda (zoom 13).
  void _enquadrarFazenda() {
    final pontos = [for (final p in widget.poligonos) ...p.pontos];
    if (pontos.isNotEmpty) {
      final alvo = CameraFit.bounds(
        bounds: LatLngBounds.fromPoints(pontos),
        padding: const EdgeInsets.all(20),
        maxZoom: 17,
      ).fit(_mapController.camera);
      // Zoom 14 é o menor aceito (igual ao web): fazenda com pasto isolado
      // longe do resto não abre afastada demais.
      final zoom = math.max(alvo.zoom, 14.0);
      // Zoom de entrada = "visão geral" da fazenda (ver _visaoGeral).
      _zoomInicial = (zoom * 10).roundToDouble() / 10;
      // Aplicado no quadro seguinte: enquadrando direto no onMapReady o
      // TileLayer não pedia as imagens (fundo ficava preto até mexer).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _mapController.move(alvo.center, zoom);
        _aoMudarZoom(zoom);
        _zoomNaBusca();
      });
      return;
    } else if (widget.centroFazenda != null) {
      _mapController.move(widget.centroFazenda!, 13);
      _zoomInicial = 13;
    }
    _aoMudarZoom(_mapController.camera.zoom);
    _zoomNaBusca();
  }

  void _aoMudarZoom(double zoom) {
    final arredondado = (zoom * 10).roundToDouble() / 10;
    if (arredondado != _zoom && mounted) setState(() => _zoom = arredondado);
  }

  /// Igual ao web (aplicar_escala_zoom): zoom 16 = tamanho original; cada
  /// nível de zoom varia 25%, limitado entre 0.45 e 1.6.
  double get _escala => (1 + (_zoom - 16) * 0.25).clamp(0.45, 1.6);

  /// Visão geral, igual ao web (modo_visao_geral): zoom afastado (abaixo de
  /// 16) ou o mesmo zoom em que o mapa abriu (fazenda pequena, que já abre
  /// aproximada). Nela não aparecem os nomes dos pastos e o selo mostra só
  /// as bolinhas das categorias, sem os números.
  bool get _visaoGeral =>
      _zoom < 16 || (_zoomInicial != null && _zoom <= _zoomInicial!);

  double? _zoomInicial;

  /// Igual ao web (atualizar_rotulos_zoom): o nome só aparece se couber em
  /// 80% da largura do pasto na tela, senão vira uma pilha de textos.
  bool _nomeCabe(PoligonoPasto p, TextStyle estilo) {
    final graus = _larguraGraus[p] ??= () {
      final lons = p.pontos.map((e) => e.longitude);
      return lons.reduce((a, b) => a > b ? a : b) -
          lons.reduce((a, b) => a < b ? a : b);
    }();
    final larguraTela = graus / 360 * 256 * math.pow(2, _zoom);
    final texto = TextPainter(
      text: TextSpan(text: p.nome, style: estilo),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return texto.width <= larguraTela * 0.8;
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
      final pasto = poligono == null
          ? null
          : widget.pastoPorNome[poligono.nome];
      // pasto sem cadastro não participa (igual ao web)
      if (pasto != null) widget.onTocarPasto(pasto);
      return;
    }

    // Pasto cadastrado: abre a tela do pasto (no web é o duplo clique;
    // aqui um toque, como no Tabuleiro). Desenho sem cadastro: balão
    // "Este pasto não existe no sistema", igual ao web.
    final pasto = poligono == null ? null : widget.pastoPorNome[poligono.nome];
    if (pasto != null) {
      setState(() => _balaoPoligono = null);
      widget.onAbrirPasto(pasto);
      return;
    }
    setState(() {
      _balaoPoligono = poligono;
      _balaoPonto = poligono == null ? null : ponto;
    });
  }

  /// Segurar o dedo em qualquer ponto de um pasto com animais começa o
  /// arraste (antes era só em cima do selo).
  void _aoSegurar(Offset posicao, LatLng ponto) {
    if (widget.modoToque) return;
    final poligono = MapaSateliteGeo.poligonoEm(widget.poligonos, ponto);
    final pasto = poligono == null ? null : widget.pastoPorNome[poligono.nome];
    if (pasto == null || pasto.total <= 0) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _origemArraste = pasto;
      _dedo = posicao;
      _balaoPoligono = null;
    });
    _timerBorda ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _rolarNaBorda(),
    );
  }

  /// Com o dedo perto da borda, o mapa anda para aquele lado — dá para
  /// soltar num pasto que não estava visível. Quanto mais perto da borda,
  /// mais rápido.
  void _rolarNaBorda() {
    final dedo = _dedo;
    final tamanho = context.size;
    if (_origemArraste == null || dedo == null || tamanho == null) return;
    const faixa = 56.0;
    const maximo = 5.0; // pixels por quadro
    double passo(double pos, double total) {
      if (pos < faixa) return -maximo * (1 - math.max(pos, 0) / faixa);
      if (pos > total - faixa) {
        return maximo * (1 - math.max(total - pos, 0) / faixa);
      }
      return 0;
    }

    final dx = passo(dedo.dx, tamanho.width);
    final dy = passo(dedo.dy, tamanho.height);
    if (dx == 0 && dy == 0) return;
    final camera = _mapController.camera;
    final centro = Offset(tamanho.width / 2 + dx, tamanho.height / 2 + dy);
    _mapController.move(camera.screenOffsetToLatLng(centro), camera.zoom);
    _atualizarDestino(dedo);
  }

  void _aoMoverDedo(PointerMoveEvent e) {
    if (_origemArraste == null) return;
    setState(() => _dedo = e.localPosition);
    _atualizarDestino(e.localPosition);
  }

  void _atualizarDestino(Offset posicao) {
    final ponto = _mapController.camera.screenOffsetToLatLng(posicao);
    final poligono = MapaSateliteGeo.poligonoEm(widget.poligonos, ponto);
    final destino = poligono == null
        ? null
        : widget.pastoPorNome[poligono.nome];
    final valido =
        destino != null && destino.pasto.id != _origemArraste!.pasto.id;
    final novo = valido ? poligono : null;
    if (novo != _poligonoSobArraste) setState(() => _poligonoSobArraste = novo);
  }

  void _pararRolagem() {
    _timerBorda?.cancel();
    _timerBorda = null;
  }

  @override
  void dispose() {
    _pararRolagem();
    super.dispose();
  }

  void _aoSoltarDedo() {
    final origem = _origemArraste;
    final alvo = _poligonoSobArraste;
    _pararRolagem();
    if (origem == null) return;
    setState(() {
      _origemArraste = null;
      _dedo = null;
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

    if (pasto != null &&
        (widget.origemToqueId == pasto.pasto.id ||
            _origemArraste?.pasto.id == pasto.pasto.id)) {
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
    // Mesma regra do CSS do web: max(7px, 10px * escala).
    final estilo = _textoBranco(math.max(7, 10 * _escala));
    final alturaNome = estilo.fontSize! * 1.3;
    const meio = 130.0; // centro do Marker = centro do pasto
    return Marker(
      point: p.centro,
      width: 260,
      height: meio * 2,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (!_visaoGeral && _nomeCabe(p, estilo))
            Positioned(
              left: 0,
              right: 0,
              top: meio - alturaNome / 2,
              child: IgnorePointer(
                child: Text(
                  p.nome,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: estilo,
                ),
              ),
            ),
          if (temAnimais)
            Positioned(
              left: 0,
              right: 0,
              // um respiro entre o nome do pasto e o selo (acompanha o zoom)
              top: meio + alturaNome / 2 + 5 * _escala,
              // Igual ao web: scale(--sat-escala) a partir do topo/centro.
              child: Transform.scale(
                scale: _escala,
                alignment: Alignment.topCenter,
                child: Center(child: _seloArrastavel(pasto)),
              ),
            ),
        ],
      ),
    );
  }

  /// O selo não tem gesto próprio: o arraste começa segurando o dedo em
  /// qualquer ponto do pasto (ver _aoSegurar).
  Widget _seloArrastavel(PastoTabuleiro pasto) {
    final selo = _Selo(pasto: pasto, visaoGeral: _visaoGeral);
    final arrastando = _origemArraste?.pasto.id == pasto.pasto.id;
    return IgnorePointer(
      child: Opacity(opacity: arrastando ? 0.35 : 1, child: selo),
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
        linhas.add(
          'Animais no pasto há ${_dias(pasto.pasto.dataComAnimais)} dia(s)',
        );
      } else {
        linhas.add(
          'Pasto vazio há ${_dias(pasto.pasto.dataSemAnimais)} dia(s)',
        );
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
              boxShadow: const [
                BoxShadow(color: Colors.black38, blurRadius: 6),
              ],
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

    final arrastado = _origemArraste;
    final dedo = _dedo;

    return Listener(
      onPointerMove: _aoMoverDedo,
      onPointerUp: (_) => _aoSoltarDedo(),
      onPointerCancel: (_) {
        _pararRolagem();
        setState(() {
          _origemArraste = null;
          _poligonoSobArraste = null;
          _dedo = null;
        });
      },
      child: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: inicio,
              initialZoom: 13,
              maxZoom: 20,
              backgroundColor: const Color(0xFF263238),
              // No "Mover por toque" o toque duplo escolhe o pasto: o zoom
              // por toque duplo do mapa atrapalharia (igual ao web).
              interactionOptions: InteractionOptions(
                flags:
                    InteractiveFlag.all &
                    ~InteractiveFlag.rotate &
                    (widget.modoToque
                        ? ~InteractiveFlag.doubleTapZoom
                        : InteractiveFlag.all),
              ),
              onMapReady: _enquadrarFazenda,
              onPositionChanged: (camera, _) => _aoMudarZoom(camera.zoom),
              onTap: (_, ponto) => _aoTocarMapa(ponto),
              onLongPress: (toque, ponto) =>
                  _aoSegurar(toque.relative ?? Offset.zero, ponto),
            ),
            children: [
              TileLayer(
                urlTemplate:
                    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                maxNativeZoom: 18,
                maxZoom: 20,
                userAgentPackageName: 'com.example.boivirtual',
                tileProvider: _tileProvider,
                errorTileCallback: (tile, erro, _) =>
                    debugPrint('[MapaSat] tile ${tile.coordinates} -> $erro'),
              ),
              PolygonLayer(
                polygons: [for (final p in widget.poligonos) _poligono(p)],
              ),
              MarkerLayer(
                markers: [for (final p in widget.poligonos) _rotulo(p)],
              ),
              if (balao != null) MarkerLayer(markers: [balao]),
              // Crédito das imagens (exigido pela Esri), discreto no canto.
              Align(
                alignment: Alignment.bottomRight,
                child: Container(
                  color: const Color(0xB3FFFFFF),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  child: const Text(
                    'Esri, Maxar, Earthstar Geographics',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 9, color: Color(0xFF333333)),
                  ),
                ),
              ),
            ],
          ),
          // Selo acompanhando o dedo durante o arraste.
          if (arrastado != null && dedo != null)
            Positioned(
              left: dedo.dx,
              top: dedo.dy,
              child: IgnorePointer(
                child: FractionalTranslation(
                  translation: const Offset(-0.5, -1.3),
                  child: Material(
                    color: Colors.transparent,
                    child: _Selo(pasto: arrastado),
                  ),
                ),
              ),
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

/// Selo do pasto no satélite — igual ao web (.satelite-pasto-badge).
///
/// Zoom aproximado: uma bolinha colorida por categoria com animal (ícone e
/// o total da categoria DENTRO da bolinha), o divisor e o total do pasto.
///
/// Visão geral ([visaoGeral], web: .satelite-zoom-baixo): só as bolinhas,
/// pequenas e lado a lado, sem os números nem o total.
class _Selo extends StatelessWidget {
  final PastoTabuleiro pasto;
  final bool visaoGeral;
  const _Selo({required this.pasto, this.visaoGeral = false});

  static const _corBezerro = Color(0xFF9C7239);
  static const _corFemea = Color(0xFFB71C1C);
  static const _corMacho = Color(0xFF212121);

  @override
  Widget build(BuildContext context) {
    final bolinhas = [
      if (pasto.bezerros > 0)
        _bolinha('mapa_bezerro.png', _corBezerro, pasto.bezerros),
      if (pasto.femeas > 0) _bolinha('mapa_vaca.png', _corFemea, pasto.femeas),
      if (pasto.machos > 0) _bolinha('mapa_gado.png', _corMacho, pasto.machos),
    ];

    if (visaoGeral) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < bolinhas.length; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            bolinhas[i],
          ],
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // As duas metades têm a MESMA largura, para a barra ficar sempre
          // no centro do selo — e o selo é centralizado no nome do pasto,
          // então bolinhas | barra | total ficam alinhados ao centro do
          // nome, com total de 1 ou de 4 dígitos.
          SizedBox(
            width: _metade,
            child: Align(
              alignment: Alignment.centerRight,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < bolinhas.length; i++) ...[
                    if (i > 0) const SizedBox(height: 2),
                    bolinhas[i],
                  ],
                ],
              ),
            ),
          ),
          const SizedBox(width: 6),
          Container(
            width: 1,
            decoration: const BoxDecoration(
              color: Color(0xBFFFFFFF),
              boxShadow: [BoxShadow(color: Colors.black, blurRadius: 1.5)],
            ),
          ),
          const SizedBox(width: 6),
          // Total do pasto: menor e sem negrito (web: 16px, peso 300).
          SizedBox(
            width: _metade,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${pasto.total}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.normal,
                  color: Colors.white,
                  shadows: [
                    Shadow(color: Colors.black, blurRadius: 1.5),
                    Shadow(color: Colors.black, blurRadius: 1.5),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Largura de cada lado da barra (cabe um total de 4 dígitos).
  static const _metade = 44.0;

  /// Bolinha da categoria: 28 com o ícone e o total dentro; na visão geral
  /// 20, só com o ícone.
  Widget _bolinha(String imagem, Color cor, int qtd) {
    final tamanho = visaoGeral ? 20.0 : 28.0;
    final icone = ColorFiltered(
      colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
      child: Image.asset('assets/images/$imagem', width: visaoGeral ? 12 : 10),
    );
    return Container(
      width: tamanho,
      height: tamanho,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: cor,
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xE6FFFFFF), width: 1.5),
        boxShadow: const [BoxShadow(color: Color(0xD9000000), blurRadius: 2)],
      ),
      child: visaoGeral
          ? icone
          : Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                icone,
                const SizedBox(height: 2.5),
                // total da categoria dentro da bolinha: menor e sem negrito
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$qtd',
                    style: const TextStyle(
                      // 8 (web: 9): com o espaço maior entre o ícone e o
                      // total, o número não encosta na borda da bolinha.
                      fontSize: 8,
                      height: 1,
                      fontWeight: FontWeight.normal,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}
