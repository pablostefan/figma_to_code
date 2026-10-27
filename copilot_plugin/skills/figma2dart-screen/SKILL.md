---
name: figma2dart-screen
description: Implementa uma tela Flutter a partir do BRIEF.md gerado pelo figma2dart resolve, usando os widgets e tokens do Design System. Use para escrever ou corrigir o arquivo de uma tela vinda do Figma.
---

# Implementar a tela a partir do brief

Entrada: o item da tela em `tasks` de `figma2dart resolve --json` (`brief`, `image`, `screenFile`, `components`) e
as escolhas do usuário sobre os componentes fora do DS.

## 1. Ler

- Leia o `BRIEF.md` inteiro e abra o PNG (`image`): é a referência visual.
- Seções do brief:
  - **Componentes:** o código de cada instância do DS, já com os valores do Figma.
  - **Esqueleto da tela:** o que toda tela do DS tem por fora. É um modelo do pacote de mapeamentos (`@FigmaScreen`,
    `FigmaScreenProps`, que **não existem no app**: não copie a anotação nem a função). Copie o **corpo** dela para o
    `build` da página, trocando `s.body()` pelo layout da "Estrutura da tela" e `s.instance(x)` pela instância
    (ou nada).
  - **Estrutura da tela:** o layout (frames, direção, gap, padding, tokens) e onde cada instância fica.
  - **Navegação:** o protótipo do Figma; diz para onde cada botão leva.
  - **Decisões (f2d:guided):** o que você decide, com o norte.
  - **Componentes desta tela:** regras, trechos dos docs e exemplos do DS. Siga.
- Antes de escrever, veja uma tela parecida no app (mesma pasta) para seguir as convenções: estado, navegação,
  nomes.

## 2. Escrever

- Arquivo: `screenFile`. Se já existir, pergunte ao usuário antes de sobrescrever.
- Classe `<Nome>Page`, com o corpo do "Esqueleto da tela" do brief por fora (sem esqueleto, um `Scaffold` simples).
- **Layout:** monte a árvore da "Estrutura da tela" com `Column`/`Row`/`Padding`/`Expanded`. Direção, gap, padding
  e alinhamento vêm dela. `FILL` vira `Expanded`/largura total; `spacer` com `FILL` vira `Spacer()`/`Expanded`.
- **Tokens:** com a tabela de tokens do DS, a estrutura já traz o código Dart (`DsSpacing.md`,
  `context.acmeColors.textPrimary`): use como está. Token do tema (`context.…`) só dentro do `build` e tira o `const`
  de quem o usa. `(sem Dart, valor)` é token sem correspondência: use o mais próximo e marque `f2d:inferred`. Sem
  tabela, a estrutura traz o nome do Figma (`Spacing/md`): ache a constante com `search` no pacote do DS (o nome do
  Figma costuma estar no comentário). Nunca número ou cor solta.
- **Textos:** `texto → <código>` já é o widget e a tipografia do DS (`AcmeText('Entrar', type: …)`): use como está,
  nunca `Text`/`TextStyle` do Flutter. Sem o `→`, o texto vem descrito (estilo e cor): use o widget de texto do DS,
  se houver, com esse estilo.
- **Instâncias do DS:** copie o código da seção Componentes como está. Só mude o que tem marcador.
- **`/* f2d:guided Gn parte */ valor`:** decida com o norte, a navegação e as regras. Troque o valor e **apague o
  marcador**. Se decidiu sem base no brief, deixe `// f2d:inferred Gn — <motivo>` na linha.
- **`f2d:gap`:** resolva com o widget do DS mais próximo e marque `// f2d:inferred — <motivo>`.
- **`f2d:sketch` (componente do DS a montar) e `f2d:local` (widget do app que já existe, `@FigmaLocal`):** o
  placeholder aponta para o brief da tarefa (`components/<nome>/BRIEF.md`, `"kind": "sketch"`/`"local"` no JSON,
  com o `import`). Widget do app não se altera sem perguntar ao usuário. Leia-o: tem o norte, a **API do widget** (construtor,
  parâmetros e tipos auxiliares), os dados de cada instância no Figma (props, expostas, o **conteúdo de dentro** e o
  **recorte do PNG** só daquela instância — abra a imagem), docs e exemplos. Troque o placeholder pelo
  widget montado com essa API: valores do Figma entram como estão; conteúdo de exemplo (linhas, itens) vem dos dados
  da tela. Apague o marcador e deixe `f2d:inferred` no que decidiu.
- **Navegação:** use o mecanismo de navegação que o app já usa. Destino que ainda não existe no app: deixe uma ação
  vazia com **exatamente** `// f2d:inferred — tela <nome> ainda não existe` (o agente procura esse texto para ligar
  a navegação depois que a tela de destino for escrita).
- **Placeholders (`f2d:placeholder`):**
  - Componente construído → troque o placeholder pela classe, com os valores de "props" da estrutura (ou de "Usos
    na tela" no brief do componente). Importe de `widgets/`.
  - Componente ligado com `figma2dart link` depois do `resolve` → rode o `resolve` de novo: ele vira `f2d:local`.
  - Senão → mantenha o placeholder do brief como está.
- **`TODO(f2d)`** (ícone que não existe no DS, imagem ou vetor sem arquivo): mantenha o valor provisório e o
  comentário como estão. É pendência do dev, não invente asset.
- Itens "Não implementar" do brief são do Figma só (anotações, bases): não entram na tela.
- Texto e dados de exemplo do Figma (nomes, valores) viram parâmetros ou estado da tela quando o brief ou o doc
  disser que vêm de dados; senão, ficam como no Figma.

## 3. Conferir

`figma2dart check <screenFile> [widgets] --json`. Corrija cada item de `markers` bloqueante (`guided`, `gap`,
`sketch`, `local`) e cada `analyze` de severidade `error` ou `warning`. Repita até `"ok": true`.

Depois, os **`hints`** (dicas; não reprovam). Cada um traz a sugestão; decida caso a caso:

- `value`: número ou cor solta. A dica diz o token do mesmo valor (`→ use DsSpacing.md`): troque. Sem token
  equivalente, deixe `// f2d:inferred — <motivo>` na linha (cala a dica).
- `widget`: um componente a montar (`sketch`/`local`) sumiu sem virar o widget esperado.
- `text`: texto do Figma que não aparece no código. Se vem de dados ou de tradução, siga em frente.

## Não fazer

- Alterar widgets do DS ou criar variações deles.
- Criar widgets novos além dos que o usuário escolheu construir.
- Inventar valor que o Figma tem: texto, ícone, variante e cor vêm do brief.
