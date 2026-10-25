---
name: figma2dart-component
description: Constrói um widget Flutter que existe no Figma mas não no Design System, a partir do brief de construção do figma2dart (components/<nome>/BRIEF.md). Use quando o usuário escolher construir um componente fora do DS.
---

# Construir um componente fora do DS

Entrada: o `BRIEF.md` do componente, o arquivo a criar (`widgetFile`), a classe, a `key` e o `name` no Figma e o
pacote.

## 1. Ler

- O brief inteiro e o PNG de cada variante (tabela "Variantes"), quando houver.
- **API proposta:** o construtor tirado das props do Figma, mais um parâmetro para cada prop de instância exposta
  que muda entre os usos (ex.: `avatarInitials`). Use como base; ajuste só o que o uso exige.
- **Estrutura:** uma linha por camada. Layout e estilo pelos tokens (em Dart, ou pelo nome do Figma sem tabela); textos com `← prop` são parâmetros;
  `DS \`…\`` é o código pronto da instância do DS (o `L×A` no fim é o tamanho no Figma: passe-o se o padrão do
  widget for outro); **exposta** recebe o valor do parâmetro, não o do exemplo; link para outro brief é outro
  componente local (construa antes). Tamanho `L×A`: número = fixo, `HUG` = conteúdo, `FILL` = `Expanded`/largura
  total.
- **O que muda em cada variante:** só as diferenças da base (`antes → agora`): é o que o enum da variant decide no
  `build`.
- **SVG** na pasta do brief (componente só de vetor): use como asset, com o que o app já usa para SVG.
- **Usos na tela:** os valores que a tela passa. Confira que a API cobre todos.

## 2. Escrever

- `widgetFile`, `StatelessWidget`, com doc de uma linha na classe e em cada parâmetro.
- Componha com os widgets do DS (copie o código das instâncias do DS da estrutura) e só tokens do DS. Os tokens já
  vêm em Dart quando o DS tem tabela de tokens (`DsSpacing.md`, `context.acmeSpacing.md`; do tema: dentro do
  `build`, sem `const`); com o nome do Figma (`Spacing/md`) ou `(sem Dart, valor)`, ache a constante com `search` no
  pacote do DS ou use a mais próxima com `f2d:inferred`.
- Variant do Figma vira enum (como na API proposta) e muda o `build` conforme a estrutura de cada variante.
- Callback (toque, mudança) não existe no Figma: adicione só se a camada parece interativa (botão, item com
  chevron) e marque `// f2d:inferred — <motivo>`.
- Texto sem `← prop` é fixo no componente.
- `TODO(f2d)` na estrutura (ícone fora do DS, imagem ou vetor sem arquivo): copie o valor provisório com o
  comentário; não invente asset.

## 3. Testar e conferir

- Um teste de widget por variante em `test/` espelhando o caminho do widget: renderiza com os valores de "Usos na
  tela" e confere os textos.
- `figma2dart check <widgetFile> --json` até `"ok": true` e `flutter test <arquivo do teste>` passando. Leia os
  `hints` (não reprovam): valor solto (a dica traz o token), parâmetro da API proposta que não está no construtor,
  texto fixo do Figma que não aparece. Corrija ou explique com `// f2d:inferred — <motivo>`.

## 4. Ligar ao Figma

`figma2dart link <key> <widgetFile>#<classe> --name "<name>" --json`. Escreve o `@FigmaLocal` em `figma/connect/` do
pacote (e o `figma_connect` nas dev_dependencies, se faltar): daí em diante o `resolve` manda **montar** este widget
em vez de construir outro.

## Não fazer

- Usar cor, tamanho ou espaçamento solto.
- Recriar um componente do DS (Button, Badge…): use o do DS.
- Copiar dados de exemplo do Figma como valor fixo de parâmetro.
