# `@FigmaConnect` — referência da anotação

Como ligar um componente do Figma a um widget Dart, e como orientar a LLM quando essa ligação não é
determinística. Para quem escreve e revisa os mapeamentos (time do DS).

A arquitetura geral está em [ARCHITECTURE.md](ARCHITECTURE.md): o mapeamento é a seção 7 e a geração assistida por
LLM é a seção 10. Este documento é a referência completa da API.

> **Status:** os tipos da API estão no pacote [`figma_connect/`](../figma_connect/). O gerador, o brief e a validação
> que os consomem ainda não existem (roadmap, passos 3 e 4). Os nomes do DS real nos exemplos (`AcmeListPage`,
> `AcmeFilterChip`…) são ilustrativos.

---

## 1. Ideia geral

- **Um arquivo `*.figma.dart` por componente**, no pacote `carteira_ds_figma`. **O widget do DS não é alterado.**
- **A função anotada é um template:** o gerador avalia a função trocando cada `f.*` pelos valores que a instância
  usa no Figma, e escreve o código resultante na tela.
- **O que é determinístico, a anotação resolve.** O que não é, ela orienta: deixa um **norte** (`guide`,
  `f.guided`, notas, docs e exemplos) e a LLM implementa, marcando o que decidiu.
- **A anotação é o índice do componente.** Norte, docs, exemplos e regras ficam num lugar só; a CLI junta no brief
  só o que a tela precisa.

Onde ficam os arquivos:

```
design_system/
  carteira_ds_figma/
    lib/connect/*.figma.dart     ← as anotações
    lib/figma_policy.dart        ← regras por tipo, tabela de ícones, componentes ignorados
    docs/                        ← docs opcionais por componente
    rules/                       ← regras de projeto (valem para a tela ou para vários componentes)
  carteira_ds_examples/          ← exemplos de implementação: compilam, sem regra de negócio
  carteira_lints/                ← regras obrigatórias como lint
```

---

## 2. Do mínimo ao completo

**Componente simples e totalmente coberto** (a maioria): só `key`, `name` e o corpo.

```dart
// carteira_ds_figma/lib/connect/ds_badge.figma.dart
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
  tags: {'list', 'filter'},
  owner: 'time-ds-core',
  status: Status.stable,
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
    Set<String> tags = const {},
    String? owner,
    Status status = Status.stable,
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
| `name` | nome no Figma, para humanos e para o drift ("mesma key, nome diferente") | obrigatório |
| `kind` | tipo do componente; decide geração, validação e brief (3.2) | `component` |
| `when` | caso 1 do Figma → N widgets (3.3) | — |
| `tags` | domínio (`form`, `list`, `navigation`…), para selecionar regras de projeto | — |
| `owner` | time responsável: aparece no brief e recebe os erros de CI | — |
| `status` | `stable`, `experimental` ou `deprecated` (3.4) | `stable` |
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

O gerador procura o mapeamento primeiro pela `mainComponentKey` e, se não achar, pela `componentKey`. Assim dá para
mapear o componente inteiro ou uma variant específica. Pelo MCP nativo, que não tem keys, a busca é pelo nome.

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
| **Geração** | normal | normal | vira a raiz da tela; o `@FigmaScreen` não acrescenta outro scaffold | pela tabela de ícones (7.2) |
| **Cobertura esperada** | `complete` (`partial` dá aviso) | qualquer | qualquer | sempre `complete` |
| **Obrigatório** | — | `guide`, se `partial` | `guide`, `docs` e ao menos 1 `Example.code` | — |
| **No brief** | só as lacunas | lacunas e exemplos | `guide`, docs e exemplos inteiros | nunca |

A tabela mostra a política recomendada (exemplo da seção 7). As regras só valem se estiverem no `FigmaPolicy`: sem
`KindPolicy` para um tipo, nada é exigido dele.

> **Em aberto:** se os blocos compostos do DS já forem componentes comuns, `section` pode sair e ficam só
> `component`, `template` e `icon`.

### 3.3 `when`: nomes que não batem 1:1

| Caso | Exemplo | Como declarar |
|---|---|---|
| Nome diferente, 1:1 | `Btn` → `DsButton` | `@FigmaConnect(key: …, name: 'Btn')` |
| 1 do Figma → N widgets | `Button type=icon-only` → `DsIconButton` | duas funções com a mesma `key`, cada uma com `when: {'type': 'icon-only'}` |
| N do Figma → 1 widget | `Card/Small` + `Card/Large` → `DsCard(size:)` | uma função por componente (cada um tem a sua key); o corpo fixa o valor: `DsCard(size: DsCardSize.small)` |
| Só existe no Figma | `_Base/Shape`, `.Nested / …` | prefixo `_` ou `.` = ignorado; outros casos em `FigmaPolicy.ignored` |

```dart
@FigmaConnect(key: 'cc4d…', name: 'Button', when: {'type': 'icon-only'})
Widget iconButton(FigmaProps f) => DsIconButton(icon: f.icon('icon'));

@FigmaConnect(key: 'cc4d…', name: 'Button')
Widget button(FigmaProps f) => DsButton(label: f.text('label'));
```

A função com `when` mais específico vence. Um componente `.Nested` com widget próprio ganha a sua anotação pela
key, como qualquer outro.

### 3.4 `status`

```dart
sealed class Status {
  static const Status stable = StableStatus();
  const factory Status.experimental({String? hint}) = ExperimentalStatus;
  const factory Status.deprecated({required String replacement, String? hint}) = DeprecatedStatus;
}
```

```dart
status: Status.deprecated(replacement: 'Template / Lista v2', hint: 'Remover até a versão 4.0'),
```

- **`deprecated`:** o gerador continua gerando (a tela usa aquilo no Figma), mas marca `f2d:inferred` e mostra o
  substituto. No brief: "não usar em código novo; preferir X". Exemplo que usa componente depreciado dá aviso.
- **`experimental`:** entra no brief como "API pode mudar".

---

## 4. Orientar a LLM

### 4.1 `FigmaProps`: o que o corpo da função pode ler

| Método | Prop do Figma | Retorno |
|---|---|---|
| `text(name)` | TEXT | `String` |
| `boolean(name)` | BOOLEAN | `bool` |
| `variant(name, map)` | VARIANT | valor do `map` |
| `icon(name)` | INSTANCE_SWAP de ícone | `DsIconName`, pela tabela de ícones (7.2) |
| `instance(name)` | INSTANCE_SWAP / instância exposta | `Widget`, resolvido pelo mapeamento dela |
| `nested(path)` | instância exposta sem mapeamento próprio (ex.: `.Nested / Global Switcher/1. Flag`) | `FigmaProps` dela (`f.nested('1. Flag').boolean('Disabled')`) |
| `slot(part)` | área livre do template | `Widget`, gerado recursivamente a partir da árvore do IR |
| `guided(part, …)` | nenhuma: parte que exige julgamento | o valor `or` (4.2) |

Os nomes de prop vêm sem o sufixo `#id` do Figma (`label`, não `label#4:0`).

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
| `or` | valor provisório que **compila**; é o que o gerador escreve |
| `docs`, `examples` | doc e exemplo só desta parte; entram no brief só se a parte for lacuna na tela |

O gerador escreve o valor `or` e, acima dele, o marcador com o norte e os valores do Figma. A orientação fica na
linha que precisa mudar:

```dart
// f2d:guided G2 filters — Cada Flag exposta vira AcmeFilterChip; Disabled → enabled: false.
//   Figma: 1. Flag {Rounded: true, Disabled: false, Currency: BRL}, 2. Flag {…, Currency: Global}
filters: const [],
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
| `map(values, hint:)` | correspondência conhecida, mas que ainda não cabe no corpo da função | entra no brief como tabela; é candidata a virar código |

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

- **Fala da tela ou de vários componentes** ("toda tela de feature usa AcmeContext"): regra de projeto em `rules/`,
  ou `devNotes` do **tipo** na política (seção 7). Senão ela é copiada em 12 templates.
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
  valores); docs e exemplos. A LLM monta o widget no lugar do placeholder e marca com `f2d:inferred` o que decidiu.
  Desde o IR 1.3 o brief de cada instância traz também o **conteúdo de dentro** (textos e instâncias visíveis, com
  caminho e props: os dias e as linhas do Extrato) e o **recorte do PNG** da tela só com aquela instância. Export
  anterior (IR 1.2) tem só o que é exposto ou sobrescrito, e o PNG da tela inteira.

Casos reais no Carteira DS (`design_system/carteira_ds_figma`): `TransactionList` é `partial` (título e ação do
Figma, linhas em `f.guided`) e `Template / Extrato` é `sketch`.

A cobertura declarada é **conferida** pela CLI. Ela compara o que cada instância usa no IR com o que a anotação lê:

| Item da instância no IR | Coberto quando | Se não for coberto |
|---|---|---|
| Prop (TEXT, BOOLEAN, VARIANT, SWAP) | a função lê com `f.text`, `f.boolean`… ou há `FigmaNote` | lacuna `f2d:gap`, sem norte |
| Instância exposta | a função usa `f.instance` ou `f.nested` | idem |
| Override fora da API do componente | nunca: a anotação não lê overrides | lacuna, com os valores do override |
| `f.guided` | nunca: é proposital | lacuna `f2d:guided`, com o norte |

Componente **do DS** sem nenhuma anotação: a instância inteira vira lacuna `f2d:gap` ("componente sem
mapeamento"). Componente **fora do DS** não é lacuna: vira `f2d:placeholder` com brief de construção, ou, se o
widget já existe no app, `f2d:local` (seção 5.1).

**Do DS ou fora dele** se decide pelo **retrato da biblioteca**: `figma_library.json` no pacote de mapeamentos, com
a key e o nome de cada componente do DS. Ele sai dos exports do plugin em **modo biblioteca** (uma página do arquivo
do DS por export, sem seleção): `figma2dart library <zip>…` grava ou atualiza (exportar a mesma página de novo
substitui a anterior). Sem retrato, vale a regra antiga: componente remoto (de qualquer biblioteca) é do DS.

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
| `path` | arquivo no repositório do DS, relativo à raiz dele; a CLI lê direto |
| `url` | doc online (site, Confluence…) |
| `section` | o trecho que interessa, com o mesmo nome da parte (`filters`) |
| `source` | só no `link`: arquivo de origem daquele link, para a CLI ler sem rede |
| `hint` | uma linha: **o que tem no doc e quando ele importa** |

- **Convenção:** sem `docs`, a CLI procura `carteira_ds_figma/docs/<arquivo>.md` com o nome do `*.figma.dart`.
- **Conteúdo, não link:** a LLM recebe o trecho do doc dentro do brief, não "veja este link". Um `Doc.link` sem
  `source` é baixado no `brief` e guardado em `.figma2dart/cache/`; se a CLI não tiver acesso, entra só o `hint`.
- **Por que o `hint`:** resolve o caso em que o conteúdo não chega à LLM (sem acesso, doc grande, seção fora do
  recorte). Ela sabe o que existe e se precisa abrir. Também ajuda a CLI a deixar de fora docs que não se aplicam
  à tela.
- **Doc online exige cuidado** com versão (o app pode usar uma versão mais antiga do DS), com âncoras estáveis e com
  login (SSO exige token na CLI). Preferir docs gerados a partir de markdown no repositório, com `source`.

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
- **Golden opcional:** cada `Example.code` pode virar golden test; o exemplo também vira teste visual do DS.

---

## 7. Política por tipo: `FigmaPolicy`

Regras que valem para todos os componentes de um tipo, num lugar só:

```dart
// carteira_ds_figma/lib/figma_policy.dart
const figmaPolicy = FigmaPolicy(
  kinds: {
    FigmaKind.template: KindPolicy(
      require: {Field.guide, Field.docs, Field.exampleCode},
      brief: BriefDepth.full,
      devNotes: [
        DevNote.must('Template é a raiz da tela: não envolver em AcmeScaffold.', lint: 'acme_single_scaffold'),
        DevNote.must('Sempre dentro de AcmeContext com `feature` definido.'),
      ],
    ),
    FigmaKind.section: KindPolicy(brief: BriefDepth.gapsAndExamples),
    FigmaKind.component: KindPolicy(expectedCoverage: Coverage.complete, brief: BriefDepth.gaps),
    FigmaKind.icon: KindPolicy(expectedCoverage: Coverage.complete, brief: BriefDepth.none),
  },
  icons: IconTable(values: DsIconName.values, byKey: {/* mainComponentKey: DsIconName.x */}),
  ignored: {'4a7e…': 'Anotação de handoff do designer, sem código'},
);
```

| Campo | Para quê |
|---|---|
| `kinds` | por tipo: campos obrigatórios (`require`), cobertura esperada, profundidade no brief e `devNotes` comuns |
| `icons` | tabela de ícones (7.2) |
| `ignored` | componentes só do Figma que não seguem o prefixo `_`/`.`, com o motivo |

### 7.1 Como as regras se combinam

- **`devNotes` do tipo** valem para todos os componentes daquele tipo e entram no brief **uma vez**.
- **Regras de projeto** (`rules/*.md`) podem filtrar por tipo e por tag:

  ```markdown
  ---
  id: forms.validation
  applies_when: { tags: [form] }      # ou { kind: template }, { uses: [Input] }, { has: flow }, always
  enforced_by: none                   # ou lint:<id>
  ---
  Validação usa AcmeForm + AcmeValidators, nunca TextFormField.validator direto.
  ```

- **Ordem no brief:** regras do tipo → `devNotes` do componente → regras de projeto selecionadas. Uma regra
  repetida aparece uma vez.

### 7.2 Ícones

O set de ícones tem uma anotação só, com `kind: FigmaKind.icon`:

```dart
@FigmaConnect(key: '087d…', name: 'Icon', kind: FigmaKind.icon)
Widget icon(FigmaProps f) => DsIcon(f.icon('name'));
```

A resolução de cada ícone, em `f.icon` e em INSTANCE_SWAP:

1. pela `mainComponentKey` na `IconTable.byKey` (todos os ícones de um set compartilham a `componentKey`; é a
   `mainComponentKey` que diz qual é);
2. pela convenção de nomes (`arrow-up-right` → `DsIconName.arrowUpRight`), com as exceções de
   `figma_specs/naming.yaml`;
3. sem correspondência: o primeiro valor do enum com `/* TODO(f2d): ícone "x" do Figma não existe em DsIconName */`.
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
```

- **Coleção:** a primeira parte do nome da variável no Figma (`Spacing/md` → `Spacing`; `Color/text/primary` →
  `Color`).
- **Membro:** o que tem o nome do Figma entre crases no doc (`` /// `2xs` = 2 `` → `xxs`); sem isso, o nome em
  camelCase (`text/primary` → `textPrimary`). Vale campo, getter, estático ou de instância.
- **`via`:** a expressão que chega na instância do tema. Sem ela, o membro é estático (`DsSpacing.md`). Com ela, o
  brief avisa que o código precisa de `BuildContext` e não pode ser `const`.
- **Sem correspondência:** o brief mantém o nome do Figma com o valor (`Spacing/huge (sem Dart, 48)`), e a LLM usa o
  mais próximo com `f2d:inferred`.
- Estilos de cor do Figma (paint styles) ainda saem pelo nome do estilo.

---

## 8. Mapeamento de tela: `@FigmaScreen`

Para o que vale em toda tela e só existe no código (`AcmeContext`, `AcmeScaffold`). A função recebe um
`FigmaScreenProps`. O `instance` recebe o **mapeamento** do componente, não o nome: o gerador acha pela key da
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

- Tela montada a partir de um **template** (instância ou `detachedInfo` no IR): o template é a raiz e o
  `@FigmaScreen` não acrescenta outro scaffold.
- Configuração que depende da feature vira uma pergunta explícita no brief.
- **Template desanexado:** sem instância nem props, a anotação não roda. A CLI usa o `detachedInfo` para achar o
  template e entrega `guide`, notas, docs e exemplos inteiros dele, mais a árvore do IR.

---

## 9. Como cada campo chega à LLM

O `BRIEF.md` que o `figma2dart resolve` escreve junta só o que vale para a tela:

````markdown
## Componentes desta tela
### Lista com filtro (template · parcial · time-ds-core)
Lista paginada. Filtros, células e refresh dependem da feature.
- [obrigatório · lint acme_single_scaffold] Template é a raiz da tela: não envolver em AcmeScaffold.
- [obrigatório] Sempre dentro de AcmeContext com `feature` definido.
- [recomendado] Mais de 3 filtros: usar AcmeFilterSheet em vez de chips.
- Figma `state`: não existe no código; o vazio vem de items: [] + empty:

Docs:
- docs/templates/lista_com_filtro.md — Visão geral e erros comuns do template  ← conteúdo abaixo
- https://ds.empresa/docs/paginacao — Ler se a lista vem da API  ← conteúdo abaixo (lido de docs/paginacao.md)

Exemplo — Caso padrão: lista da API com filtros e refresh
(carteira_ds_examples/lib/templates/lista_com_filtro.dart · ListaComFiltroBasica)
```dart
class ListaComFiltroBasica extends StatelessWidget { … }
```

## Lacunas
- G2 (guided) filters — Cada Flag exposta vira AcmeFilterChip… · Figma: 1. Flag {…} · doc: ## filters · exemplo: ListaComMuitosFiltros
````

| Campo | Onde aparece |
|---|---|
| `kind`, `owner`, `status`, `coverage` | cabeçalho do componente |
| `guide` | primeira linha do componente |
| `devNotes` (tipo + componente) | lista de regras, uma vez por componente |
| `figmaNotes` | `derive` e `map` como norte; `ignore` não aparece |
| `docs` | conteúdo recortado + `hint`; só o `hint` se o conteúdo não chegou |
| `examples` | código extraído pelo símbolo, dentro do limite |
| `f.guided` | marcador no código + item em "Lacunas" |

Componentes `complete` sem `devNotes` não aparecem: já estão resolvidos no rascunho.

---

## 10. Validação (CI e `figma2dart check`)

| Verificação | Severidade |
|---|---|
| `coverage: complete` com prop do Figma não lida e sem `FigmaNote` | erro |
| `coverage: partial` sem `guide` ou sem nenhum `f.guided`/`figmaNotes` | erro |
| Campo exigido pela política do `kind` ausente (ex.: template sem `Example.code`) | erro |
| `component` com `coverage: partial` | aviso |
| `Doc.path` ou `source` inexistente; `section` inexistente no doc | erro |
| `Doc.link` sem `source` e sem `hint` | erro |
| `f.guided('x')` com doc da parte sem seção `## x` | erro |
| Seção do doc sobre uma prop que a função passou a cobrir | aviso (doc desatualizado) |
| `Example`: arquivo ou símbolo inexistente, ou símbolo que não usa o widget anotado | erro |
| `Example.code` que viola um `DevNote.must` com lint | erro |
| `Example.usage` sem nenhum `Example.code` no componente | aviso |
| Exemplo que usa componente `deprecated` | aviso |
| `guide`, `hint` ou nota com mais de ~2 linhas | aviso (mover para o doc) |
| Mesma `devNote` em vários componentes | sugestão: regra do tipo ou de projeto |
| `DevNote.must` sem `lint` repetido em vários componentes | sugestão: virar lint |
| Prop nova no Figma sem leitura, sem `FigmaNote` | erro (drift) |
| Mesma key, nome diferente | info (drift) |

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
4. `DevNote.must` que se repete → lint em `carteira_lints`.

O relatório do `check`, agregado por componente, mostra quais lacunas mais aparecem: é a lista de prioridades do
time do DS. `figma2dart docs status` lista os componentes usados nos exports sem anotação ou sem norte, por
frequência e por `owner`.
