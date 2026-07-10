import 'dart:convert'; // Para converter o JSON
import 'package:http/http.dart' as http; // Para fazer a requisição Web
import 'package:shared_preferences/shared_preferences.dart'; // Para salvar o login
import 'package:flutter/material.dart';
import 'config/api_config.dart';

class AuthService {
  final String _urlApi = '${ApiConfig.baseUrl}/rest/usuario/login.php';

  Future<bool> login(String usuario, String senha) async {
    try {
      // Fazemos o POST para a API
      // Nota: Dependendo de como a sua API foi construída, os campos podem ser 'login', 'usuario' ou 'cpf'
      // Ajustei para 'login' e 'senha' que é o padrão comum.
      final response = await http.post(
        Uri.parse(_urlApi),
        body: {'username': usuario, 'pass': senha},
      );

      // --- INSERIR OS PRINTS AQUI ---
      debugPrint("URL CHAMADA: $_urlApi");
      debugPrint("STATUS CODE: ${response.statusCode}");
      debugPrint("RESPOSTA DO SERVIDOR: ${response.body}");
      // ------------------------------

      // Se o servidor responder Sucesso (200)
      if (response.statusCode == 200) {
        // Transformamos o texto que veio da internet em um Mapa (JSON)
        final Map<String, dynamic> userData = json.decode(response.body);

        // Verificamos se os dados básicos chegaram (ex: se o ID existe)
        if (userData.containsKey('id')) {
          SharedPreferences prefs = await SharedPreferences.getInstance();
          await prefs.setBool('isLoggedIn', true);
          await prefs.setString('userId', userData['id'].toString());
          await prefs.setString('userName', userData['nome'].toString());

          // ADICIONE ESTA LINHA: Salvando o CNPJ para usar como nome do banco (bd)
          // Verifique se o nome da chave no seu JSON é 'cnpj' ou 'cpf_cnpj'
          await prefs.setString('userCNPJ', userData['cnpj'].toString());

          String fazendasJson = json.encode(userData['local']);
          await prefs.setString('userFazendas', fazendasJson);
          return true;
        }
      }
      return false; // Algo deu errado (senha incorreta, etc)
    } catch (e) {
      // Se a internet cair ou o servidor estiver fora do ar, cai aqui
      debugPrint("Erro na API: $e");
      return false;
    }
  }

  // Função para deslogar (será usada no ícone SAIR)
  static Future<void> logout() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.clear(); // Apaga tudo o que gravamos (isLoggedIn vira false)
  }
}
