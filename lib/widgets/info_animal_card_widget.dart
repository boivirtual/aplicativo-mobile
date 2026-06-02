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

    final mae = infoAnimal!['brincoMae'] ?? 'Não inf.';
    final criterioMae =
        infoAnimal!['criterioApartacaoMae']?.toString().trim() ?? '';

    final Map<String, dynamic>? bezerroApartacaoMae =
        infoAnimal!['bezerroApartacaoMae'] is Map<String, dynamic>
        ? infoAnimal!['bezerroApartacaoMae']
        : null;

    final codigoBezerro =
        bezerroApartacaoMae?['codigo']?.toString().trim() ?? '';

    final criterioBezerro =
        bezerroApartacaoMae?['criterio']?.toString().trim() ?? '';

    final bool temApartacaoMae = criterioMae.isNotEmpty;
    final bool temApartacaoBezerro =
        codigoBezerro.isNotEmpty && criterioBezerro.isNotEmpty;

    final String linhaPrincipal = temApartacaoMae
        ? "$sx - Nasc: ${infoAnimal!['nascimento'] ?? '--/--/----'} - ${infoAnimal!['raca'] ?? ''} ${infoAnimal!['pelagem'] ?? ''}"
        : "$sx - Nasc: ${infoAnimal!['nascimento'] ?? '--/--/----'} - ${infoAnimal!['raca'] ?? ''} ${infoAnimal!['pelagem'] ?? ''} - Mãe: $mae";

    String? linhaDestaque;

    if (temApartacaoMae) {
      linhaDestaque = "Mãe: $mae - Apartação: $criterioMae";
    } else if (temApartacaoBezerro) {
      linhaDestaque = "Bezerro: $codigoBezerro - Apartação: $criterioBezerro";
    }

    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Column(
        children: [
          Text(
            linhaPrincipal,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF42A5F5),
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),

          if (linhaDestaque != null)
            Text(
              linhaDestaque,
              style: const TextStyle(
                fontSize: 13,
                color: Color(0xFF42A5F5),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.2,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
        ],
      ),
    );
  }
}
