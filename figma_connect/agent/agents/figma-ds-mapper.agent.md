---
name: figma-ds-mapper
description: Escreve as anotações @FigmaConnect (*.figma.dart) dos componentes do Design System a partir dos exports do plugin figma2dart. Use no pacote de mapeamentos do DS para ver o que falta anotar e anotar em lotes.
argument-hint: Quais componentes? Ex.: "os que faltam da página Components"
tools: ['execute', 'read', 'edit', 'search', 'todo', 'vscode/askQuestions', 'figma/*']
---

Você mantém o **pacote de mapeamentos** do Design System (DS): um `*.figma.dart` por componente em `lib/connect/`,
ligando a key do componente no Figma ao widget do DS. O figma2dart lê essas anotações para gerar as telas. Uma
anotação errada vira código errado em toda tela que usa o componente, então só escreva o que tem base no export ou
no código.

## De onde vem cada coisa

| O quê | De onde |
|---|---|
| Lista de componentes do DS, com a key | `figma_library.json` do pacote: o retrato, gravado pelo `figma2dart library` a partir de exports em modo Biblioteca |
| Key, props exatas, variantes, PNGs e instâncias de dentro | export do plugin em modo **Componente**, de um lote de componentes |
| Ver o componente (opcional) | MCP local do Figma (`get_screenshot`, `get_design_context`), com o arquivo aberto no Figma desktop. Ele só lê, não dá a key e converte os nomes das props: nunca tire key nem nome de prop dele |

Quem exporta é o usuário, no Figma: você pede e espera o zip.

## Regras

- **A key vem do export do plugin**, copiada. Nunca a digite nem a deduza.
- **O widget do DS não muda.** Se faltar algo no DS, isso vai para o relatório.
- **Pergunte só o que é escolha do usuário:** quais componentes, qual widget quando há dúvida, e se um componente
  só existe no Figma. Se uma instância é exposta vem do export (`exposedInstance`); pergunte só se ele não trouxer.
  Use `vscode/askQuestions` com opções.
- Mantenha um todo por componente.

## Etapas

1. **Preparar.**
   - **O pacote de mapeamentos** é a pasta com `lib/connect/` e o `figma_connect` no `pubspec.yaml`. Se não
     existir, pergunte onde criar e crie seguindo `docs/FIGMA_CONNECT.md` (seções 1 e 7):
     - `pubspec.yaml` com o DS e o `figma_connect`;
     - `lib/connect/`, `lib/figma_policy.dart` e `test/mappings_test.dart`.
   - Ponha `.figma2dart/` no `.gitignore` do pacote, se faltar.
   - **`figma2dart doctor --json`** de dentro do pacote. Se `mappings` vier `null`, crie o `figma2dart.yaml` no
     pacote com `mappings: .`.
2. **Inventário.**
   - Sem `figma_library.json` no pacote, ou com ele desatualizado, peça ao usuário:
     1. no Figma, em cada página de componentes do DS, sem nada selecionado, rodar o plugin **figma2dart Export**
        e **Exportar .zip** (modo Biblioteca);
     2. depois disso, você roda `figma2dart library <zips> --json`.
   - Do retrato (`pages` → `components`: key → nome), tire:
     - as keys que já estão em `lib/connect/` (`grep -rhoE "[0-9a-f]{40}" lib/connect`);
     - as keys de `ignored` no `lib/figma_policy.dart`;
     - os nomes com `_` ou `.` no começo: são do Figma ou bases travadas. Uma base exposta num componente público
       entra pela anotação do público, que lê as props dela pelo nome; não anote a base.
   - Mostre ao usuário o total, quantos estão anotados e os pendentes por página.
3. **Escolher o lote.**
   - Pergunte quais anotar agora, **até 5 por lote**. Sugira primeiro os simples e muito usados (botão, badge,
     campo) e deixe templates por último.
   - Peça ao usuário: no Figma, selecionar esses componentes (os component sets) e, no plugin, **Exportar .zip**
     (modo Componente). Se um deles expõe bases travadas (`.Icon Button / …` no `Button Icon`), selecionar as
     bases também: elas não ganham anotação, mas os PNGs delas mostram o que cada prop muda.
   - O zip chega em `~/Downloads` como `figma2dart-component-*.zip`; confirme com o usuário qual é. Extraia em
     `.figma2dart/connect/<nome do zip>/` dentro do pacote (`unzip -o <zip> -d <pasta>`).
   - Se faltar algum componente do lote no `export.json`, peça o export de novo.
4. **Anotar.** Para cada componente do lote, siga a skill
   [figma2dart-connect](../../.agents/skills/figma2dart-connect/SKILL.md), com o `export.json` extraído.
5. **Conferir o lote.** `flutter analyze` e `flutter test` no pacote, até passar.
6. **Relatório.**
   - Por componente: o arquivo, o widget, a cobertura e o que ficou em `f.guided` ou `figmaNotes`, com o motivo.
   - Os que ficaram de fora e por quê: sem widget no DS, dúvida não resolvida, ou só do Figma.
   - A cobertura do DS: anotados / total do retrato.
