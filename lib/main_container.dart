import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'services/connectivity_service.dart';
import 'package:boivirtual/screens/pesagem_screen.dart';
import 'package:boivirtual/screens/mapa_screen.dart';
import 'package:boivirtual/screens/chuva_screen.dart';
import 'package:boivirtual/screens/agenda_screen.dart';
import 'package:boivirtual/screens/dashboard_screen.dart';
import 'package:boivirtual/screens/home_screen.dart';
import 'auth_service.dart';

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer> {
  // REGRA: O programa abre direto na Pesagem (Index 2)
  int _currentIndex = 2;
  String _userName = "Usuário";

  late StreamSubscription<NivelConexao> _subscription;
  bool _mostrarBanner = false;
  String _mensagemInternet = "";
  Color _corBanner = Colors.orange[800]!;

  @override
  void initState() {
    super.initState();
    _carregarDadosUsuario();
    _subscription = ConnectivityService.instance.status.listen(
      (nivel) => _aplicarNivelConexao(nivel),
    );
  }

  Future<void> _carregarDadosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? "Usuário";
    });
  }

  void _aplicarNivelConexao(NivelConexao nivel) {
    switch (nivel) {
      case NivelConexao.semInternet:
        setState(() {
          _mensagemInternet = "Sem Internet";
          _corBanner = Colors.redAccent;
          _mostrarBanner = true;
        });
        break;
      case NivelConexao.internetRuim:
        // Mantém o mesmo comportamento de antes: só liga o banner, sem
        // sobrescrever mensagem/cor (herda o que já estava definido).
        setState(() => _mostrarBanner = true);
        break;
      case NivelConexao.internetOk:
        setState(() => _mostrarBanner = false);
        break;
    }
  }

  void _confirmarSaida(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Sair do App"),
        content: const Text("Deseja realmente sair do Boi Virtual?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              "Não",
              style: TextStyle(color: Colors.blue, fontWeight: FontWeight.bold),
            ),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await AuthService.logout();
              if (!context.mounted) return;
              Navigator.pushReplacementNamed(context, '/login');
            },
            child: const Text(
              "Sim",
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const Color azulBarra = Color(0xFF18385F);
    const Color cinzaInativo = Colors.grey;

    final List<Widget> pages = [
      MapaScreen(onBack: () => setState(() => _currentIndex = 5)),
      DashboardScreen(onBack: () => setState(() => _currentIndex = 5)),
      PesagemScreen(onBack: () => setState(() => _currentIndex = 5)),
      ChuvaScreen(onBack: () => setState(() => _currentIndex = 5)),
      AgendaScreen(onBack: () => setState(() => _currentIndex = 5)),
      // AJUSTE: Passando a função onNavigate para a HomeScreen
      HomeScreen(onNavigate: (index) => setState(() => _currentIndex = index)),
    ];

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _currentIndex == 5
          ? AppBar(
              backgroundColor: azulBarra,
              elevation: 0,
              automaticallyImplyLeading: false,
              title: Text(
                "Olá, $_userName",
                style: const TextStyle(fontSize: 18, color: Colors.white),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.logout, color: Colors.white, size: 20),
                  onPressed: () => _confirmarSaida(context),
                ),
              ],
            )
          : null,
      body: Column(
        children: [
          if (_mostrarBanner && _currentIndex == 5)
            Container(
              width: double.infinity,
              color: _corBanner,
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Center(
                child: Text(
                  _mensagemInternet,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          Expanded(child: pages[_currentIndex]),
        ],
      ),
      // AJUSTE: Se estiver na Home (Index 5), o rodapé some.
      bottomNavigationBar: _currentIndex == 5
          ? null
          : BottomNavigationBar(
              currentIndex: _currentIndex > 4 ? 0 : _currentIndex,
              onTap: (index) => setState(() => _currentIndex = index),
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.white,
              selectedItemColor: azulBarra,
              unselectedItemColor: cinzaInativo,
              items: [
                _buildNavItem(
                  'home.png',
                  'Mapa Gado',
                  0,
                  azulBarra,
                  cinzaInativo,
                ),
                _buildNavItem(
                  'dashboard.png',
                  'Dashboard',
                  1,
                  azulBarra,
                  cinzaInativo,
                ),
                _buildNavItem(
                  'pesagem.png',
                  'Pesagem',
                  2,
                  azulBarra,
                  cinzaInativo,
                ),
                _buildNavItem('chuva.png', 'Chuva', 3, azulBarra, cinzaInativo),
                _buildNavItem(
                  'agenda.png',
                  'Agenda',
                  4,
                  azulBarra,
                  cinzaInativo,
                ),
              ],
            ),
    );
  }

  BottomNavigationBarItem _buildNavItem(
    String img,
    String label,
    int index,
    Color ativo,
    Color inativo,
  ) {
    return BottomNavigationBarItem(
      icon: Image.asset(
        'assets/images/$img',
        width: 30,
        height: 30,
        color: _currentIndex == index ? ativo : inativo,
      ),
      label: label,
    );
  }
}
