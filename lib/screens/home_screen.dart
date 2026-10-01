import 'package:flutter/material.dart';

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

              // Quadro 1: Mapa Gado - Largura total
              _buildWideCard("Mapa Gado", 'home.png', 0, onNavigate),

              const SizedBox(height: 15),

              // Grade com os outros 4 quadros menores
              GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: 2,
                mainAxisSpacing: 15,
                crossAxisSpacing: 15,
                childAspectRatio: 1.1,
                children: [
                  _buildMenuCard("Dashboard", 'dashboard.png', 1, onNavigate),
                  _buildMenuCard("Pesagem", 'pesagem.png', 2, onNavigate),
                  _buildMenuCard("Chuva", 'chuva.png', 3, onNavigate),
                  _buildMenuCard("Agenda", 'agenda.png', 4, onNavigate),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Quadro LARGO (Mapa Gado) - AJUSTADO PARA PADRONIZAR
  Widget _buildWideCard(
    String title,
    String img,
    int index,
    Function(int)? tap,
  ) {
    const Color azulIcone = Color(0xFF228cb9);

    return GestureDetector(
      onTap: () => tap?.call(index),
      child: LayoutBuilder(
        builder: (context, constraints) {
          double alturaCalculada = (constraints.maxWidth / 2) / 1.1;

          return Container(
            width: double.infinity,
            height: alturaCalculada,
            padding: const EdgeInsets.all(18),
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
            Text(
              title,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: Color(0xFF18385F),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
