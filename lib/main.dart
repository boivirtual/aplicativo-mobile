import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'screens/login_screen.dart';
import 'screens/atualizando_dados_screen.dart';
import 'main_container.dart';
import 'services/sync_service.dart';
import 'services/chuva_sync_service.dart';
import 'data/local_database.dart';

// TEMPORÁRIO (2026-09-22) — limpeza pontual a pedido do George de uma
// pesagem fantasma (lote Desmama de 27/08/2026) que só aparecia offline —
// causa raiz já documentada (PesagemLocalDao.listarPendentesLocais não
// filtra por fazenda). Remover esta função e a chamada em main() assim que
// confirmado que a pesagem sumiu do aparelho.
Future<void> _limpezaTemporariaPesagemFantasma() async {
  final db = await LocalDatabase.instance.database;
  final achadas = await db.query(
    'pesagens_locais',
    where: 'criado_em LIKE ?',
    whereArgs: ['2026-08-27%'],
  );
  debugPrint('LIMPEZA_TEMP: encontradas ${achadas.length} pesagem(ns): $achadas');
  for (final p in achadas) {
    final idLocal = p['id_local'] as int;
    await db.delete(
      'itens_pesagem_locais',
      where: 'pesagem_id_local = ?',
      whereArgs: [idLocal],
    );
    await db.delete(
      'pesagens_locais',
      where: 'id_local = ?',
      whereArgs: [idLocal],
    );
    debugPrint(
      'LIMPEZA_TEMP: removida pesagem id_local=$idLocal lote=${p['lote']}',
    );
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await _limpezaTemporariaPesagemFantasma();
  // Liga o motor de sincronização offline assim que o app abre — ele fica
  // ouvindo conectividade e reprocessando a fila local durante toda a vida
  // do app, independente de qual tela está em primeiro plano.
  SyncService.instance.iniciar();
  // Motor de sincronização da chuva — isolado do de cima de propósito (ver
  // ChuvaSyncService), não mexe na fila/lógica da pesagem.
  ChuvaSyncService.instance.iniciar();
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
        '/atualizando': (context) => const AtualizandoDadosScreen(),
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
      Navigator.pushReplacementNamed(context, '/atualizando');
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
