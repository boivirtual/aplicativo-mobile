import 'dart:async';
import 'package:flutter/material.dart';

class AppAlert {
  static Future<void> erro(BuildContext context, String mensagem) {
    FocusManager.instance.primaryFocus?.unfocus();

    final completer = Completer<void>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Text('Atenção', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(mensagem, style: const TextStyle(fontSize: 14)),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }

  static Future<void> sucesso(BuildContext context, String mensagem) {
    FocusManager.instance.primaryFocus?.unfocus();

    final completer = Completer<void>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Row(
              children: [
                Icon(Icons.check_circle_outline, color: Colors.green),
                SizedBox(width: 8),
                Text('Sucesso', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text(
                  'OK',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }

  static Future<void> confirmacao(
    BuildContext context, {
    required String mensagem,
    required VoidCallback onConfirmar,
  }) {
    FocusManager.instance.primaryFocus?.unfocus();

    final completer = Completer<void>();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!context.mounted) {
        if (!completer.isCompleted) completer.complete();
        return;
      }

      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            title: const Text(
              'Confirmação',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            content: Text(mensagem),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancelar'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  onConfirmar();
                },
                child: const Text(
                  'Confirmar',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF007AFF),
                  ),
                ),
              ),
            ],
          );
        },
      );

      if (!completer.isCompleted) completer.complete();
    });

    return completer.future;
  }
}
