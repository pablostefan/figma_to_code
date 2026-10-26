---
name: figma2dart-review
description: Revisão visual de uma tela implementada contra o Figma: captura com figmaCapture, figma2dart review e o subagente figma-visual-reviewer. Use depois do check ok de uma tela.
---

# Revisão visual da tela

Entrada: o item da tela em `tasks` do `figma2dart resolve --json` (`screen`, `brief`, `screenFile`) e a tela já com
o `check` ok. A revisão não reprova nada: é para deixar a tela o mais parecida possível com o Figma no que importa.

## 1. Capturar

1. `figma2dart review --screen "<screen>" --json`. Sem captura ainda, volta `"capture": false` com `testFile` (onde
   criar o teste) e `test` (o modelo). O `figma_connect` já fica nas dev_dependencies (`devDependency` diz se
   precisou adicionar).
2. Escreva o `testFile` completando o modelo: a tela do `screenFile` dentro do `MaterialApp` com o **mesmo tema do
   app** (o do `main.dart`) e os **dados de exemplo do Figma** (os textos do brief), sem back-end: parâmetros, um
   cubit com estado fixo ou um repositório falso. Imagem de rede fica como está.
3. `flutter test <testFile>`, **de dentro da pasta do pacote** (`app` do `doctor`): o `figmaCapture` acha a tarefa
   por `.figma2dart/tasks/` a partir dela. Overflow não reprova (vai para a revisão). Se o teste falhar por outro motivo,
   corrija o **teste** (dados, tema, dependência), não a tela. O teste fica no repositório: é o teste de widget da
   tela. Em outra máquina ou na CI (sem `.figma2dart/`, que não é versionado), ele passa sem capturar.

## 2. Revisar

1. `figma2dart review --screen "<screen>" --json` → `review` (o `REVIEW.md`), `screen`, `sections`, `facts`.
2. Delegue ao subagente `figma-visual-reviewer` com o caminho do `REVIEW.md` e do `brief`. Não revise você mesmo:
   quem escreveu a tela tende a não ver o que errou.
3. Resposta `Imagens abertas: não` → a ferramenta não lê imagem: pare a revisão e diga no relatório; os `facts`
   (texto ausente, fora de ordem, overflow) ainda valem como dica.

## 3. Corrigir

- Cada achado traz a **base** (a linha da estrutura ou do brief) e a **correção**. Corrija pela base, com os tokens
  e widgets do brief.
- Achado que é dado de exemplo ou decisão sua (não erro): deixe `// f2d:inferred — <motivo>` na linha e siga.
- Depois de corrigir: `figma2dart check` (até `"ok": true`), `flutter test <testFile>`, `review` e o revisor de
  novo. **No máximo 2 rodadas**; o que sobrar vai para o relatório.

## 4. Relatar

Por tela: os achados corrigidos, os que ficaram (com o motivo) e o caminho de `review/screen.png` para a pessoa
conferir.
