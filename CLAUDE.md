# CLAUDE.md — Instruções para o Assistente

## Premissa obrigatória nº 1: Idioma

Todas as respostas, explicações, mensagens e textos escritos pelo assistente
devem ser **obrigatoriamente em Português do Brasil**, independentemente do
idioma usado na pergunta. Isso inclui mensagens de commit e qualquer texto
exibido ao usuário. Código, nomes de variáveis e termos técnicos que já
estejam em inglês por convenção do projeto (Flutter/Dart) podem permanecer
em inglês.

---

## Premissa obrigatória nº 2: Repositório correto

Esta pasta (`C:\Users\George\Desktop\boivirtual`) é o **aplicativo mobile
Flutter** (funcionalidade de pesagem offline, entre outras). Todo commit de
arquivo feito aqui deve ir **exclusivamente** para o repositório
`boivirtual/aplicativo-mobile` no GitHub.

Não confundir com o repositório `boivirtual/sistema-web`, que é outro
projeto completamente separado, em outra pasta (`C:\wamp64\www\reproducao\sistema`)
— esse contém o sistema web em PHP e a pasta `api/` que o app consome.
Nunca commitar arquivos deste projeto Flutter dentro do repositório do
sistema web, nem vice-versa.

**Sobre a pasta `api/`** (backend que este app consome): ela vive dentro do
repositório `sistema-web`, na branch **`master`** desse repositório — não
existe mais uma branch separada só para ela (havia uma `offline-pesagem`
nesse repositório até 2026-09-02, mas ela causava confusão real: o deploy
manual do George sempre publica o que está no `master`, então trabalho
feito só naquela branch nunca ia pro ar). Se for preciso editar algo em
`api/`, é sempre no `master` do `sistema-web`.

A branch de trabalho atual é `offline-pesagem`, mas o hook de auto-commit
(veja abaixo) sempre envia para a branch que estiver ativa no momento
(`git push origin HEAD`) — então, se a branch de trabalho mudar no futuro,
não é necessário alterar essa configuração.

---

## Projeto
**Nome:** Boi Virtual — Aplicativo Mobile (Flutter)
**Tecnologia:** Flutter/Dart
**Repositório:** https://github.com/boivirtual/aplicativo-mobile.git

---

## Regra obrigatória: Atualizar GitHub após toda alteração

Sempre que qualquer arquivo for criado, editado ou excluído nesta pasta, um
hook automático (configurado em `.claude/settings.local.json`) já executa
`git add`, `git commit` e `git push origin HEAD` sozinho, para o repositório
`boivirtual/aplicativo-mobile`. Não é necessário rodar esses comandos
manualmente — apenas confirme, se tiver dúvida, que o commit realmente foi
enviado (`git log --oneline -1` e `git status`).

**Importante:** este hook é independente do hook equivalente configurado no
projeto do sistema web (`C:\wamp64\www\reproducao\sistema`). As duas pastas
têm repositórios e hooks próprios, então é seguro trabalhar nas duas ao
mesmo tempo, em sessões separadas, sem risco de um commit ir parar no
repositório errado.

---

## Padrões visuais do app (seguir sempre, em toda tela nova)

Todas as telas do app têm que ser iguais. Antes de criar ou mexer numa tela,
reaproveitar os componentes e cores abaixo — nunca criar cor, borda ou campo
"solto" na tela.

### Cores — `lib/utils/estilo_app.dart` (`EstiloApp`)
- `azulBarra` (#18385F): AppBar, títulos, item selecionado do rodapé.
- `azulIcone` (#228CB9): ícones de cards, opções e linhas de marcar.
- `azulPrimario` (#337AB7, btn-primary do web): ícones de editar/excluir.
- `verdeConfirmar` (#4CAF50): botões Confirmar/Gravar.
- `azulBordaFoco` (#81D4FA): borda do campo em edição.
- Tarja do topo das telas: azul bem claro (`Colors.blue` 10% sobre branco).

### Campos de texto
- Usar `CampoTextoTopo` / `CampoValorTopo` (`lib/widgets/campo_topo_widget.dart`):
  rótulo no meio quando vazio e no topo quando preenchido, valor em negrito
  14, exemplo (dica) só aparece com o campo em edição.
- Campo com caixa própria (Pesagem, Chuva, buscas): envolver a caixa com
  `MolduraFoco` (`estilo_app.dart`) para ganhar a borda azul clara do foco.
- A borda é SEMPRE `foregroundDecoration` que só muda de cor
  (`EstiloApp.molduraCampo`). Nunca colocar/tirar uma borda normal no
  Container do campo: isso recria o campo de texto e o cursor some.
- Campo de número: `keyboardType: TextInputType.number` +
  `FilteringTextInputFormatter.digitsOnly` (peso sempre inteiro).

### Selects
- Fora de modal: `SeletorCampoWidget` (`destaque: true`).
- Dentro de modal: lista que abre embaixo do campo, dentro do próprio modal
  (sem janela por cima), com "— Selecione —" quando o campo pode ficar vazio;
  linha escolhida com fundo azul claro (#D6E8FA) e ✓.
- Seleção múltipla: lista já aberta mostrando todas as opções, toque
  marca/desmarca, nomes marcados em itálico embaixo ("Nenhuma selecionada").

### Modais
- Fundo cinza (`Colors.grey[200]`), cantos 12, (x) azul-escuro redondo no
  canto superior direito, conteúdo com rolagem, botão verde "Confirmar …"
  embaixo; `barrierDismissible: false`.
- Teclado aberto: folga embaixo (160) e `rolarAteCampoEmFoco()`
  (`lib/utils/rolar_ate_foco.dart`) para o campo não ficar atrás do teclado,
  mantendo o Confirmar visível.

### Mensagens
- Avisos/erros/sucesso: `AppAlert` (`lib/utils/app_alert.dart`).
- Confirmação de exclusão: título em negrito "Excluir …", texto "Confirma a
  exclusão …?", botões NÃO (negrito, em evidência) e SIM, como o "Excluir
  Item" da Pesagem.

### Textos
- A fonte do app (FuturaStd) só tem a versão fina: negrito é simulado com
  `fontWeight: w900` + sombras da mesma cor (ver `_textoGrosso` no Resumo
  Diário).
- Títulos de seção centralizados em azul claro; subtítulos com maiúsculas
  iniciais ("Aplicações Realizadas Hoje").

### Telas
- Toda tela que rola reserva no fim a altura da barra de navegação do
  celular (`MediaQuery.paddingOf(context).bottom`), senão o último item fica
  escondido atrás dela.
- App só em retrato. Rodapé em todos os programas: Mapa Gado, Pesagem,
  Chuva, Agenda, Resumo Diário (`main_container.dart`).
