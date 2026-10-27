import 'package:flutter/material.dart';

import 'resumo_diario_screen.dart';

class HomeScreen extends StatelessWidget {
  final Function(int)? onNavigate;

  const HomeScreen({super.key, this.onNavigate});

  @override
  Widget build(BuildContext context) {
    const Color azulBarra = Color(0xFF18385F);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Bem-vindo ao Boi Virtual!",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: azulBarra,
                ),
              ),
              const SizedBox(height: 5),
              const Text(
                "Selecione uma funcionalidade:",
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 20),

              // Linha 1: Mapa de Gado — largura total
              _buildWideCard(
                "Mapa de Gado",
                'home.png',
                () => onNavigate?.call(0),
              ),

              const SizedBox(height: 15),

              // Linhas 2 e 3: Pesagem e Chuva; Agenda e Resumo Diário
              // (mesmos índices do rodapé, em main_container.dart)
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.1,
                children: [
                  _buildMenuCard("Pesagem", 'pesagem.png', 1, onNavigate),
                  _buildMenuCard("Chuva", 'chuva.png', 2, onNavigate),
                  _buildMenuCard("Agenda", 'agenda.png', 3, onNavigate),
                  _buildMenuCard(
                    "Resumo Diário",
                    'farmer.png',
                    4,
                    onNavigate,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Quadro LARGO (Resumo Diário da Fazenda) - mesmo padrão dos outros
  Widget _buildWideCard(
    String title,
    String img,
    VoidCallback onTap, {
    Color fundo = Colors.white,
  }) {
    const Color azulIcone = Color(0xFF228cb9);

    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          double alturaCalculada = (constraints.maxWidth / 2) / 1.1;

          return Container(
            width: double.infinity,
            height: alturaCalculada,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: fundo,
              borderRadius: BorderRadius.circular(15),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // ÍCONE AJUSTADO (de 50 para 32 para igualar aos outros)
                Align(
                  alignment: Alignment.topLeft,
                  child: Image.asset(
                    'assets/images/$img',
                    width: 32,
                    height: 32,
                    color: azulIcone,
                  ),
                ),
                // FONTE AJUSTADA (de 18 para 14 para igualar aos outros)
                Align(
                  alignment: Alignment.bottomLeft,
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF18385F),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Quadros MENORES
  Widget _buildMenuCard(
    String title,
    String img,
    int index,
    Function(int)? tap,
  ) {
    const Color azulIcone = Color(0xFF228cb9);

    return GestureDetector(
      onTap: () => tap?.call(index),
      child: Container(
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(
              'assets/images/$img',
              width: 32,
              height: 32,
              color: azulIcone,
            ),
            // sempre em uma linha: nos cards menores (3 por linha) a fonte
            // encolhe um pouco em vez de quebrar o nome
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                title,
                maxLines: 1,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF18385F),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
