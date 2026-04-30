import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'main_container.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Boi Virtual',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'FuturaStd',
        primaryColor: const Color(0xFF18385F),
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF18385F)),
      ),
      home: const AuthCheckScreen(),
      routes: {
        '/login': (context) => const LoginScreen(),
        '/main': (context) => const MainContainer(),
      },
    );
  }
}

class AuthCheckScreen extends StatefulWidget {
  const AuthCheckScreen({super.key});

  @override
  State<AuthCheckScreen> createState() => _AuthCheckScreenState();
}

class _AuthCheckScreenState extends State<AuthCheckScreen> {
  @override
  void initState() {
    super.initState();
    _processarVerificacao();
  }

  Future<void> _processarVerificacao() async {
    // 1. Forçamos o Flutter a esperar um pouquinho para a tela da bolinha "montar"
    await Future.delayed(const Duration(milliseconds: 500));

    // 2. Agora sim buscamos os dados
    SharedPreferences prefs = await SharedPreferences.getInstance();
    bool isLoggedIn = prefs.getBool('isLoggedIn') ?? false;

    // 3. Um segundinho extra só para você ver a bolinha girar e ter certeza que funcionou
    await Future.delayed(const Duration(seconds: 1));

    if (!mounted) return;

    if (isLoggedIn) {
      Navigator.pushReplacementNamed(context, '/main');
    } else {
      Navigator.pushReplacementNamed(context, '/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Adicionei 'const' no Scaffold e removi dos filhos para simplificar
    return const Scaffold(
      backgroundColor: Color(0xFF18385F),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: Colors.white, strokeWidth: 5),
            SizedBox(height: 25),
            Text(
              "Carregando informações...",
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
