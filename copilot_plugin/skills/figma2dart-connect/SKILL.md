---
name: figma2dart-connect
description: Escreve a anotação @FigmaConnect (*.figma.dart) de um componente do Design System a partir do export de componentes do plugin figma2dart e do código do widget. Use para anotar componentes do DS no pacote de mapeamentos.
---

# Anotar um componente do DS

Entrada:
- o `export.json` de um export de componentes do plugin, já extraído, com a pasta `images/` ao lado;
- o nome do componente;
- o pacote de mapeamentos (o que tem `lib/figma_policy.dart`).

Referência da API: `docs/FIGMA_CONNECT.md` do repositório do figma2dart. O `figma_connect` do `pubspec.yaml` do
pacote aponta para ele; o doc fica em `<figma_connect>/../docs/`. As anotações que já existem em `lib/` (`*.figma.dart`) são
o modelo: siga o estilo delas.

## 1. Ler o export

O export do plugin é a fonte da **key** e dos **nomes exatos das props**. A anotação lê as props pelo nome do Figma
(`f.text('Show icon')`, não `showIcon`).

- **Achar o componente:** `grep -n '"name": "<componente>"' export.json`. O objeto dele, dentro de `components`,
  tem `"role": "exported"` e os campos nesta ordem:
  - `key`: copie exatamente; nunca digite nem deduza;
  - `name` e `description`;
  - `props`: nome → `type` (`TEXT`, `BOOLEAN`, `VARIANT`, `INSTANCE_SWAP`), `default` e, nas VARIANT, `options`;
  - `variants`: cada uma com as `props` (a combinação de variant) e a `image` (o PNG, em `images/`).
- **Abrir os PNGs** das variantes, para ver o que muda entre elas.
- **Instâncias de dentro:** na `tree` da primeira variante, cada nó `"type": "INSTANCE"`.
  - O **caminho** é o nome das camadas desde a raiz da variante, sem incluir a raiz (ex.: `field/trailingAction`).
    É esse caminho que vai em `f.nested` e `f.instance`.
  - `instance.componentName` diz qual componente é; `instance.props` traz os valores.
  - `instance.exposedInstance: true`: a instância está **exposta**, e as props dela aparecem em toda instância do
    componente. Sem essa marca, ela não chega à tela.
  - A **definição** de cada componente de dentro (props com tipo e `options`) está em `componentRefs`, pela
    `instance.componentKey`.
- **Export com o público e as bases** (o usuário selecionou o `Button Icon` e as `.Icon Button / …`): todos vêm em
  `components` com `"role": "exported"`, mas só o **público** (nome sem `.` ou `_` no começo) é anotado. As bases
  servem de fonte: as props delas e os PNGs, que mostram o que cada opção muda.
- **INSTANCE_SWAP:** em `props`, o `default` é o id de um nó, não o nome. O ícone padrão está na instância
  correspondente da `tree` (`instance.componentName` e `variant`, ex.: `{"name": "mail"}`).
- **MCP local do Figma (opcional):** com o arquivo do DS aberto no Figma desktop, `get_screenshot` e
  `get_design_context` com o `id` do componente ajudam a entender o comportamento. Nunca tire do MCP a key nem o
  nome de uma prop: ele não dá a key e converte os nomes.

## 2. Achar o widget

- Procure a classe no pacote do DS, que é dependência do pacote de mapeamentos:
  - pelo nome, com o mesmo prefixo das anotações que já existem (`Button` → `DsButton`);
  - pela `description` do Figma.
- Leia todos os construtores (os nomeados e as factories também), os enums dos parâmetros e o doc da classe.
  Construtores com o nome das opções de uma VARIANT (`primary`, `secondary`) indicam que a prop troca o construtor
  (seção 3).
- Se houver dois candidatos ou nenhum, **pergunte**; não adivinhe.
- Se não houver widget no DS, não anote. Relate como "só no Figma" ou como falta no DS.

## 3. Ligar cada prop a um parâmetro

Monte esta tabela antes de escrever, com uma linha por prop do Figma:

| Prop do Figma | Vira |
|---|---|
| TEXT | `f.text('label')` |
| BOOLEAN | `f.boolean('x')`. Se só mostra ou esconde outra prop: `f.boolean('showIcon') ? f.icon('icon') : null` |
| VARIANT | `f.variant('size', {'md': DsXSize.md, …})`, com **todas** as `options`. Opção que é estado vira o valor de outro parâmetro: `'disabled'` → `onPressed: null`, `'error'` → `errorText` |
| INSTANCE_SWAP de ícone | `f.icon('icon')`. O nome do Figma em camelCase (`arrow-up-right` → `arrowUpRight`) acha o valor na tabela de ícones da política |
| INSTANCE_SWAP de outra coisa | `f.instance('x')` |
| Prop de uma instância **exposta** (o painel do Figma mostra junto com as do componente) | pelo nome, direto: `f.variant('✏️ Type', …)`. A CLI procura a prop no componente e, se não achar, nas expostas. Só use `f.nested('<caminho>').text('label')` quando duas expostas têm a mesma prop. Use `f.instance('<caminho>')` quando o widget recebe o widget pronto |
| Prop sem parâmetro no código | `figmaNotes`: `FigmaNote.ignore('<motivo>')` (só visual, ou só vale noutra variant), `.derive('<como>')` ou `.map({...})` |
| Parâmetro sem prop (callback, acessibilidade, controller) | `f.guided('onPressed', guide: '<o que a tela decide>', or: <valor neutro>)`, só se for obrigatório ou mudar o que se vê. Parâmetro opcional sem efeito no Figma fica de fora |

- **Só instância exposta pode ser lida** (`exposedInstance: true` na `tree`). Fora isso, a instância não chega à
  tela. Export de um plugin antigo não traz a marca: aí pergunte ao usuário. Na dúvida, não leia.
- **Base travada** (o `Button Icon` só tem `👉 Size` e expõe uma base por tamanho, `.Icon Button / Large`, `/ Medium`
  e `/ Small`, cada uma com a sua key):
  - **uma anotação só, na key do público**, lendo o `👉 Size` dele e as props da base pelo nome;
  - **as bases não ganham anotação:** o nome delas começa com `.`, e o público cobre todos os tamanhos.

  ```dart
  @FigmaConnect(key: '<key do Button Icon>', name: 'Button Icon')
  Widget buttonIcon(FigmaProps f) => AcmeIconButton(
    size: f.variant('👉 Size', {'Large': …, 'Medium': …, 'Small': …}),
    type: f.variant('✏️ Type', {…}),       // da base exposta
    icon: f.icon('🔄 Icon'),               // da base exposta
  );
  ```
- **Prop que troca o construtor, a factory ou o widget** (o `✏️ Type` da base escolhe `AcmeIconButton.primary`,
  `AcmeIconButton.secondary` ou outro widget). O usuário pode avisar ("o Button Icon troca de construtor pelo
  `✏️ Type`"); sem o aviso, desconfie quando o widget tem construtores nomeados ou factories com o nome das opções
  de uma VARIANT, ou quando uma opção é outro widget, e confirme com o usuário. Use `f.variant` **na raiz**, com o
  widget inteiro em cada opção; a CLI troca só o ramo escolhido. Vale para prop do componente ou da base exposta:

  ```dart
  @FigmaConnect(key: '<key do Button Icon>', name: 'Button Icon')
  Widget buttonIcon(FigmaProps f) => f.variant('✏️ Type', {
    'Primary': AcmeIconButton.primary(notification: f.boolean('🔔 Notification')),
    'Secondary': AcmeIconButton.secondary(notification: f.boolean('🔔 Notification')), // factory
    'Ghost': const AcmeGhostButton(),                                               // outro widget
  });
  ```

  - Todas as `options` da VARIANT entram, cada uma com o seu widget.
  - Prop que só vale em parte dos ramos é lida só neles; a que não vale em nenhum vai em `figmaNotes`.
  - Se for BOOLEAN: `f.boolean('x') ? A.foo(…) : B(…)`.
- **Variant que troca o widget e muda muito entre os casos** (notas, cobertura ou `guide` próprios; `type=icon` →
  `DsAvatar.icon`): uma função por caso, com a mesma `key` e `when: {'type': 'icon'}`. O `when` só vê as props do
  próprio componente; se a prop for da base exposta, use o `f.variant` na raiz. As props que não valem naquele caso
  vão em `figmaNotes`.
- **Prop que o widget calcula sozinho** (o tom do Badge sai do `direction`): `FigmaNote.ignore` com o motivo.

## 4. Escolher a cobertura

- **`complete`** (padrão): toda prop é lida ou tem `FigmaNote`.
- **`partial`**: parte do conteúdo é exemplo ou depende da tela (as linhas de uma lista).
  - Use `f.guided` para essa parte e escreva o `guide`.
  - Bloco composto leva `kind: FigmaKind.section`.
- **`sketch`**: o conteúdo são camadas, não props (template de tela). Use `@FigmaConnect.sketch(…, guide: …)` sobre
  um `typedef` para o widget, sem função.
- Template e bloco composto pedem `guide`; docs e um `Example.code` ajudam a LLM onde ela mais erra.

## 5. Escrever

1. **`lib/<pasta que espelha o DS>/<arquivo do widget>.figma.dart`**: o mesmo caminho do widget no DS, como as
   anotações que já existem (`AcmeButton` em `acme/components/button/` → `lib/acme/components/button/acme_button.figma.dart`).
   A CLI lê qualquer `*.figma.dart` de `lib/`. Sem padrão no pacote ainda, pergunte ao usuário:
   - imports do DS, do `figma_connect` e de `flutter/widgets.dart`;
   - doc de uma linha: ``/// Figma `Name` → [DsWidget]. <o que não é óbvio>``.
2. **`docs/<arquivo>.md`**, só se houver `f.guided`, `partial`, `sketch` ou uma armadilha conhecida:
   - `## Geral`, uma seção `## <parte>` por parte guiada e `## Erros comuns` (com ❌);
   - sem repetir o construtor nem as props, que a CLI já lê.
3. **README do pacote:** uma linha na tabela de mapeamentos.
4. **`test/mappings_test.dart`**, se existir:
   - em `defaults`, os valores padrão do Figma (o `default` de cada prop). Para ícone, use só o nome que está na
     `tree` (`'mail'`). Prop lida de uma exposta pelo nome entra em `defaults` como as outras, com o padrão dela
     (está em `componentRefs`). Com `f.nested`, a exposta é um mapa com as props dela;
   - se o teste tem um mapa `icons` (ícones como constantes de uma classe, como no Acme), acrescente nele cada
     ícone usado em `defaults`: `'home': acme.AcmeIcons.home`;
   - em `variantOptions`, todas as `options` de cada VARIANT;
   - `sketch` não entra (não tem função).

## 6. Conferir

1. **Nomes contra o export.** O `mappings_test` usa os nomes que você escreveu, então não pega um emoji errado.
   Liste as props que a anotação pode ler, com as opções, e confira cada `f.text`, `f.boolean`, `f.variant`,
   `f.icon` e `f.instance` da anotação, letra por letra (emoji incluso), e cada opção dos `f.variant`:

   ```sh
   N='Button Icon'  # o público
   jq -r --arg n "$N" '.components[] | select(.name == $n) | .props | to_entries[]
     | "\(.key)\t\(.value.options // [] | join("|"))"' export.json
   jq -r --arg n "$N" '. as $r | [.components[] | select(.name == $n) | .variants[].tree | .. | objects
     | select(.instance.exposedInstance?) | .instance.componentKey] | unique[] | $r.componentRefs[.].props
     | to_entries[] | "\(.key)\t\(.value.options // [] | join("|"))"' export.json | sort -u
   ```

   O primeiro dá as props do componente; o segundo, as das instâncias expostas.
2. `flutter analyze` e `flutter test`, de dentro do pacote, até passar.
   - "variant x=y sem mapeamento": falta essa opção no `f.variant`.
   - "prop ausente no teste": falta o valor em `defaults`.

## Não fazer

- Alterar o widget do DS.
- Inventar key, nome de prop, opção de variant ou parâmetro.
- Usar `f.guided` para algo que o Figma tem: vira lacuna em toda tela.
- Copiar o texto de exemplo do Figma (o padrão da prop) como valor fixo no código.
