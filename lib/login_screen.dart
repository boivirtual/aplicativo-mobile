import 'package:flutter/material.dart';
import 'auth_service.dart'; // Importando a lógica da API que criamos

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  // Controles para capturar o que o usuário digita
  final TextEditingController _userController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  bool _isObscure = true; // Controla se a senha está visível ou oculta
  bool _isLoading = false; // Mostra um carregamento ao clicar no botão

  // Cores baseadas na sua imagem
  final Color darkBlue = const Color(0xFF18385F);
  final Color lightBlue = const Color(0xFF5D9CEC);

  void _handleLogin() async {
    setState(() => _isLoading = true);

    // Chama o serviço de autenticação
    AuthService auth = AuthService();
    bool success = await auth.login(
      _userController.text,
      _passwordController.text,
    );

    setState(() => _isLoading = false);

    if (success) {
      // Se deu certo, vai para a tela principal e remove a tela de login da pilha
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/main');
      }
    } else {
      // Se deu errado, mostra um aviso
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao entrar. Verifique seus dados.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: darkBlue,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Logo
              Image.asset('assets/images/logo.png', height: 180),
              const SizedBox(height: 10),
              const Text(
                "Boi Virtual",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 32,
                  fontWeight: FontWeight.w300,
                ),
              ),
              const SizedBox(height: 60),

              // Campo de CPF ou E-mail
              TextField(
                controller: _userController,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.person_outline, color: Colors.white),
                  hintText: "CPF ou E-mail",
                  hintStyle: TextStyle(color: Colors.white70),
                  enabledBorder: UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Campo de Senha
              TextField(
                controller: _passwordController,
                obscureText: _isObscure,
                maxLength: 8, // Limite pedido
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  counterText: "", // Esconde o contador de caracteres
                  prefixIcon: const Icon(
                    Icons.lock_outline,
                    color: Colors.white,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isObscure ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white,
                    ),
                    onPressed: () => setState(() => _isObscure = !_isObscure),
                  ),
                  hintText: "Senha",
                  hintStyle: const TextStyle(color: Colors.white70),
                  enabledBorder: const UnderlineInputBorder(
                    borderSide: BorderSide(color: Colors.white54),
                  ),
                ),
              ),
              const SizedBox(height: 50),

              // Botão Entrar
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: lightBlue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: _isLoading ? null : _handleLogin,
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Text(
                          "Entrar",
                          style: TextStyle(color: Colors.white, fontSize: 18),
                        ),
                ),
              ),

              const SizedBox(height: 20),

              // Links Inferiores
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      "Esqueceu a Senha?",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                  TextButton(
                    onPressed: () {},
                    child: const Text(
                      "Novo Cadastro?",
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
