import 'package:flutter/material.dart';

class InputMinimalPesagemWidget extends StatelessWidget {
  final String label;
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final int maxLines;
  final double containerHeight;
  final Color corDoRotulo;

  const InputMinimalPesagemWidget({
    super.key,
    required this.label,
    required this.corDoRotulo,
    this.controller,
    this.focusNode,
    this.maxLines = 1,
    this.containerHeight = 60,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: containerHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        maxLines: maxLines,
        style: const TextStyle(fontSize: 16),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: TextStyle(fontSize: 14, color: corDoRotulo),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 22,
          ),
        ),
      ),
    );
  }
}
