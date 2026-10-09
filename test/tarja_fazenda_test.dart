// A tarja azul do Mapa de Gado (ícone do mapa + nome da fazenda + total de
// animais + ícone de trocar de fazenda) tem que caber em UMA linha, sem
// estourar, também com total de 4 e 5 dígitos e nome de fazenda comprido.
//
// Para ver o resultado: TARJA_PNG=<pasta> flutter test test/tarja_fazenda_test.dart
// grava um PNG por caso, com a fonte de verdade do aplicativo.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:boivirtual/widgets/tarja_fazenda_widget.dart';

void main() {
  setUpAll(() async {
    final fonte = FontLoader('FuturaStd')
      ..addFont(rootBundle.load('assets/fonts/FuturaStd-Light.otf'));
    await fonte.load();
  });

  const casos = {
    'casa_blanca_534': ['FAZENDA CASA BLANCA', '534'],
    'casa_blanca_1234': ['FAZENDA CASA BLANCA', '1234'],
    'casa_blanca_12345': ['FAZENDA CASA BLANCA', '12345'],
    'santa_helena_12345': ['FAZENDA SANTA HELENA', '12345'],
    'nome_comprido_12345': ['FAZENDA NOSSA SENHORA APARECIDA', '12345'],
  };

  for (final caso in casos.entries) {
    testWidgets('tarja em uma linha: ${caso.key}', (tester) async {
      // Largura da tela do aparelho de teste (1440 px / 3,75).
      tester.view.physicalSize = const Size(384 * 3, 120 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final chave = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(fontFamily: 'FuturaStd'),
          home: Scaffold(
            body: RepaintBoundary(
              key: chave,
              child: TarjaFazendaWidget(
                nomeFazenda: caso.value[0],
                temOutras: true,
                onTrocar: () {},
                prefixo: InkWell(
                  onTap: () {},
                  child: const Padding(
                    padding: EdgeInsets.fromLTRB(8, 7, 6, 7),
                    child: Icon(
                      Icons.map_outlined,
                      color: Colors.blue,
                      size: 22,
                    ),
                  ),
                ),
                complemento: [
                  const TextSpan(text: '  ➔  '),
                  TextSpan(
                    text: '${caso.value[1]} Animais',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // Nada estourou e o texto ficou em uma linha só, dentro da tarja,
      // sem passar por cima do ícone de trocar de fazenda.
      expect(tester.takeException(), isNull);
      final texto = tester.getRect(find.byType(RichText).first);
      final editar = tester.getRect(find.byIcon(Icons.edit_note));
      expect(texto.height, lessThan(24));
      expect(texto.right, lessThanOrEqualTo(editar.left + 12));

      final pasta = Platform.environment['TARJA_PNG'];
      if (pasta != null) {
        await tester.runAsync(() async {
          final limite =
              chave.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final imagem = await limite.toImage(pixelRatio: 3);
          final bytes = await imagem.toByteData(format: ui.ImageByteFormat.png);
          File('$pasta/tarja_${caso.key}.png')
              .writeAsBytesSync(bytes!.buffer.asUint8List());
        });
      }
    });
  }
}
