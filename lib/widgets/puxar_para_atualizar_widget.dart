import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/connectivity_service.dart';

/// "Puxar para atualizar" a partir de um elemento fixo da tela (a tarja azul
/// do Mapa de Gado e da tela de itens da Pesagem, o botão "Nova Pesagem"):
/// arrastar o dedo para baixo a partir de [child] e soltar depois de
/// [distancia] chama [onAtualizar]. Enquanto puxa, aparece logo abaixo o
/// ícone girando com "Puxe para atualizar" / "Solte para atualizar".
///
/// Só atualiza com internet: sem ela, avisa e não chama [onAtualizar].
class PuxarParaAtualizarWidget extends StatefulWidget {
  final Widget child;
  final Future<void> Function() onAtualizar;

  /// false = o gesto fica desligado (ex.: no meio de uma edição).
  final bool habilitado;

  /// Mostra "Atualizando..." enquanto [onAtualizar] roda (o Mapa de Gado
  /// já tem o próprio "Aguarde").
  final bool mostrarAtualizando;

  /// Cor de fundo da faixa que aparece abaixo de [child].
  final Color corFundo;

  static const distancia = 80.0;

  const PuxarParaAtualizarWidget({
    super.key,
    required this.child,
    required this.onAtualizar,
    this.habilitado = true,
    this.mostrarAtualizando = true,
    this.corFundo = Colors.transparent,
  });

  @override
  State<PuxarParaAtualizarWidget> createState() =>
      _PuxarParaAtualizarWidgetState();
}

class _PuxarParaAtualizarWidgetState extends State<PuxarParaAtualizarWidget> {
  static const _azul = Color(0xFF18385F);

  double _puxao = 0;
  bool _atualizando = false;

  bool get _ativo => widget.habilitado && !_atualizando;

  Future<void> _soltou() async {
    final atualizar = _puxao >= PuxarParaAtualizarWidget.distancia;
    setState(() => _puxao = 0);
    if (!atualizar) return;

    final nivel = await ConnectivityService.instance.verificarAgora();
    if (!mounted) return;
    if (nivel != NivelConexao.internetOk) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Sem internet (ou internet ruim): não foi possível atualizar.',
          ),
        ),
      );
      return;
    }
    setState(() => _atualizando = true);
    try {
      await widget.onAtualizar();
    } finally {
      if (mounted) setState(() => _atualizando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final pronto = _puxao >= PuxarParaAtualizarWidget.distancia;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragUpdate: _ativo
          ? (d) => setState(
              () => _puxao = (_puxao + d.delta.dy).clamp(0, 140).toDouble(),
            )
          : null,
      onVerticalDragEnd: _ativo ? (_) => _soltou() : null,
      onVerticalDragCancel: _ativo ? () => setState(() => _puxao = 0) : null,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          widget.child,
          if (_puxao > 0)
            _faixa(
              altura: (_puxao * 0.6).clamp(0, 48).toDouble(),
              icone: Transform.rotate(
                angle: _puxao / PuxarParaAtualizarWidget.distancia * math.pi,
                child: Icon(
                  Icons.refresh,
                  size: 20,
                  color: pronto ? _azul : Colors.grey,
                ),
              ),
              texto: pronto ? 'Solte para atualizar' : 'Puxe para atualizar',
              cor: pronto ? _azul : Colors.grey[600]!,
            )
          else if (_atualizando && widget.mostrarAtualizando)
            _faixa(
              altura: 36,
              icone: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _azul,
                ),
              ),
              texto: 'Atualizando...',
              cor: _azul,
            ),
        ],
      ),
    );
  }

  Widget _faixa({
    required double altura,
    required Widget icone,
    required String texto,
    required Color cor,
  }) => Container(
    height: altura,
    color: widget.corFundo,
    alignment: Alignment.center,
    child: FittedBox(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icone,
          const SizedBox(width: 6),
          Text(texto, style: TextStyle(fontSize: 13, color: cor)),
        ],
      ),
    ),
  );
}
