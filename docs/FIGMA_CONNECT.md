# `@FigmaConnect` — referência da anotação

Como ligar um componente do Figma a um widget Dart, e como orientar a LLM quando essa ligação não é
determinística. Para quem escreve e revisa os mapeamentos (time do DS).

Os tipos estão no pacote [`figma_connect/`](../figma_connect/); como a CLI usa as anotações para resolver uma tela,
em [ARQUITETURA.md §4](ARQUITETURA.md#4-como-uma-tela-é-resolvida). Nos exemplos, os nomes do Acme (`AcmeListPage`,
`AcmeFilterChip`…) são ilustrativos.

---

## 1. Ideia geral

- **Um arquivo `*.figma.dart` por componente**, no pacote de mapeamentos (`acme_figma`). **O widget do DS não é
  alterado.**
- **A função anotada é um template:** a CLI lê a função e troca cada `f.*` pelos valores que a instância usa no
  Figma; o código resultante vai para o brief da tela.
- **O que é determinístico, a anotação resolve.** O que não é, ela orienta: deixa um **norte** (`guide`,
  `f.guided`, notas, docs e exemplos) e a LLM implementa, marcando o que decidiu.
- **A anotação é o índice do componente.** Norte, docs, exemplos e regras ficam num lugar só; a CLI junta no brief
  só o que a tela precisa.

Onde ficam os arquivos:

```
acme_figma/
  lib/<pasta do DS>/<widget>.figma.dart   ← as anotações, em qualquer pasta de lib/ (espelhando o DS)
  lib/figma_policy.dart                   ← tokens, ícones, ignorados, regras por tipo
  docs/<widget>.md                        ← docs opcionais por componente
  test/mappings_test.dart                 ← cada anotação com os valores padrão e as opções do Figma
  figma_library.json                      ← retrato do DS no Figma
```

Exemplos de implementação (`Example.code`) ficam num pacote à parte que compila, sem regra de negócio (no POC,
`carteira_ds_examples`).

---

## 2. Do mínimo ao completo

**Componente simples e totalmente coberto** (a maioria): só `key`, `name` e o corpo.

```dart
// carteira_ds_figma/lib/connect/ds_badge.figma.dart (POC)
@FigmaConnect(key: 'b3e1…', name: 'Badge')
Widget badge(FigmaProps f) => DsBadge(
  label: f.text('label'),
  tone: f.variant('tone', {
    'neutral': DsBadgeTone.neutral,
    'success': DsBadgeTone.success,
    'danger': DsBadgeTone.danger,
  }),
);
```

**Template com cobertura parcial:** usa todos os campos.

```dart
// carteira_ds_figma/lib/connect/lista_com_filtro.figma.dart
@FigmaConnect(
  key: '9f2c…',
  name: 'Template / Lista com filtro',
  kind: FigmaKind.template,
  coverage: Coverage.partial,
  guide: 'Lista paginada. Filtros, células e refresh dependem da feature.',
  figmaNotes: {
    'state': FigmaNote.derive('Não existe no código: o vazio vem de items: [] + empty:'),
    'Collapse': FigmaNote.ignore('Só visual no Figma'),
  },
  devNotes: [
    DevNote.prefer('Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.'),
  ],
  docs: [
    Doc.path('carteira_ds_figma/docs/templates/lista_com_filtro.md', hint: 'Visão geral e erros comuns do template'),
    Doc.link('https://ds.empresa/docs/paginacao',
        source: 'carteira_ds_figma/docs/paginacao.md',
        hint: 'Ler se a lista vem da API: regras de paginação e refresh'),
  ],
  examples: [
    Example.code('carteira_ds_examples/lib/templates/lista_com_filtro.dart',
        symbol: 'ListaComFiltroBasica', hint: 'Caso padrão: lista da API com filtros e refresh'),
    Example.usage('lib/features/extrato/extrato_page.dart',
        symbol: 'ExtratoPage', repo: 'extrato-app', hint: 'Uso real com paginação e AcmeContext da feature'),
  ],
)
Widget listaComFiltro(FigmaProps f) => AcmeListPage(
  title: f.text('Title'),
  header: f.slot('header'),
  itemBuilder: f.guided('itemBuilder',
    guide: 'A primeira célula do Figma é o modelo; as outras são só exemplo.',
    or: (_) => const SizedBox.shrink()),
  filters: f.guided('filters',
    guide: 'Cada Flag exposta vira AcmeFilterChip; Disabled → enabled: false.',
    docs: [
      Doc.path('carteira_ds_figma/docs/templates/lista_com_filtro.md', section: 'filters',
          hint: 'Regra da moeda Global e do limite de 3 chips'),
    ],
    examples: [
      Example.code('carteira_ds_examples/lib/templates/lista_com_filtro.dart',
          symbol: 'ListaComMuitosFiltros', hint: 'Quando há mais de 3 filtros'),
    ],
    or: const []),
  onRefresh: f.guided('onRefresh',
    guide: 'Só existe no código. Obrigatório se a lista vem da API: chamar o refresh do cubit.',
    or: () async {}),
);
```

Todos os campos além de `key` e `name` têm valor padrão. A anotação só cresce onde o componente é difícil.

---

## 3. Campos do `@FigmaConnect`

```dart
class FigmaConnect {
  const FigmaConnect({
    required String key,
    required String name,
    FigmaKind kind = FigmaKind.component,
    Map<String, String> when = const {},
    Coverage coverage = Coverage.complete,
    String? guide,
    Map<String, FigmaNote> figmaNotes = const {},
    List<DevNote> devNotes = const [],
    List<Doc> docs = const [],
    List<Example> examples = const [],
  });
}
```

| Campo | Para quê | Padrão |
|---|---|---|
| `key` | identidade: key do component set (ou do componente, sem variants). Ver 3.1 | obrigatório |
| `name` | nome no Figma, para humanos (aparece no brief) | obrigatório |
| `kind` | tipo do componente; escolhe as `devNotes` do tipo na política (3.2) | `component` |
| `when` | caso 1 do Figma → N widgets (3.3) | — |
| `coverage` | `complete` ou `partial` (seção 5); `sketch` só pelo construtor `FigmaConnect.sketch` | `complete` |
| `guide` | uma ou duas linhas: o que é o componente e o que falta cobrir | — |
| `figmaNotes` | como ler props do Figma que não viram parâmetro (4.3) | — |
| `devNotes` | regras de uso no código, valem em qualquer tela (4.4) | — |
| `docs` | onde está a documentação (6.1) | convenção `docs/<arquivo>.md` |
| `examples` | exemplos de implementação (6.2) | — |

### 3.1 `key` e a busca do mapeamento

Toda instância no IR traz duas keys:

- **`componentKey`:** do component set (ou do componente, se não tem variants).
- **`mainComponentKey`:** do componente principal exato, ou seja, a variant usada.

A CLI procura o mapeamento primeiro pela `mainComponentKey` e, se não achar, pela `componentKey`. Assim dá para
mapear o componente inteiro ou uma variant específica.

### 3.2 `kind`: o tipo do componente

```dart
enum FigmaKind {
  component,  // widget do DS (Button, Input, Badge)
  section,    // bloco composto usado dentro de telas (cabeçalho de saldo, card de resumo)
  template,   // esqueleto de tela: já traz scaffold e contexto
  icon,       // set de ícones, resolvido pela tabela de ícones
}
```

| | `component` | `section` | `template` | `icon` |
|---|---|---|---|---|
O `kind` hoje decide quais `devNotes` do tipo (`KindPolicy`, seção 7) entram no brief. Os ícones são resolvidos pela
tabela de ícones (7.2) em qualquer `f.icon`, seja qual for o `kind`.

### 3.3 `when`: nomes que não batem 1:1

| Caso | Exemplo | Como declarar |
|---|---|---|
| Nome diferente, 1:1 | `Btn` → `DsButton` | `@FigmaConnect(key: …, name: 'Btn')` |
| 1 do Figma → N widgets | `Button type=icon-only` → `DsIconButton` | duas funções com a mesma `key`, cada uma com `when: {'type': 'icon-only'}` |
| Prop escolhe construtor nomeado, factory ou outro widget (também prop da base exposta) | `✏️ Type` → `AcmeIconButton.primary` / `.secondary` / `AcmeGhostButton` | uma função com `f.variant` na raiz, o widget inteiro em cada opção: `f.variant('✏️ Type', {'Primary': AcmeIconButton.primary(…), …})`. O `when` só vê as props do próprio componente |
| N do Figma → 1 widget | `Card/Small` + `Card/Large` → `DsCard(size:)` | uma função por componente (cada um tem a sua key); o corpo fixa o valor: `DsCard(size: DsCardSize.small)` |
| Base travada exposta (um componente por tamanho, cada um com a sua key) | `Button Icon` (`👉 Size`) expõe `.Icon Button / Large`, `/ Medium` e `/ Small` | **uma** função, na key do público: lê o `👉 Size` dele e as props da base pelo nome (4.1). As bases não ganham anotação |
| Só existe no Figma | `_Base/Shape`, `.Nested / …` | prefixo `_` ou `.` = ignorado (se não tiver anotação própria); outros casos em `FigmaPolicy.ignored` |

```dart
@FigmaConnect(key: 'cc4d…', name: 'Button', when: {'type': 'icon-only'})
Widget iconButton(FigmaProps f) => DsIconButton(icon: f.icon('icon'));

@FigmaConnect(key: 'cc4d…', name: 'Button')
Widget button(FigmaProps f) => DsButton(label: f.text('label'));
```

A função com `when` mais específico vence. Um componente `.Nested` com widget próprio ganha a sua anotação pela
key, como qualquer outro, e aí entra na tela mesmo com o prefixo.

```dart
// Base travada: uma anotação só. O tamanho vem do público; tipo, ícone e estado, da base exposta.
@FigmaConnect(key: 'e8186571…', name: 'Button Icon')
Widget buttonIcon(FigmaProps f) => AcmeIconButton(
  size: f.variant('👉 Size', {'Large': AcmeIconButtonSize.large, 'Medium': …, 'Small': …}),
  type: f.variant('✏️ Type', {'Primary': …, 'Secondary': …, 'Tertiary': …}),
  icon: f.icon('🔄 Icon'),
  notification: f.boolean('🔔 Notification'),
);
```

---

## 4. Orientar a LLM

### 4.1 `FigmaProps`: o que o corpo da função pode ler

| Método | Prop do Figma | Retorno |
|---|---|---|
| `text(name)` | TEXT | `String` |
| `boolean(name)` | BOOLEAN | `bool` |
| `variant(name, map)` | VARIANT | valor do `map` |
| `icon(name)` | INSTANCE_SWAP de ícone | o ícone do DS (enum ou constante), pela tabela de ícones (7.2) |
| `instance(name)` | INSTANCE_SWAP / instância exposta | `Widget`, resolvido pelo mapeamento dela |
| `nested(path)` | instância exposta sem mapeamento próprio (ex.: `.Nested / Global Switcher/1. Flag`) | `FigmaProps` dela (`f.nested('1. Flag').boolean('Disabled')`) |
| `slot(part)` | área livre do template | lacuna `f2d:gap`: a LLM monta a área pela estrutura do brief |
| `guided(part, …)` | nenhuma: parte que exige julgamento | o valor `or` (4.2) |

Os nomes de prop vêm sem o sufixo `#id` do Figma (`label`, não `label#4:0`), e com o resto exato, inclusive emoji
(`✏️ Type`).

**Props das instâncias expostas:** `text`, `boolean`, `variant` e `icon` procuram a prop no componente e, se não
acharem, nas instâncias expostas dele, como o painel do Figma mostra. Assim um componente público lê as props da base
que expõe sem `nested` (3.3). Se a prop estiver em duas expostas, é erro: diga qual com `f.nested('<caminho>')`.

### 4.2 `f.guided`: parte com norte

```dart
T guided<T>(
  String part, {
  required String guide,
  required T or,
  List<Doc> docs = const [],
  List<Example> examples = const [],
});
```

| Parâmetro | Para quê |
|---|---|
| `part` | nome da parte; é o mesmo nome da seção no doc (`## filters`) |
| `guide` | o norte, em uma ou duas linhas |
| `or` | valor provisório que **compila**; é o que a CLI escreve no código |
| `docs`, `examples` | doc e exemplo só desta parte. A CLI ainda não lê: use a seção `## <parte>` no doc do componente |

A CLI escreve o valor `or` com o marcador, e a decisão vai para a seção "Decisões" do brief, com o norte e os valores
do Figma daquela instância:

```dart
filters: /* f2d:guided G2 filters */ const [],
```

### 4.3 `figmaNotes`: props do Figma sem parâmetro no código

Uma nota por prop do Figma que a função **não lê**:

```dart
sealed class FigmaNote {
  const factory FigmaNote.ignore(String reason) = IgnoreNote;
  const factory FigmaNote.derive(String guide) = DeriveNote;
  const factory FigmaNote.map(Map<String, Object?> values, {String? hint}) = MapNote;
}
```

| Tipo | Quando usar | O que a CLI faz |
|---|---|---|
| `ignore(reason)` | prop só visual, sem efeito no código | não reporta a prop como lacuna |
| `derive(guide)` | o efeito existe, mas vem de outra coisa (ex.: `state=empty` → `items: []`) | vira norte no brief |
| `map(values, hint:)` | correspondência conhecida, mas que ainda não cabe no corpo da função | entra no brief como `Global → null, BRL → Currency.brl`; é candidata a virar código |

```dart
figmaNotes: {
  'state': FigmaNote.derive('O vazio vem de items: [] + empty:'),
  'Collapse': FigmaNote.ignore('Só visual no Figma'),
  'Currency': FigmaNote.map({'Global': null, 'BRL': Currency.brl}, hint: 'Global = sem filtro de moeda'),
},
```

### 4.4 `devNotes`: regras de uso no código

Valem sempre que o componente aparece, **independente da cobertura**: um componente completo também pode ter
regras.

```dart
sealed class DevNote {
  const factory DevNote.must(String rule, {String? lint}) = MustNote;
  const factory DevNote.prefer(String rule) = PreferNote;
}
```

| Tipo | Significa | No código |
|---|---|---|
| `must(rule, lint:)` | obrigatório. Se for verificável, aponta o lint que cobra | o lint garante; o texto orienta |
| `prefer(rule)` | recomendação | a LLM pode fugir, mas marca `f2d:inferred` e diz o motivo |

```dart
devNotes: [
  DevNote.must('Em fluxo de pagamento, nunca onPressed: null; usar state: disabled.'),
  DevNote.prefer('Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.'),
],
```

Onde **não** colocar uma regra:

- **Fala de vários componentes** ("todo template fica dentro de AcmeContext"): `devNotes` do **tipo** na política
  (seção 7). Senão ela é copiada em 12 templates. O que vale para toda tela vai no `@FigmaScreen` (seção 8).
- **Precisa de explicação longa ou exemplo:** vai no doc; a `devNote` guarda só a frase.

---

## 5. Cobertura

```dart
enum Coverage { complete, partial, sketch }
```

- **`complete`:** a função lê todas as props que importam; as outras têm `FigmaNote.ignore`.
- **`partial`:** parte do componente depende de julgamento. Exige norte: `guide` e ao menos um `f.guided` ou
  `figmaNotes`. O código que sai é final, fora das lacunas marcadas.
- **`sketch`:** o componente não vai ser mapeado de forma determinística. A anotação **não tem função**: anota um
  `typedef` que liga o componente do Figma à classe do DS, e dá o norte. O construtor `FigmaConnect.sketch` exige
  `guide` em compilação:

```dart
@FigmaConnect.sketch(
  key: 'e5eab15a…', name: 'Template / Extrato', kind: FigmaKind.template,
  guide: 'Cada grupo de dia do Figma vira um DsStatementDay; o resumo vira incomeTotal/expenseTotal.',
  docs: [Doc.path('carteira_ds_figma/docs/ds_statement_template.md')],
  examples: [Example.code('carteira_ds_examples/lib/statement_example.dart', symbol: 'StatementExample')],
)
typedef StatementTemplate = DsStatementTemplate;
```

  Na tela, a instância vira o placeholder `/* f2d:sketch Template / Extrato → DsStatementTemplate */` (o `check`
  não passa com ele) e ganha uma tarefa própria, `components/<nome>/BRIEF.md`, com: o norte; a **API do widget**,
  lida do código do DS (construtores, parâmetros com tipo, obrigatório, padrão e doc, e os tipos auxiliares como
  `DsStatementDay` e enums); os **dados de cada instância** no Figma (props, instâncias expostas, overrides com
  valores, o conteúdo de dentro e o recorte do PNG); docs e exemplos. A LLM monta o widget no lugar do placeholder e
  marca com `f2d:inferred` o que decidiu.

Casos reais no Carteira DS (`design_system/carteira_ds_figma`): `TransactionList` é `partial` (título e ação do
Figma, linhas em `f.guided`) e `Template / Extrato` é `sketch`.

Na tela, cada caso vira:

| Item da instância no IR | Vira |
|---|---|
| Prop lida pela função (`f.text`, `f.boolean`…) | o valor do Figma no código |
| `f.guided` | o valor `or` com `f2d:guided` e o norte no brief |
| Prop que a função não lê | nada: a CLI não confere a cobertura declarada. Quem garante que toda prop importante é lida é o `mappings_test` do pacote (seção 10) |
| Override fora da API do componente | não entra no código; os valores aparecem no brief |

Componente **do DS** sem nenhuma anotação: a instância inteira vira lacuna `f2d:gap` ("componente sem
mapeamento"). Componente **fora do DS** não é lacuna: vira `f2d:placeholder` com brief de construção, ou, se o
widget já existe no app, `f2d:local` (5.1).

**Do DS ou fora dele** se decide pelo **retrato da biblioteca** (`figma_library.json` no pacote de mapeamentos,
gravado por `figma2dart library`). Sem retrato, componente remoto (de qualquer biblioteca) é do DS.

### 5.1 Componente do app que já existe: `@FigmaLocal`

Widget fora do DS que já existe no app (feito antes, por outro time, ou construído pelo agente). A anotação é
mínima — só liga a key do Figma ao widget — e fica **no pacote do widget**, em `figma/connect/` (fora de `lib/`, então
o `figma_connect` entra só como dev_dependency):

```dart
// libraries/pix/pix_ui/figma/connect/contact_item.figma.dart
import 'package:figma_connect/figma_connect.dart';
import 'package:pix_ui/widgets/contact_item.dart';

@FigmaLocal(key: '267291286c16eafc32e9a66b9571700954952086', name: 'ContactItem')
typedef ContactItemFigma = ContactItem;
```

- Ninguém escreve à mão: `figma2dart link <key> <arquivo.dart>[#Classe] [--name <nome>]` escreve o arquivo e põe o
  `figma_connect` nas dev_dependencies do pacote (pelo mesmo caminho que o pacote de mapeamentos usa), se faltar.
- A instância vira `/* f2d:local ContactItem → ContactItem */` + placeholder (o `check` não passa com ele) e uma
  tarefa de montagem como a do `sketch`: API do widget, `import`, dados de cada instância no Figma e `guide`
  (opcional). A LLM usa o widget; não o altera sem perguntar.
- A CLI lê os `@FigmaLocal` do pacote alvo e das dependências por path dele (pasta `connect:` no config; padrão
  `figma/connect`). Key do DS (no retrato), key já mapeada ou repetida, e `@FigmaConnect` em `figma/connect/` são
  erro.
- Num componente a construir, o `resolve` devolve `existing` quando acha uma classe de mesmo nome no `lib/` desses
  pacotes: o agente pergunta se é o mesmo e, se for, roda o `link`.
- O widget tem que estar no pacote da tela ou numa **dependência direta** dele: é só aí que o `resolve` procura, e o
  `link` recusa os outros.
- Anotação com problema (o widget foi renomeado e ela não compila, key do DS, key repetida) **fica de fora com
  aviso** (`warnings` no `doctor` e no `resolve`): o componente volta a ser "a construir" e as outras telas seguem.
  Anotação de um time não trava a tela de outro.

---

## 6. Docs e exemplos

### 6.1 `Doc`

```dart
sealed class Doc {
  const factory Doc.path(String path, {String? section, String? hint}) = PathDoc;
  const factory Doc.link(String url, {String? section, String? hint, String? source}) = LinkDoc;
}
```

| Campo | Para quê |
|---|---|
| `path` | arquivo no repositório, relativo à raiz dele; a CLI lê direto |
| `url` | doc online (site, Confluence…) |
| `section` | o trecho que interessa, com o mesmo nome da parte (`filters`) |
| `source` | só no `link`: arquivo local com o mesmo conteúdo, para a CLI ler |
| `hint` | uma linha: **o que tem no doc e quando ele importa** |

- **Convenção:** sem `docs`, a CLI procura `docs/<arquivo>.md` no pacote de mapeamentos, com o nome do `*.figma.dart`.
- **Conteúdo, não link:** a LLM recebe o trecho do doc dentro do brief. A CLI não acessa a rede: um `Doc.link` sem
  `source` entra só com o endereço e o `hint`.
- **Por que o `hint`:** quando o conteúdo não chega à LLM (link sem `source`, doc grande, seção fora do recorte),
  ela sabe o que existe e se precisa abrir.
- Seção pedida que não existe no arquivo aparece no brief com o aviso.

Organização do doc, pelas mesmas partes da anotação:

```markdown
# Template / Lista com filtro

## Geral
Já inclui AcmeScaffold; não envolver em outro. Paginação via AcmePaginator.

## filters
Cada Flag vira um AcmeFilterChip; `Disabled` → `enabled: false`; `Currency=Global` = sem filtro de moeda.

## Erros comuns
❌ Gerar os itens de exemplo do Figma como filhos fixos.
```

O doc **não** repete o que já está em outro lugar: construtor, tipos e defaults a CLI lê do Dart; props e variants,
do IR. Exemplo do que **não** fazer fica aqui, em "Erros comuns", como trecho curto com ❌; nunca como código no
repositório, porque código errado que compila acaba sendo copiado.

### 6.2 `Example`

```dart
sealed class Example {
  const factory Example.code(String path, {required String symbol, String? hint}) = CodeExample;
  const factory Example.usage(String path, {required String symbol, String? repo, String? hint}) = UsageExample;
}
```

| Tipo | Fonte | No brief |
|---|---|---|
| `code` | `carteira_ds_examples`: escrito para isso, compila na CI, sem regra de negócio | modelo para seguir |
| `usage` | uso real num app; `repo` identifica o repositório do app quando não é o do DS | referência de contexto, com o aviso "não copiar a lógica de negócio" |

Todo `path` é relativo à raiz do repositório: o do DS, ou o `repo` do `Example.usage`.

- **Referência por símbolo, não por linha:** classe, função ou método (`'ListaComFiltroBasica.build'`). A CLI extrai
  com o analyzer; número de linha desatualiza em qualquer edição.
- **Exemplos do pacote** são classes pequenas, uma por caso, com cubits de exemplo e dados falsos:

  ```dart
  // carteira_ds_examples/lib/templates/lista_com_filtro.dart

  /// Lista vinda da API, com filtros e refresh.
  class ListaComFiltroBasica extends StatelessWidget {
    const ListaComFiltroBasica({super.key});

    @override
    Widget build(BuildContext context) {
      final state = context.watch<ExemploListaCubit>().state;
      return AcmeListPage<Item>(
        title: 'Transações',
        items: state.items,
        itemBuilder: (item) => DsTransactionItem(title: item.titulo, value: item.valor),
        filters: [
          for (final f in state.filtros) AcmeFilterChip(label: f.label, enabled: !f.disabled),
        ],
        onRefresh: context.read<ExemploListaCubit>().refresh,
        empty: const AcmeEmptyState(title: 'Nenhuma transação'),
      );
    }
  }
  ```

- **Seleção no brief:** no máximo 1 `code` e 1 `usage` por componente; exemplos de uma parte só se ela for lacuna.
  Exemplo acima de ~60 linhas, ou que não coube, entra só como uma linha com o `hint` e o caminho.

---

## 7. Política por tipo: `FigmaPolicy`

Regras que valem para todos os componentes de um tipo, num lugar só:

```dart
// carteira_ds_figma/lib/figma_policy.dart
const figmaPolicy = FigmaPolicy(
  kinds: {
    FigmaKind.template: KindPolicy(
      devNotes: [
        DevNote.must('Template é a raiz da tela: não envolver em AcmeScaffold.', lint: 'acme_single_scaffold'),
        DevNote.must('Sempre dentro de AcmeContext com `feature` definido.'),
      ],
    ),
  },
  icons: IconTable(values: DsIconName.values, byKey: {/* mainComponentKey: DsIconName.x */}),
  ignored: {'4a7e…': 'Anotação de handoff do designer, sem código'},
);
```

| Campo | Para quê |
|---|---|
| `kinds` | por tipo: `devNotes` comuns, que entram no brief uma vez |
| `icons` | tabela de ícones (7.2) |
| `ignored` | componentes só do Figma que não seguem o prefixo `_`/`.`, com o motivo |

### 7.1 Como as regras se combinam

**`devNotes` do tipo** valem para todos os componentes daquele tipo e entram no brief uma vez, antes das `devNotes`
do componente.

### 7.2 Ícones

O set de ícones tem uma anotação só, com `kind: FigmaKind.icon`:

```dart
@FigmaConnect(key: '087d…', name: 'Icon', kind: FigmaKind.icon)
Widget icon(FigmaProps f) => DsIcon(f.icon('name'));
```

Os ícones do DS ficam no `IconTable` da política, de um destes jeitos:

```dart
icons: IconTable(values: DsIconName.values),   // enum
icons: IconTable.constants(AcmeIcons),         // classe com `static const activity = AcmeIconData('activity')`
```

Na classe, contam como ícone as constantes estáticas públicas de um tipo do DS. Uma `static const String`
auxiliar, por exemplo, não conta. Com a classe, o `f.icon` do mapeamento recebe o tipo do parâmetro do widget
(`AcmeIcon(f.icon('name'))`, onde o parâmetro é `AcmeIconData`), e a CLI escreve `AcmeIcons.activity`.

A resolução de cada ícone, em `f.icon` e em INSTANCE_SWAP:

1. pela `mainComponentKey` na `IconTable.byKey` (todos os ícones de um set compartilham a `componentKey`; é a
   `mainComponentKey` que diz qual é);
2. pela convenção de nomes (`arrow-up-right` → `DsIconName.arrowUpRight`);
3. sem correspondência: o primeiro valor (do enum ou da classe) com `/* TODO(f2d): ícone "x" do Figma não existe em DsIconName */`.
   O componente continua na tela; o dev troca o ícone (o `check` lista o TODO e não reprova).

### 7.3 Tokens

Guia prático para quem configura (como descobrir as coleções, conferir o que faltou): [DESIGN_OPS.md §2](DESIGN_OPS.md#2-tabela-de-tokens).

`TokenTable` diz onde cada coleção de variáveis do Figma (e os estilos de texto) está no código. Com ela, os briefs
já escrevem o código Dart do token (`DsSpacing.md`, `context.acmeSpacing.md`) em vez do nome do Figma (`Spacing/md`):
a LLM não procura constante nenhuma.

```dart
// DS com constantes estáticas (Carteira)
tokens: TokenTable(
  collections: {'Spacing': TokenSource(DsSpacing), 'Color': TokenSource(DsColors)},
  textStyles: TokenSource(DsTextStyles),
),

// DS com tokens no tema, por extensão do BuildContext (Acme)
tokens: TokenTable(
  collections: {
    'Spacing': TokenSource(AcmeSpacing, via: 'context.acmeSpacing'),
    'Color': TokenSource(AcmeColors, via: 'context.acmeColors'),
  },
  textStyles: TokenSource(AcmeTextStyles, via: 'context.acmeTextStyles'),
),

// Coleção que é a marca (`MarcaA/Colors/Surface/primary`, `MarcaB/Colors/Surface/primary`): o tema escolhe a marca,
// então a tabela liga o caminho, em qualquer coleção
tokens: TokenTable(
  scopes: {
    'Colors/Surface': TokenSource(AcmeColorSchemeSurface, via: 'context.acme.designTokens.colorScheme.surface'),
    'Colors/Surface/Brand': TokenSource(AcmeColorSchemeBrand, via: 'context.acme.designTokens.colorScheme.surface.brand'),
    'Colors/Content': TokenSource(
      AcmeColorSchemeContent,
      via: 'context.acme.designTokens.colorScheme.content',
      names: {'02': 'two', '03': 'three'},
    ),
  },
),
```

- **Coleção:** a primeira parte do nome da variável no Figma (`Spacing/md` → `Spacing`; `Color/text/primary` →
  `Color`).
- **`scopes`:** o caminho depois da coleção (`MarcaA/Colors/Surface/primary` → `Colors/Surface`), valendo para qualquer
  coleção. É para quando cada marca é uma coleção com os mesmos tokens: uma marca nova não pede configuração. A
  CLI procura primeiro em `collections`; se não achar, o caminho mais longo de `scopes` ganha
  (`Colors/Surface/Brand/primary` vai para `Colors/Surface/Brand`, não para `Colors/Surface`).
- **Membro:** o de `names` (`'02': 'two'`), para a classe que não dá para anotar; senão, o que tem o nome do Figma
  entre crases no doc (`` /// `2xs` = 2 `` → `xxs`); senão, o nome em camelCase (`text/primary` → `textPrimary`).
  Vale campo, getter, estático ou de instância. Membro que não existe na classe não vira código: o token sai como
  sem correspondência.
- **`via`:** a expressão que chega na instância do tema. Sem ela, o membro é estático (`DsSpacing.md`). Com ela, o
  brief avisa que o código precisa de `BuildContext` e não pode ser `const`.
- **Sem correspondência:** o brief mantém o nome do Figma com o valor (`Spacing/huge (sem Dart, 48)`), e a LLM usa o
  mais próximo com `f2d:inferred`.
- Estilos de cor do Figma (paint styles) saem pelo nome do estilo.
- **Conferir:** `figma2dart doctor --json` mostra em `policy` os tokens, estilos de texto e ícones do retrato sem
  código Dart, agrupados com o que fazer.

---

## 8. Mapeamento de tela: `@FigmaScreen`

Para o que vale em toda tela e só existe no código (`AcmeContext`, `AcmeScaffold`). A função recebe um
`FigmaScreenProps`. O `instance` recebe o **mapeamento** do componente, não o nome: a CLI acha pela key da
anotação dele, então renomear no Figma não quebra nada. Devolve `null` se a tela não tiver o componente:

```dart
// carteira_ds_figma/lib/connect/screen.figma.dart
@FigmaScreen()
Widget screen(FigmaScreenProps s) => AcmeContext(
  child: AcmeScaffold(
    appBar: s.instance(appHeader),     // a função anotada do AppHeader; se a tela tiver um, vira o appBar
    body: s.body(),                    // o resto da árvore gerada
  ),
);
```

- O `@FigmaScreen` entra no brief como "Esqueleto da tela": a LLM monta a tela dentro dele.
- **Template desanexado** (o designer desanexou a instância): sem instância nem props, a anotação não roda. O plugin
  aponta no lint (`detached-instance`), e a tela sai como camadas.

### 8.1 Widget de texto do DS: `@FigmaText`

No Figma, um texto é só uma camada com um estilo de texto. Quando o DS tem widget próprio (`AcmeText`), uma função
diz como cada texto vira código, uma vez para o pacote todo:

```dart
// acme_figma/lib/figma_policy.dart
const figmaPolicy = FigmaPolicy(
  tokens: TokenTable(textStyles: TokenSource(AcmeTextType)), // a tipografia é um enum: body/sm → AcmeTextType.bodySm
);

@FigmaText()
Widget text(FigmaTextProps t) => AcmeText(t.text(), type: t.style());
```

| `FigmaTextProps` | Vira |
|---|---|
| `t.text()` | o texto entre aspas; num componente a construir, o parâmetro da prop ligada (`label`) |
| `t.style()` | o estilo de texto pelo `textStyles` da política (§7.3) |
| `t.color()` | a cor pelo token (`context.acmeColors.textPrimary`), se o widget recebe cor |

- Na estrutura do brief, cada texto sai com o código pronto: `` texto → `AcmeText('Entrar', type: AcmeTextType.bodySm)` ``.
  O "Não fazer" do brief proíbe o `Text`/`TextStyle` do Flutter, e o `figma2dart check` dá uma dica em cada linha
  da tela ou do componente construído que usa um deles.
- **Texto sem estilo do DS** (fonte solta; o plugin aponta no lint `text-without-style`): no lugar do estilo sai
  `fonte Inter Bold 14 (sem estilo do DS)`. Estilo do Figma sem membro no enum: `body/xl (sem Dart)`. Nos dois casos
  a LLM usa o mais próximo e marca `f2d:inferred`.
- **Texto com trechos em estilos diferentes** (`72% de chance de **Alta**`): com uma função `@FigmaText.rich`, sai
  o código com um item por trecho; sem ela, sai o widget simples com `estilo de cada trecho` e a lista de trechos.

  ```dart
  @FigmaText.rich()
  Widget richText(BuildContext context, FigmaRichTextProps t) => AcmeRichText(
    text: TextSpan(
      children: t.spans((s) => TextSpan(
        text: s.text(),
        style: s.style<AcmeTypographyType>().styleOf(context).copyWith(color: s.color()),
      )),
    ),
  );
  ```

  `t.spans` repete a função para cada trecho, com o texto, o estilo e a cor dele; o `context` vai como está (é o do
  `build` da tela). O `check` procura cada trecho no código, não a frase inteira. Texto em trechos ligado a uma prop
  (num componente a construir) sai com o widget simples: os trechos dependem do valor.
- Vale para o texto solto da tela e para o dos componentes a construir. Dentro de um componente do DS, o texto é
  atributo dele (`f.text('label')` → `'Entrar'`), e a função não entra.
- Uma função `@FigmaText` por pacote, de expressão (`=>`), em qualquer arquivo de `lib/`. O código dela vai para o
  brief como está: escreva sem prefixo de import (`AcmeText`, não `acme.AcmeText`). Sem ela, os textos saem
  descritos, e o `doctor` avisa; num DS que usa o `Text` do Flutter, `Text(t.text(), style: t.style())` resolve.

---

## 9. Como cada campo chega à LLM

O `BRIEF.md` que o `figma2dart resolve` escreve junta só o que vale para a tela, na seção "Componentes desta tela":

````markdown
### Lista com filtro (partial)

Norte: Lista paginada. Filtros, células e refresh dependem da feature.
- [obrigatório · lint acme_single_scaffold] Template é a raiz da tela: não envolver em AcmeScaffold.
- [recomendado] Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.
- Figma `state`: não existe no código; o vazio vem de items: [] + empty:

API do widget:
```dart
AcmeListPage({required String title, …})
```

- Doc: acme_figma/docs/lista_com_filtro.md — Visão geral e erros comuns
  (conteúdo das seções que valem para a tela)
- Exemplo: ListaComFiltroBasica — Caso padrão (código extraído pelo símbolo)
````

| Campo | Onde aparece |
|---|---|
| `coverage` | ao lado do nome, quando não é `complete` |
| `guide` | "Norte", quando não é `complete` |
| `devNotes` (tipo + componente) | lista de regras, uma vez por componente |
| `figmaNotes` | `derive` e `map` como norte; `ignore` não aparece |
| `docs` | conteúdo recortado + `hint`; só o `hint` se o conteúdo não chegou |
| `examples` | código extraído pelo símbolo, até ~60 linhas |
| `f.guided` | marcador no código + item em "Decisões" |

Componentes `complete` sem `devNotes`, `figmaNotes`, docs nem exemplos não aparecem: já estão resolvidos no código.

---

## 10. Validação

| Onde | O que pega |
|---|---|
| `flutter analyze` do pacote de mapeamentos | a anotação instancia o widget de verdade: parâmetro renomeado ou removido no DS não compila |
| `test/mappings_test.dart` do pacote | cada anotação com os valores padrão do Figma e **todas** as opções de cada variant: opção sem mapeamento falha |
| CLI, ao carregar os mapeamentos | anotação do DS que não compila (erro); duas anotações empatadas para a mesma instância (erro: diferencie com `when`); `FigmaConnect.sketch` que não anota um `typedef` (erro); `@FigmaLocal` fora de `figma/connect/` ou que não compila (fica de fora, com aviso) |
| CLI, ao resolver a tela | valor sem correspondência (variant sem opção, prop que não existe, prop em duas expostas): só aquela instância vira `f2d:gap` com o motivo |
| `figma2dart doctor` | política contra o retrato: tokens, estilos de texto e ícones sem código Dart |

### 10.1 Captura para a revisão visual: `figmaCapture`

`package:figma_connect/capture.dart` (só em teste de widget) renderiza a tela no tamanho do frame do Figma, na escala
do PNG do export, com **todas as fontes do app** (pelo `FontManifest.json`: as do DS entram sem config), e grava em
`.figma2dart/tasks/<tela>/capture/` o `screen.png` e o `layout.json` (textos visíveis com o retângulo, inclusive o
valor digitado num campo; erros de layout como overflow, que **não reprovam** o teste).

```dart
testWidgets('figma: 03 · Transferir', (tester) async {
  await figmaCapture(
    tester,
    MaterialApp(theme: DsTheme.light(), home: TransferPage(wallet: Wallet.sample())),
    task: 'transferir',
    // o estado do Figma antes da captura: sem isso, botão desabilitado e campo vazio viram diferença falsa
    prepare: (tester) => tester.enterText(find.byType(TextField), '15000'),
  );
});
```

O `figma2dart review` lê a captura e monta a revisão (Figma | Flutter, fatos e critério). Quem escreve o teste é a
LLM (skill `figma2dart-review`): só ela sabe o construtor, o tema e os dados da tela. O `figma_connect` passa a
depender do `flutter_test` por causa desse arquivo; o resto da API não usa.

---

## 11. O que não colocar na anotação

- **Props, tipos e defaults do widget:** já estão no construtor Dart; a CLI lê de lá.
- **Props e variants do Figma:** já estão no IR.
- **Ancestrais obrigatórios tipados** (`requires: [AcmeContext]`): é o que um lint faz melhor; usar
  `DevNote.must(…, lint:)`.
- **Versão ou `since`:** quem sabe a versão é o pacote; o `status` cobre o que importa para a LLM.
- **Mais níveis de prioridade de regra:** `must` e `prefer` bastam; mais níveis confundem o modelo.
- **Exemplo como string de código:** não compila, não é analisado e desatualiza no primeiro refactor. Use `Example`.

---

## 12. Ciclo de melhoria

A anotação começa com norte e fica mais determinística com o uso:

1. Lacuna resolvida do mesmo jeito em várias telas → vira código na função (sai o `f.guided`).
2. `FigmaNote.map` estável → vira `f.variant` na função.
3. Erro que se repete no review → linha em "Erros comuns" no doc ou nova `devNote`.
4. `DevNote.must` que se repete e dá para verificar → vira lint, e a nota aponta o lint (`lint:`).

As lacunas que mais aparecem nos briefs são a lista de prioridades do time do DS.
