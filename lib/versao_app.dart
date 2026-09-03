/// Atualizado manualmente a cada build enviada pra teste/produção — é a
/// forma mais simples de o testador conferir se instalou a versão certa
/// (compara o número/data mostrados na tela "Atualizações" com o que foi
/// combinado no momento do envio da build).
///
/// Não existe hoje uma versão "oficial" do app (pubspec.yaml não é
/// versionado a cada build) — isso aqui é o substituto até esse controle
/// existir de verdade.
class VersaoApp {
  static const String numero = "0.1.0";
  static const String data = "03/09/2026";
  static const String descricao =
      "Tela de Atualizações (menu superior) e correções de sexo/ordem dos itens";
}
