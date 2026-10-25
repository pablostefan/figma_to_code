# Levar o figma2dart para o monorepo (<monorepo>)

Passo a passo para quando a solução sair deste repositório. O que o design ops configura e mantém depois (tokens,
ícones, mapeamentos, retrato): [DESIGN_OPS.md](DESIGN_OPS.md). Por que cada coisa é assim:
[plano/01](plano/01-monorepo-descoberta.md). Como a CLI acha tudo: [README da CLI](../figma2dart/README.md#monorepo).

## Onde fica cada coisa

```
<monorepo>/
  .gitignore                              ← + `.figma2dart/`
  rakelib/figma2dart.rake                 ← cópia de cli/tool/figma2dart.rake
  libraries/design_ops/packages/
    acme/  acme_templates/                ← não mudam
    acme_figma/                           ← novo: mapeamentos do acme e do acme_templates
    figma2dart/
      figma2dart.yaml                     ← config do repositório
      cli/                                ← daqui: figma2dart/ (inclui agent/, referência para os agentes do time)
      figma_connect/                      ← daqui: figma_connect/
      plugin/                             ← daqui: figma_plugin/ (opcional)
```

## 1. Copiar

Sem `.dart_tool/`, `build/`, `pubspec.lock`, `.figma2dart/` e `node_modules/`:

| Daqui | Para |
|---|---|
| `figma2dart/` | `libraries/design_ops/packages/figma2dart/cli/` |
| `figma_connect/` | `libraries/design_ops/packages/figma2dart/figma_connect/` |
| `figma_plugin/` | `libraries/design_ops/packages/figma2dart/plugin/` (se o plugin for distribuído de lá) |
| `docs/` | junto, se quiser a documentação no monorepo (os links relativos para `../figma2dart` mudam) |

O script `cli/tool/figma2dart` precisa continuar executável (`chmod +x`), e o git guarda isso.

**Testes da CLI:** `commands_test`, `policy_test` e `resolve_test` usam o `carteira_ds_figma` deste repositório
(`../../design_system/...`). No monorepo eles não acham: ou rode a suíte só aqui, ou troque esses caminhos por um
fixture próprio. O `monorepo_test` não depende de nada externo.

## 2. Criar o `acme_figma`

Use o `carteira_ds_figma` como modelo. O conteúdo de cada arquivo (tabela de tokens, ícones, mapeamentos, retrato)
está explicado em [DESIGN_OPS.md](DESIGN_OPS.md).

```yaml
# libraries/design_ops/packages/acme_figma/pubspec.yaml
name: acme_figma
publish_to: none
environment:
  sdk: ^3.11.0
dependencies:
  flutter:
    sdk: flutter
  acme:
    path: ../acme
  acme_templates:
    path: ../acme_templates
  figma_connect:
    path: ../figma2dart/figma_connect
```

- `lib/figma_policy.dart`: regras por tipo, tabela de ícones, componentes ignorados e a **tabela de tokens**
  ([FIGMA_CONNECT.md §7.3](FIGMA_CONNECT.md#73-tokens)). No Acme os tokens vêm do tema:
  `TokenSource(AcmeSpacing, via: 'context.acmeSpacing')`, uma por coleção do Figma (`Spacing`, `Color`, `Radius`…), e
  `textStyles:` para os estilos de texto. Confira com `figma2dart resolve` se sobra `(sem Dart, …)` nos briefs: é
  token sem correspondência (nome diferente e sem o nome do Figma no doc da constante).
- `lib/connect/<componente>.figma.dart`: um por componente do Acme; templates do `acme_templates` como
  `@FigmaConnect.sketch` sobre um `typedef`.
- `docs/` (opcional): um `.md` por componente.

As dependências por path do `acme_figma` (menos o `figma_connect`) são o que o `figma2dart packages` usa para dizer
se um pacote usa o DS: `acme` e `acme_templates`.

**Retrato do Acme** (para saber o que é do DS e o que é de outra biblioteca): no arquivo do Acme no Figma, rode o
plugin **sem seleção** em cada página de componentes (modo biblioteca) e depois
`figma2dart library <zip da página 1> <zip da página 2>…`. Grava `acme_figma/figma_library.json`: versione. Quando o
Acme mudar no Figma, exporte de novo só a página que mudou e rode `library` com ela.

## 3. Configurar

```yaml
# libraries/design_ops/packages/figma2dart/figma2dart.yaml
mappings: ../acme_figma     # relativo a este arquivo
screens: lib/figma          # pasta das telas geradas, relativa a cada pacote
# exports: ~/Downloads      # onde o plugin salva os figma2dart-*.zip (padrão)
```

- Um pacote de setor pode ter o próprio `figma2dart.yaml` (só `screens:`, por exemplo); ele vence o do repositório.
  Não ponha `mappings:` nele: dois configs com `mappings:` é erro.
- Raiz: `.figma2dart/` no `.gitignore` (cada pacote ganha uma pasta `.figma2dart/tasks` com os briefs).
- Raiz: copie `cli/tool/figma2dart.rake` para `rakelib/figma2dart.rake`, ou cole o bloco no `Rakefile`.

**`git add` de tudo.** A CLI e o rake acham o config, a CLI e os mapeamentos pelo índice do git: arquivo fora do
git não existe para eles.

## 4. Conferir

```sh
rake figma2dart:setup                         # uma vez por máquina; avisa se ~/.pub-cache/bin não está no PATH
figma2dart packages cards --json              # da raiz: acha pacotes; "ds": true nos que usam o Acme
cd libraries/<setor>/<pacote>
figma2dart doctor --json                      # "ok": true, mappings.components = nº de mapeamentos
figma2dart screens --json                     # telas do export mais novo em ~/Downloads
figma2dart resolve --screen "<tela>" --json   # escreve .figma2dart/tasks/<tela>/BRIEF.md
```

- A primeira chamada roda sozinha o `pub get` da CLI, do `acme_figma` e do pacote (eles estão fora do melos), com a
  saída no stderr. Precisa de acesso ao pub.dev (ou ao mirror/proxy da empresa) para o `analyzer` e o `archive`.
- O `doctor` leva ~6 s (o analyzer carregando os mapeamentos). Com o Acme inteiro deve subir: medir.
- `"problems"` no `doctor` traz a correção de cada item.

## 5. Componentes do app que já existem

Nada a configurar antes: quando o `resolve` achar uma classe de mesmo nome (`existing`), ou quando alguém indicar o
widget, `figma2dart link <key> <arquivo.dart>#<Classe>` escreve `figma/connect/<nome>.figma.dart` no pacote do widget
e põe o `figma_connect` nas dev_dependencies dele. Versione os dois. Se o time preferir outra pasta, `connect:` no
config do repositório.

- O widget precisa estar no pacote da tela ou numa dependência direta dele (é onde o `resolve` procura).
- Renomeou o widget? A anotação deixa de compilar e o `doctor`/`resolve` avisam (`warnings`); o componente volta a
  ser "a construir" até alguém corrigir ou apagar o `figma/connect/<nome>.figma.dart`. Como os pacotes dos setores
  estão fora do melos, o CI pode não pegar: vale incluir `figma/` no `dart analyze` do pacote.

## 6. Agentes (time)

Ficam com o time. O `cli/agent/` é a referência: orquestrador, subagente e skills, já usando `--package` e
`figma2dart packages`. Onde o Copilot e o opencode leem arquivos do usuário (instalação global, vale para workspaces
com vários pacotes):

| Peça | Copilot (VS Code) | opencode |
|---|---|---|
| agentes | `~/.copilot/agents/*.agent.md` | `~/.config/opencode/agents/*.md` (frontmatter `description`, `mode: primary`/`subagent`, `permission`) |
| skills | `~/.agents/skills/<nome>/SKILL.md` | `~/.agents/skills/<nome>/SKILL.md` (os dois leem) |

Uma tarefa do rake pode copiar esses arquivos junto com o `setup`.

## Em aberto

- **Windows:** o comando instalado é `sh`; precisa de uma versão `.ps1` se alguém do time usar.
- **Pasta das telas por pacote:** `lib/figma` é o padrão do config; se o `cli_bricks`/mason tem convenção
  (`lib/src/presentation/pages`…), use-a no config do repositório.
- **Pacotes que usam o Acme por outro pacote** (`commons/dependencies`): o `packages` marca `"ds": false` neles.
- As questões 02 a 08 do [plano](plano/README.md) (Acme × app, brief, tokens, check, skills, plugin).
