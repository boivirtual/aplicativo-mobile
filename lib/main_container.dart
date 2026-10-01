import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:boivirtual/screens/pesagem_screen.dart';
import 'package:boivirtual/screens/mapa_screen.dart';
import 'package:boivirtual/screens/chuva_screen.dart';
import 'package:boivirtual/screens/agenda_screen.dart';
import 'package:boivirtual/screens/dashboard_screen.dart';
import 'package:boivirtual/screens/home_screen.dart';
import 'package:boivirtual/screens/atualizacoes_screen.dart';
import 'package:boivirtual/screens/atualizando_dados_screen.dart';
import 'package:boivirtual/services/connectivity_service.dart';
import 'package:boivirtual/widgets/indicador_conectividade_widget.dart';
import 'package:boivirtual/widgets/indicador_sincronizando_widget.dart';
import 'auth_service.dart';

class MainContainer extends StatefulWidget {
  const MainContainer({super.key});

  @override
  State<MainContainer> createState() => _MainContainerState();
}

class _MainContainerState extends State<MainContainer>
    with WidgetsBindingObserver {
  // REGRA: O programa abre direto na Pesagem (Index 2)
  int _currentIndex = 2;
  String _userName = "Usuário";

  /// Android normalmente não fecha o app quando o vaqueiro sai (Home,
  /// trocar de app) — só coloca em segundo plano e o processo continua
  /// vivo, então reabrir volta direto pra onde parou, sem passar de novo
  /// pela tela de atualização de dados. Se isso ficar parado por muito
  /// tempo (o vaqueiro só volta depois de horas, ou no dia seguinte), o
  /// cadastro de animais/pesagens pode estar bem desatualizado. Esse tempo
  /// aqui é o quanto pode passar em segundo plano antes de forçar a tela de
  /// atualização de novo ao voltar.
  static const _tempoMaximoEmSegundoPlano = Duration(hours: 1);

  bool _verificandoAoVoltar = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _carregarDadosUsuario();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _verificarSeAtualizaAoVoltar();
    }
  }

  Future<void> _verificarSeAtualizaAoVoltar() async {
    // Evita empilhar mais de uma verificação se o resumed disparar de novo
    // rápido (ex: trocar de app repetidamente) antes da anterior terminar.
    if (_verificandoAoVoltar) return;
    _verificandoAoVoltar = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final ultimaIso = prefs.getString(
        AtualizandoDadosScreen.chaveUltimaAtualizacao,
      );
      final ultima = ultimaIso != null ? DateTime.tryParse(ultimaIso) : null;
      final passouDoTempo =
          ultima == null ||
          DateTime.now().difference(ultima) > _tempoMaximoEmSegundoPlano;
      if (!passouDoTempo) return;

      // Checagem fresca — não vale a pena nem mostrar a tela de atualização
      // se não tiver internet de verdade agora.
      await ConnectivityService.instance.verificarAgora();
      if (!ConnectivityService.instance.temInternetReal) return;

      if (!mounted) return;
      final navigator = Navigator.of(context);
      await navigator.push(
        MaterialPageRoute(
          builder: (context) =>
              AtualizandoDadosScreen(aoConcluir: () => Navigator.pop(context)),
        ),
      );
    } finally {
      _verificandoAoVoltar = false;
    }
  }

  Future<void> _carregarDadosUsuario() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _userName = prefs.getString('userName') ?? "Usuário";
    });
  }

  void _abrirAtualizacoes(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            AtualizacoesScreen(onBack: () => Navigator.pop(context)),
      ),
    );
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
                const IndicadorConectividadeWidget(),
                const SizedBox(width: 4),
                // Um botão só com duas opções — "Atualizações" (versão do
                // app instalada + cadastro de animais, pra checklist de
                // testes) e "Sair" (logout, comportamento de antes,
                // inalterado).
                PopupMenuButton<String>(
                  icon: const Icon(
                    Icons.more_vert,
                    color: Colors.white,
                    size: 22,
                  ),
                  onSelected: (opcao) {
                    if (opcao == 'atualizacoes') {
                      _abrirAtualizacoes(context);
                    } else if (opcao == 'sair') {
                      _confirmarSaida(context);
                    }
                  },
                  itemBuilder: (context) => const [
                    PopupMenuItem(
                      value: 'atualizacoes',
                      child: Row(
                        children: [
                          Icon(Icons.fact_check_outlined, size: 18),
                          SizedBox(width: 10),
                          Text('Atualizações'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      value: 'sair',
                      child: Row(
                        children: [
                          Icon(Icons.logout, size: 18),
                          SizedBox(width: 10),
                          Text('Sair'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            )
          : null,
      body: Stack(
        children: [
          Column(children: [Expanded(child: pages[_currentIndex])]),
          const IndicadorSincronizandoWidget(),
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
