import 'package:flutter/material.dart';

class InfoAnimalCardWidget extends StatelessWidget {
  final Map<String, dynamic>? infoAnimal;

  const InfoAnimalCardWidget({super.key, required this.infoAnimal});

  @override
  Widget build(BuildContext context) {
    if (infoAnimal == null) return const SizedBox.shrink();

    final sx = (infoAnimal!['sexo'] == 'M' || infoAnimal!['sexo'] == 'Macho')
        ? 'Macho'
        : 'Fêmea';

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        "$sx - Nasc: ${infoAnimal!['nascimento'] ?? '--/--/----'} - ${infoAnimal!['raca'] ?? ''} ${infoAnimal!['pelagem'] ?? ''} - Mãe: ${infoAnimal!['brincoMae'] ?? 'Não inf.'}",
        style: const TextStyle(
          fontSize: 11,
          color: Color(0xFF42A5F5),
          fontWeight: FontWeight.bold,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
