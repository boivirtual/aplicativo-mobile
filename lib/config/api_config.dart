class ApiConfig {
  /// Endereço da API do servidor de TESTE (agrolandes.com.br). É o padrão:
  /// gerou o APK sem escolher nada, ele vai para o teste — nunca para a
  /// produção por engano.
  static const urlTeste =
      'https://agrolandes.com.br/teste_reproducao/sistema/api';

  /// Endereço da API de PRODUÇÃO (boivirtual.com.br).
  static const urlProducao = 'https://boivirtual.com.br/sistema/api';

  // Único lugar da URL base da API usada pelo app. Vem do build:
  //   flutter build apk --release --dart-define=API_URL=<endereço>
  // As tarefas do VS Code (Terminal > Executar Tarefa: "APK Teste" e
  // "APK Produção (release)", em .vscode/tasks.json) já passam o endereço
  // certo. Sem o --dart-define, fica o do teste.
  //
  // Não é `const` de propósito: os testes de rede ruim
  // (test/sync_rede_ruim_test.dart) precisam apontar isso pra um servidor
  // local de mentira antes de cada teste, e um valor const não pode ser
  // reatribuído em tempo de execução.
  static String baseUrl = const String.fromEnvironment(
    'API_URL',
    defaultValue: urlTeste,
  );

  /// O APK aponta para o servidor de teste? (mostra a tarja "TESTE").
  static bool get ehTeste => !baseUrl.startsWith(urlProducao);
}
