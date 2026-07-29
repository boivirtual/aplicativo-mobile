import 'dart:async';
import 'package:flutter/material.dart';
import '../services/connectivity_service.dart';

/// Indicador discreto de conectividade para a AppBar: um ícone pequeno à
/// direita do título, em vez de uma tarja ocupando a largura toda da tela.
/// Fica invisível quando a internet está OK; ao tocar, mostra a mensagem
/// completa num snackbar (a informação não se perde, só não fica fixa na
/// tela o tempo todo).
class IndicadorConectividadeWidget extends StatefulWidget {
  const IndicadorConectividadeWidget({super.key});

  @override
  State<IndicadorConectividadeWidget> createState() =>
      _IndicadorConectividadeWidgetState();
}

class _IndicadorConectividadeWidgetState
    extends State<IndicadorConectividadeWidget> {
  StreamSubscription<NivelConexao>? _sub;
  NivelConexao _nivel = NivelConexao.internetOk;

  @override
  void initState() {
    super.initState();
    _sub = ConnectivityService.instance.status.listen((nivel) {
      if (mounted) setState(() => _nivel = nivel);
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_nivel == NivelConexao.internetOk) return const SizedBox.shrink();

    final semInternet = _nivel == NivelConexao.semInternet;
    final cor = semInternet ? Colors.redAccent : Colors.orange[600]!;
    final mensagem = semInternet
        ? "Sem conexão com a Internet"
        : "Conexão com a Internet ruim";

    return IconButton(
      tooltip: mensagem,
      icon: Icon(
        semInternet ? Icons.cloud_off : Icons.cloud_queue,
        color: cor,
        size: 20,
      ),
      onPressed: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mensagem), backgroundColor: cor),
        );
      },
    );
  }
}
