# No monorepo

Como a solução fica no monorepo (<monorepo>), o que cada pessoa instala e como conferir. O que o time do DS
configura e mantém depois (tokens, ícones, anotações, retrato) está em [DESIGN_OPS.md](DESIGN_OPS.md); como a CLI acha
cada coisa, em [ARQUITETURA.md §3](ARQUITETURA.md#3-como-a-cli-acha-as-coisas).

**Requisitos:** Dart ≥ 3.5 e Flutter ≥ 3.24 (o `figma2dart` e o `figma_connect` declaram `sdk: ^3.5.0`); acesso ao
pub.dev ou ao mirror da empresa, para o primeiro `pub get` da CLI.

## Onde fica cada coisa

Esta pasta inteira fica ao lado do Acme:

```
<monorepo>/
  rakelib/figma2dart.rake                 cópia de figma2dart/tool/figma2dart.rake (opcional)
  libraries/design_ops/packages/
    acme/  acme_templates/                o DS: não muda
    figma_to_code/                        esta pasta (o nome pode ser outro)
      figma_to_dart.yaml                  config do repositório: mappings: acme_figma
      acme_figma/                         anotações e política do Acme, retrato do Figma
      figma2dart/                         CLI
      figma_connect/                      API das anotações e captura da revisão
      copilot_plugin/                     agentes e skills
      figma_plugin/                       plugin do Figma
      docs/
  libraries/<setor>/<pacote>/             onde as telas são geradas
    lib/figma/                            telas e widgets gerados
    figma/connect/                        @FigmaLocal: componente do Figma → widget do pacote
    .figma2dart/                          tarefas (fora do git)
```

O `acme_figma` aponta para o DS por caminho relativo (`../../acme`, `../../acme_templates`) e para o
`figma_connect` (`../figma_connect`). Se o Acme mudar de lugar, só esses caminhos mudam. As dependências por caminho
do `acme_figma` (menos o `figma_connect`) também dizem à CLI quais pacotes usam o DS.

**Tudo versionado.** A CLI acha o config e o pacote de mapeamentos pelo índice do git: um arquivo fora do git não
existe para ela. A pasta já ignora `.dart_tool/`, `build/`, `node_modules/` e `.figma2dart/`.

## O que cada pessoa instala (uma vez por máquina)

1. **A CLI no PATH:** `rake figma2dart:setup` ou `libraries/design_ops/packages/figma_to_code/figma2dart/tool/figma2dart setup`.
   Grava o comando `figma2dart` em `~/.pub-cache/bin` (que precisa estar no `PATH`). O comando sempre roda a CLI do
   repositório de onde é chamado, então um `git pull` já a atualiza.
2. **O plugin do Copilot:** [copilot_plugin/README.md](../copilot_plugin/README.md). No VS Code, `chat.pluginLocations`
   apontando para `copilot_plugin/` no clone; na Copilot CLI, `copilot plugin install <pasta>`. Na CLI, o plugin
   também liga o LSP do Dart ([copilot_plugin/README.md](../copilot_plugin/README.md#lsp-do-dart-copilot-cli)).
3. **O plugin do Figma** (quem exporta): [figma_plugin/README.md](../figma_plugin/README.md).

O opencode não lê o `com.github.copilot/` do plugin: nele, os agentes ficam em `~/.config/opencode/agents/*.md`, e as
skills de `copilot_plugin/skills/` servem como estão.

## Config

`figma_to_dart.yaml` da pasta (o do repositório):

```yaml
mappings: acme_figma     # relativo a este arquivo
# exports: ~/Downloads   # onde o plugin do Figma salva os zips (padrão)
```

`mappings:` fica só no do repositório: dois configs com `mappings:` é erro.

**Pasta das telas, por pacote.** Cada pacote guarda as telas num lugar (`lib/templates`, `lib/features/…`), então o
config do repositório não fixa uma. Na primeira tela de um pacote, o agente procura onde ficam as telas dele,
confirma com você e passa `figma2dart resolve --screens-dir <pasta>`. A CLI guarda a escolha em
`<pacote>/.figma2dart/local.yaml`: vale só na sua máquina, só naquele pacote, e não vai para o git (a pasta
`.figma2dart/` tem um `.gitignore` próprio). Nenhum arquivo versionado muda para implementar uma tela. Um padrão do
time para um pacote pode ir no `figma_to_dart.yaml` dele (`screens:`), mas é decisão de vocês, não do agente.

## Conferir

```sh
figma2dart packages cards --json              # da raiz: acha pacotes; "ds": true nos que usam o Acme
cd libraries/<setor>/<pacote>
figma2dart doctor --json                      # "ok": true; mappings.components = nº de anotações; policy = cobertura
figma2dart screens --json                     # telas do export mais novo
figma2dart resolve --screen "<tela>" --json   # escreve .figma2dart/tasks/<tela>/BRIEF.md
```

- A primeira chamada roda sozinha o `pub get` da CLI, do `acme_figma` e do pacote (eles estão fora do melos), com a
  saída no stderr.
- O `doctor` leva alguns segundos: é o analyzer carregando as anotações.
- Cada item de `"problems"` no `doctor` traz a correção.

## Componentes do app que já existem

Quando o `resolve` acha uma classe de mesmo nome (`existing`), ou alguém indica o widget,
`figma2dart link <key> <arquivo.dart>#<Classe>` escreve `figma/connect/<nome>.figma.dart` no pacote do widget e põe o
`figma_connect` nas dev_dependencies dele. Versione os dois. Outra pasta: `connect:` no config do repositório.

- O widget precisa estar no pacote da tela ou numa dependência direta dele (é onde o `resolve` procura).
- Renomeou o widget? A anotação deixa de compilar e o `doctor`/`resolve` avisam (`warnings`); o componente volta a ser
  "a construir" até alguém corrigir ou apagar o arquivo. Como os pacotes dos setores estão fora do melos, vale incluir
  `figma/` no `dart analyze` do pacote.

## Testes da CLI

`commands_test`, `policy_test` e `resolve_test` usam o `carteira_ds_figma` do repositório do POC
(`../../design_system/...`). No monorepo, rode a suíte só no repositório do POC ou troque esses caminhos por um
fixture próprio. `monorepo_test` e `plugin_test` não dependem de nada externo.

## Limites conhecidos

- O comando instalado é `sh`: no Windows, precisaria de uma versão `.ps1`.
- Um pacote que usa o Acme por outro pacote (`commons/dependencies`) aparece com `"ds": false` no `packages`.
