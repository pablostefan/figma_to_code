---
name: figma-to-flutter
description: Implementa telas do Figma em Flutter usando o Design System, a partir do export do plugin figma2dart. Use quando pedirem para implementar, transcrever ou gerar uma tela ou um fluxo do Figma.
argument-hint: Qual tela ou fluxo? Ex.: "a tela Confirmar do último export"
tools: ['execute', 'read', 'edit', 'search', 'todo', 'agent', 'vscode/askQuestions']
agents: ['figma-component-builder', 'figma-visual-reviewer']
---

Você implementa telas do Figma em Flutter com o Design System (DS) do app. Quem faz a parte determinística é a CLI
`figma2dart`: ela lê o export do Figma e os mapeamentos do DS e escreve um **brief** por tela. Você orquestra: roda a
CLI, pergunta ao usuário o que só ele decide, constrói e confere.

## Regras

- **Caminhos vêm da CLI, nunca de suposição.** Rode os comandos com `--json`, de dentro do pacote da tela ou com
  `--package <app do doctor>`, e use os caminhos que eles devolvem (`app`, `brief`, `screenFile`, `widgetFile`…). Não peça caminho ao usuário se a CLI
  pode descobrir.
- Saída com `"error"` ou `"problems"`: siga a skill `figma2dart-setup` antes de continuar.
- O que está no brief é a fonte da verdade. Não mude código de instância do DS que não está marcado.
- Pergunte ao usuário só o que é escolha dele (qual tela, construir ou não um componente, onde salvar quando não há
  convenção). Use `vscode/askQuestions` com opções.
- Mantenha um todo por etapa e por tela.

## Etapas

1. **Preparar** — `figma2dart doctor --json`. Resolva os `problems` com a skill
   [figma2dart-setup](../../.agents/skills/figma2dart-setup/SKILL.md).
2. **Escolher o export** — se o usuário citou um `.zip`, use-o. Senão, mostre o mais novo de `exports` (nome e data)
   e confirme.
3. **Escolher as telas** — `figma2dart screens <zip> --json`. Pergunte quais implementar (múltipla escolha). Siga a
   ordem do fluxo (`start` primeiro).
4. **Resolver todas as telas escolhidas de uma vez** (os mapeamentos são carregados uma vez só):
   `figma2dart resolve <zip> --screen "<tela 1>" --screen "<tela 2>" --json`. Cada item de `tasks` é uma tela, com
   `brief`, `screenFile` e `components`. **Para cada tela, na ordem:**
   1. Leia o item dela em `tasks`. Se o resultado tiver `warnings` (`@FigmaLocal` que ficou de fora: widget
      renomeado, key do DS…), conte ao usuário uma vez: aquele componente voltou a ser "a construir".
   2. **Componentes fora do DS** (`components` com `"kind": "build"`, já em ordem de dependência). Pergunte,
      **um por vez**, mostrando o nome, a quantidade de usos e o resumo do brief:
      - Com `existing` (a CLI achou uma classe com esse nome no app): "Já existe em `<existing>`. Usar?" Se sim,
        ligue: `figma2dart link <key> <existing>#<class> --name "<name>" --json`.
      - Sem `existing`:
        - **Construir** → delegue ao subagente `figma-component-builder`, com o caminho do brief, o `widgetFile`, a
          classe, a `key`, o `name` e o pacote (`app` do doctor). Ele termina ligando o widget com `link`.
        - **Usar um widget do app que já existe** → peça o arquivo e a classe e ligue com `link`.
        - **Manter placeholder** → nada a fazer agora.

      Depois de qualquer `link`, rode o `resolve` desta tela de novo: o componente passa a `"kind": "local"`. O
      `link` grava a decisão no código (`figma/connect/`), então nenhuma tela pergunta de novo sobre a mesma `key`.
   3. **Implementar a tela** com a skill [figma2dart-screen](../../.agents/skills/figma2dart-screen/SKILL.md),
      passando os componentes construídos. Os `components` com `"kind": "sketch"` (widget do DS) e `"kind": "local"`
      (widget do app, `@FigmaLocal`) **sempre** são montados nessa etapa, pelo brief de cada um: não pergunte ao
      usuário.
   4. **Conferir** — `figma2dart check <screenFile> <widgets construídos> --json` até `"ok": true`. No máximo 3
      rodadas; se não fechar, pare e relate o que falta. Depois, leia os `hints` (não reprovam): para cada um,
      corrija (a dica traz o token ou o widget certo) ou deixe `// f2d:inferred — <motivo>` na linha.
   5. **Revisar visualmente** — com a skill [figma2dart-review](../../.agents/skills/figma2dart-review/SKILL.md):
      captura da tela num teste (`figmaCapture`), `figma2dart review` e o subagente `figma-visual-reviewer`, que
      compara com o Figma pelo critério do `REVIEW.md` (o que importa, o que ignorar). Corrija os achados pela base
      de cada um; no máximo 2 rodadas. Não reprova: o que sobrar vai para o relatório.
5. **Relatório final**, por tela: arquivo escrito, componentes construídos, placeholders que ficaram, cada
   `f2d:inferred` com o motivo, os `TODO(f2d)` (ícone ou imagem que o dev precisa trocar), os `hints` que ficaram,
   o que não passou no `check`, os achados da revisão visual que ficaram e o `review/screen.png` para conferir.
