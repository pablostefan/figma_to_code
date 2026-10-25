# 01 · Monorepo: descoberta e como expor a CLI

Passo a passo da migração: [MIGRACAO_MONOREPO.md](../MIGRACAO_MONOREPO.md).

## O monorepo (<monorepo>)

```
<monorepo>/                 ← raiz do git; melos.yaml + pubspec.yaml (melos)
  .github/  .vscode/  scripts/  cli_bricks/  mason.yaml  .tool-versions
  apps/                            ← apps (casca)
  libraries/<feature>/…            ← features: onde as telas são implementadas
  libraries/design_ops/
    app/                           ← app do design ops
    packages/
      acme/                        ← componentes do DS
      acme_templates/              ← componentes Flutter que são telas prontas (templates)
      acme_themes/  assets/  morphix/  recipes/  acme_playground/  acme_remote_config/
    acme_nexus/  snippets/  workspaces/
```

- **Sem pub workspaces** (nenhum `resolution: workspace`): cada pacote tem o próprio `package_config.json`.
- **O `melos.yaml` lista** os apps (`apps/*_app_v5`, `hub_app`…), `libraries/commons/dependencies/**`,
  `commons/dev_dependencies/**`, alguns `commons/packages/*`, `app_start/**`, `xconfig/**`, `xdebugging/**`; ignora
  `libraries/**/app` e `libraries/**/packages/**/example`. **Os pacotes dos setores e o `design_ops` não estão no
  melos:** o `package_config` deles só existe se alguém (ou o VS Code) rodou `pub get` ali, então a CLI precisa
  rodar quando faltar.
- **Os times trabalham em pacotes por setor** (`libraries/<setor>/…`), não por app: a tela vai num desses pacotes.
- Usam VS Code (Copilot) e opencode. **A maioria abre um workspace do VS Code com vários pacotes** (multi-root),
  não a raiz do monorepo: arquivos de agente na raiz do git não seriam vistos.

## Problema

O figma2dart hoje ([workspace.dart](../../figma2dart/lib/src/workspace.dart)) assume um app pequeno:

1. **Pacote alvo = `pubspec.yaml` mais próximo.** Da raiz do monorepo, pega o pubspec do melos.
2. **`package_config.json` só em `<pacote>/.dart_tool/`.** Pacote de `libraries/` fora do melos pode nunca ter tido
   `pub get`: sem ele a CLI não analisa nada.
3. **Acme achado pelas dependências do pacote** (pacote com `lib/connect`). As features dependem do `acme`, não de
   um pacote de mapeamentos.
4. **Config só no pacote.** Teria que ser repetido em cada feature.
5. **CLI instalada por dev apontando para uma pasta fixa** (`tool/install.sh`).

## Proposta: código no design_ops, CLI global

Decidido:
- O código fica em `libraries/design_ops/packages/figma2dart`, ao lado do `acme` e do `acme_templates`.
- **Foco na CLI.** Agente e skills ficam com o time (o `agent/` segue como fonte de referência); a instalação deles
  e a da CLI podem ser tarefas do `Rakefile` do monorepo.

```
<monorepo>/libraries/design_ops/packages/
  acme/  acme_templates/             ← como estão
  acme_figma/                        ← @FigmaConnect do acme e do acme_templates + FigmaPolicy
  figma2dart/                        ← a solução (dono: design ops)
    figma2dart.yaml                  ← config do repo inteiro
    cli/                             ← CLI; cli/tool/figma2dart é o script, cli/tool/figma2dart.rake a tarefa
    figma_connect/  plugin/  agent/
```

```yaml
# libraries/design_ops/packages/figma2dart/figma2dart.yaml
mappings: ../acme_figma        # relativo a este arquivo
screens: lib/figma             # padrão para todo pacote; um pacote pode ter o seu figma2dart.yaml
```

### `figma2dart setup` (uma vez por dev; pode rodar de novo)

```sh
rake figma2dart:setup                                            # de qualquer pasta do repo
libraries/design_ops/packages/figma2dart/cli/tool/figma2dart setup   # o mesmo, sem rake
```

Só a CLI: grava o comando `figma2dart` em `~/.pub-cache/bin/` (já no PATH de quem usa Flutter) e roda o `pub get`
em `cli/`. Nada é escrito nos pacotes dos times; na raiz, só o `rakelib/figma2dart.rake` (cópia de `cli/tool/figma2dart.rake`).

- **O comando global não é uma cópia da CLI:** chama o script do repo, que roda o código de `cli/` (`dart run`, em
  cache: 0,7 s; o "Building…" vai para o stderr, JSON limpo). `git pull` atualiza a CLI para todos sem reinstalar.
- **Nenhum caminho fixo.** O comando global acha tudo pela raiz do git de onde foi chamado:
  1. `git rev-parse --show-toplevel` → raiz do monorepo (qualquer clone ou worktree);
  2. `git ls-files '**/figma2dart.yaml'` (consulta o índice do git, sem varrer o disco) → o que tem `mappings:` é o
     config do repo, e a pasta dele tem o `cli/`; os outros são configs de pacote;
  3. Acme: `mappings:` do config, ou, sem ele, o único pacote com `lib/figma_policy.dart` (`git ls-files` de novo).

  Se o `design_ops` mudar de lugar, nada quebra; quem chama só conhece o comando `figma2dart`. O único caminho
  que alguém digita é o do primeiro `setup`, uma vez (ou fica dentro da tarefa do rake).
- **Melos 6 resolve cada pacote sozinho**, então o `analyzer` 14 da CLI não briga com o `build_runner` do repo.
- **`acme_figma`** depende do `figma_connect` por path (`../figma2dart/figma_connect`).
- **"O pacote usa o Acme"** sai das dependências do `acme_figma` (`acme`, `acme_templates`): nada a configurar.

## Descoberta automática a cada comando

| O quê | Como |
|---|---|
| Config | o `figma2dart.yaml` com `mappings:` achado por `git ls-files`; o de um pacote (opcional) vence |
| Pacote alvo | `--package`, ou o pubspec mais próximo de onde foi chamada (o da raiz e os `example/` não contam) |
| `package_config` | o do pacote; se faltar (pacote fora do melos, nunca teve `pub get`), a CLI roda `flutter pub get` nele, com a saída no stderr. Vale para o `acme_figma` também |
| Acme | `mappings:` do config; senão, o único pacote do repo com `lib/figma_policy.dart` |
| Pasta das telas | config da feature → config do design_ops → pergunta |

**Pacote alvo sem digitar caminho** (o que a CLI oferece ao agente):

1. Arquivo aberto ou citado: o agente passa `--package` com a pasta dele.
2. O usuário cita o setor ou o pacote e o agente roda `figma2dart packages --query cards --json`: busca nos
   `pubspec.yaml` versionados (`git ls-files`, sem varrer o disco: o `grep -r` levou 18 s) pelo caminho e pelo nome,
   e diz se cada um depende do Acme. Um resultado: usa. Poucos: pergunta com opções.
3. Senão, pergunta o setor.

## Tarefas

- [x] CLI: config do repo achado por `git ls-files` (o `figma2dart.yaml` com `mappings:`) + o do pacote, que vence;
      mapeamentos por `mappings:`, pela dependência ou pelo único `lib/figma_policy.dart`; pacote alvo (a raiz do
      melos sem `lib/` não conta); `pub get` automático; `--package`.
      A chave é `mappings:` (genérica), não `acme:`.
- [x] Comando `packages [<texto>]` (marca `ds` pela dependência direta de um pacote do DS).
- [x] `doctor`: repositório e configs lidos.
- [x] Script `tool/figma2dart` (acha a CLI pelo índice do git; `dart run` em cache; volta para a pasta de chamada).
- [x] `setup` (substitui `tool/install.sh`): copia o script para `~/.pub-cache/bin`.
- [x] `tool/figma2dart.rake`: `rake figma2dart:setup` para o `rakelib/` do monorepo (acha a CLI pelo git).
- [x] README da CLI; `agent/` de referência ajustado (`setup`, `packages`, `--package`).
- [ ] `.ps1` se houver Windows.
- [x] ARCHITECTURE §3 e §10.9.
- Fora: versão da CLI × `figma_connect` no `doctor` (os dois vêm do mesmo repo, não divergem); `init` ficou como
  estava (serve ao app só; no monorepo os agentes são do time).

## Verificação

- `test/monorepo_test.dart` (6 testes): repositório git com raiz do melos, `acme`, `acme_figma`, config no
  design_ops e pacotes de setor; config do repo + do pacote; erro da raiz e `--package`; `packages`; Acme por
  `lib/figma_policy.dart`; dois `mappings:` dá erro; `ensurePubGet`; `setup` + script devolvendo JSON limpo.
  Suíte inteira: 54 testes.
- Ponta a ponta num monorepo de teste com os pacotes reais do Carteira (sem nenhum `pub get` antes): `doctor` de
  dentro do pacote (13 mapeamentos, `pub get` automático na CLI e nos mapeamentos), `packages pix` da raiz,
  `resolve --package` da raiz (2 mapeadas, 4 fora do DS, 2 tarefas de componente), `check` com `pub get`
  automático no pacote.
- Tempo: o comando antigo levava ~11 s no `doctor`; o novo ~7 s (~6 s são o analyzer carregando os mapeamentos).

## Decisões em aberto

- Pacotes dos setores dependem do `acme` direto ou por outro pacote (`facade`, `commons/dependencies`)? Muda como o
  `packages --query` diz "usa o Acme".
- **Código no monorepo:** o `libraries/design_ops/packages/figma2dart/` passa a ser a casa do código (este repo vira
  histórico) ou é cópia sincronizada daqui?
- **Windows** no time? Precisa de `.ps1`.
- Pasta padrão das telas nas features (`lib/figma`? a convenção do `cli_bricks`/mason?).
