# O que o design ops configura e mantém

Para o design ops, que é dono do Acme e do `acme_figma`. Os times dos setores não configuram nada disso: eles só
rodam o agente. Tudo aqui é feito **uma vez** e depois **quando o Acme muda** (tabela no fim).

Referência completa das anotações: [FIGMA_CONNECT.md](FIGMA_CONNECT.md). Instalação no monorepo:
[MIGRACAO_MONOREPO.md](MIGRACAO_MONOREPO.md).

| # | O quê | Onde | Quando |
|---|---|---|---|
| 1 | Config do repositório | `libraries/design_ops/packages/figma2dart/figma2dart.yaml` | uma vez |
| 2 | Tabela de tokens | `acme_figma/lib/figma_policy.dart` | uma vez; nova coleção de variáveis |
| 3 | Tabela de ícones | `acme_figma/lib/figma_policy.dart` | uma vez; ícone com nome diferente |
| 4 | Componentes ignorados e regras por tipo | `acme_figma/lib/figma_policy.dart` | quando aparecer o caso |
| 5 | Mapeamento de cada componente | `acme_figma/lib/connect/<componente>.figma.dart` | componente novo ou API mudou |
| 6 | Docs e exemplos (opcional) | `acme_figma/docs/`, pacote de exemplos | quando a LLM errar o uso |
| 7 | Retrato da biblioteca | `acme_figma/figma_library.json` (gerado) | página do Acme mudou no Figma |

Tudo vai para o git: a CLI acha config, mapeamentos e retrato pelo índice do git.

---

## 1. Config do repositório

```yaml
# libraries/design_ops/packages/figma2dart/figma2dart.yaml
mappings: ../acme_figma     # pacote dos mapeamentos, relativo a este arquivo
screens: lib/figma          # onde as telas geradas ficam em cada pacote (relativo ao pacote)
# exports: ~/Downloads      # onde o plugin salva os zips (padrão)
# connect: figma/connect    # onde ficam os @FigmaLocal dos times (padrão)
```

Um pacote de setor pode ter o próprio `figma2dart.yaml` só com `screens:`. Não ponha `mappings:` em outro arquivo:
dois configs com `mappings:` é erro.

**Conferir:** `figma2dart doctor --json` de dentro de um pacote de setor mostra o config em `configs` e o
`acme_figma` em `mappings`.

## 2. Tabela de tokens

Faz o brief escrever `context.acmeSpacing.md` em vez de `Spacing/md`. **Não é uma anotação por token:** é uma linha
por **coleção de variáveis do Figma**.

```dart
// acme_figma/lib/figma_policy.dart
const figmaPolicy = FigmaPolicy(
  tokens: TokenTable(
    collections: {
      //  coleção no Figma   classe Dart     como o código chega nela
      'Spacing': TokenSource(AcmeSpacing, via: 'context.acmeSpacing'),
      'Color':   TokenSource(AcmeColors,  via: 'context.acmeColors'),
      'Radius':  TokenSource(AcmeRadius,  via: 'context.acmeRadius'),
    },
    textStyles: TokenSource(AcmeTextStyles, via: 'context.acmeTextStyles'),
  ),
  // icons:, ignored:, kinds: (abaixo)
);
```

- **Coleção:** o nome no painel de variáveis do Figma (a parte antes da primeira `/` do nome completo:
  `Spacing/md` → `Spacing`). Para listar as de um export:
  ```sh
  unzip -p figma2dart-*.zip export.json | python3 -c "import json,sys; print(sorted({k.split('/')[0] for k in json.load(sys.stdin)['tokens']}))"
  ```
- **Classe:** o tipo que `context.acmeSpacing` devolve. Se o Acme tem
  `extension on BuildContext { AcmeSpacing get acmeSpacing => … }`, a classe é `AcmeSpacing`.
- **`via`:** o que o dev escreve antes do `.md`. Sem `via`, o membro é estático (`AcmeSpacing.md`).
- **Os tokens um por um não se listam.** A CLI casa cada token com um membro da classe:
  1. pelo nome do Figma entre crases no comentário do membro: `` /// `2xs` `` em cima de `final double xxs;`;
  2. senão, pelo nome em camelCase: `text/primary` → `textPrimary`, `md` → `md`.

  Só os que não batem pelo camelCase precisam do comentário (ex.: `2xs` → `xxs`).

**Conferir:** rode `figma2dart resolve` de uma tela e procure `(sem Dart` nos `BRIEF.md`. Cada ocorrência
(`Spacing/2xs (sem Dart, 2)`) é um token sem correspondência: falta a coleção na tabela, ou o membro tem outro nome e
não tem o comentário.

## 3. Tabela de ícones

No Acme, os ícones são constantes de uma classe (`abstract class AcmeIcons { static const activity =
AcmeIconData('activity'); … }`), não um enum:

```dart
icons: IconTable.constants(
  AcmeIcons,                                           // a classe com uma constante por ícone
  byKey: {'1ca79dba…': AcmeIcons.arrowDownLeft},       // só as exceções
),
```

Se os ícones forem um enum, use `IconTable(values: AcmeIconName.values, byKey: {…})`.

- **Convenção:** o ícone do Figma vira a constante pelo nome em camelCase (`arrow-down-left` → `arrowDownLeft`).
- **`byKey`:** só para os que não batem, pela `mainComponentKey` do ícone.
- **Sem correspondência:** sai a primeira constante, com `TODO(f2d)`. Aparece no `check` (`todos`).
- **No mapeamento do ícone:** `AcmeIcon(f.icon('name'))`. O `f.icon` aceita o tipo do parâmetro (`AcmeIconData`).

## 4. Componentes ignorados e regras por tipo

```dart
ignored: {'4a7e…': 'Anotação de handoff do designer, sem código'},
kinds: {
  FigmaKind.template: KindPolicy(
    devNotes: [DevNote.must('Template é a raiz da tela: não envolver em AcmeScaffold.')],
  ),
},
```

- **`ignored`:** componente que só existe no Figma (anotação, guia) e não é `_`/`.` no nome (esses já são
  ignorados). Vira "Não implementar" no brief.
- **`kinds`:** regra que vale para todo componente de um tipo; entra no brief uma vez.

## 5. Mapeamento de cada componente

Um arquivo por componente do Acme em `acme_figma/lib/connect/`. O nível depende de quanto o Figma bate com a API:

```dart
// complete: o Figma bate com a API; a CLI escreve o código pronto
@FigmaConnect(key: 'f5c999bb…', name: 'Badge')
Widget badge(FigmaProps f) => AcmeBadge(
  label: f.text('label'),
  tone: f.variant('tone', {'success': AcmeBadgeTone.success, 'danger': AcmeBadgeTone.danger}),
);

// partial: parte vem do Figma, parte a LLM decide com o norte (f.guided)
// sketch: sem função; a LLM monta com a API do widget (bom para templates do acme_templates)
@FigmaConnect.sketch(key: 'e5eab15a…', name: 'Template / Extrato', guide: 'Cada grupo de dia vira um AcmeStatementDay.')
typedef StatementTemplate = AcmeStatementTemplate;
```

- **Key:** está no retrato (`figma_library.json`, item 7): nome do componente → key.
- **Qual nível usar:** comece com `sketch` para ter cobertura rápida; passe a `complete` os componentes mais usados.
  Detalhes e exemplos: [FIGMA_CONNECT.md §2 e §5](FIGMA_CONNECT.md#5-cobertura).
- **Componente do Acme sem mapeamento** aparece nas telas como `gap` ("componente do DS sem mapeamento"): é a fila de
  trabalho do design ops.

**Conferir:** o `doctor` conta os mapeamentos (`mappings.components`); o `resolve` de uma tela real mostra quantas
instâncias ficaram `gap`.

## 6. Docs e exemplos (opcional)

Quando a LLM erra o uso de um componente, um `.md` em `acme_figma/docs/` com seções `## Geral`, `## <parte>` e
`## Erros comuns`, ligado por `docs: [Doc.path(...)]` na anotação, e um exemplo que compila (`Example.code`). Entram no
brief só nas telas que usam o componente. Ver [FIGMA_CONNECT.md §6](FIGMA_CONNECT.md#6-docs-e-exemplos).

## 7. Retrato da biblioteca

Diz à CLI o que é do Acme e o que é de outra biblioteca. Sem ele, todo componente de biblioteca vira "do DS".

1. No arquivo **publicado** do Acme no Figma (não numa cópia: cópia tem keys novas), abra uma página de componentes
   e rode o plugin figma2dart **sem nada selecionado** (modo biblioteca). Repita para cada página.
2. `figma2dart library <zip da página 1> <zip da página 2> …`
3. Versione o `acme_figma/figma_library.json`.

Quando uma página mudar (componente novo, renomeado), exporte só ela e rode `library` com ela: substitui a página
anterior.

**Conferir:** o `doctor` mostra as páginas e a data de cada uma em `library`; sem retrato, um aviso em `warnings`.

## 8. Fontes (revisão visual)

A revisão visual renderiza a tela num teste de widget e carrega as fontes pelo `FontManifest.json` do app. Basta o
Acme declarar as fontes no `pubspec.yaml` dele (`flutter: fonts:`), como já faz para o app usar. Fonte que só existe
no aparelho (do sistema) não entra no teste: o texto sai em outra fonte, e o critério da revisão manda ignorar
diferença de renderização de fonte. Nada a configurar além disso.

---

## Quando o Acme muda

| Mudou no Acme | O que fazer |
|---|---|
| Componente novo no Figma | exportar a página dele e rodar `library`; criar o mapeamento (item 5) |
| Componente renomeado ou apagado | exportar a página e rodar `library`; ajustar ou apagar o mapeamento |
| API de um widget mudou | ajustar o mapeamento; `figma2dart doctor` aponta mapeamento que não compila |
| Nova coleção de variáveis | uma linha na tabela de tokens (item 2) |
| Token com nome diferente no código | comentário `` /// `nome-no-figma` `` no membro |
| Ícone novo com nome diferente | entrada em `byKey` (item 3) |
| Nova extensão do tema (`context.acmeX`) | `via:` na linha da coleção |

**Sinais de que falta configuração**, nos briefs que os times geram:

| No brief ou no `doctor` | Falta |
|---|---|
| `(sem Dart, …)` | token na tabela (item 2) |
| `TODO(f2d): ícone` | ícone no enum ou em `byKey` (item 3) |
| instância `gap` (DS sem mapeamento) | mapeamento (item 5) |
| componente do Acme oferecido como "a construir" | retrato desatualizado: falta a página dele (item 7) |
| componente de outra biblioteca como `gap`; `warnings` "sem retrato do DS" | retrato (item 7) |
