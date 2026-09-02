class ApiConfig {
  // Único lugar para trocar a URL base da API usada pelo app.
  //
  // Não é mais `const` de propósito: os testes de rede ruim
  // (test/sync_rede_ruim_test.dart) precisam apontar isso pra um servidor
  // local de mentira antes de cada teste, e um valor const não pode ser
  // reatribuído em tempo de execução. Em produção continua sempre igual ao
  // valor abaixo — nada muda pro app de verdade.
  static String baseUrl = 'https://agrolandes.com.br/teste_reproducao/sistema/api';
}
