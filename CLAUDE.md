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
