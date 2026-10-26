# figma_connect

API dos mapeamentos Figma → Flutter do figma2dart. Define a anotação `@FigmaConnect`, o que a função anotada pode
ler do Figma (`FigmaProps`) e a política por tipo de componente (`FigmaPolicy`).

O pacote **só define tipos**: não roda no app (a exceção é `capture.dart`, abaixo, que roda em teste). Quem lê as anotações é a CLI `figma2dart`, que gera o código e
monta o brief para a LLM. **O widget do DS não é alterado**: os mapeamentos ficam num pacote à parte
(`carteira_ds_figma`).

- Referência completa da API: [docs/FIGMA_CONNECT.md](../docs/FIGMA_CONNECT.md)
- Captura para a revisão visual (`package:figma_connect/capture.dart`, só em teste de widget): `figmaCapture`
  renderiza a tela no tamanho do frame do Figma, com as fontes do app, para o `figma2dart review`. É por ela que o
  pacote depende do `flutter_test`. Ver [FIGMA_CONNECT.md §10.1](../docs/FIGMA_CONNECT.md#101-captura-para-a-revisão-visual-figmacapture)
- Onde o pacote entra na ferramenta: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md), seções 7 e 10

## Instalação

No pacote de mapeamentos, como dependência local:

```yaml
dependencies:
  figma_connect:
    path: ../../figma_to_code/figma_connect
```

## Uso

Um arquivo `*.figma.dart` por componente. A função é um template: o gerador troca cada `f.*` pelo valor da
instância no Figma.

```dart
import 'package:figma_connect/figma_connect.dart';

@FigmaConnect(key: 'b3e1…', name: 'Badge')
Widget badge(FigmaProps f) => DsBadge(
  label: f.text('label'),
  tone: f.variant('tone', {'neutral': DsBadgeTone.neutral, 'success': DsBadgeTone.success}),
);
```

Componente que não bate 1:1 com o Figma marca `coverage: Coverage.partial` e deixa um norte para a LLM (`guide`,
`f.guided`, `figmaNotes`, `devNotes`, `docs`, `examples`). Exemplo completo de template parcial:
[docs/FIGMA_CONNECT.md, seção 2](../docs/FIGMA_CONNECT.md#2-do-mínimo-ao-completo).

Para um componente que não vale mapear, `@FigmaConnect.sketch(..., guide: '...')` anota um `typedef` para a classe
do DS (`typedef StatementTemplate = DsStatementTemplate;`), sem função; a LLM monta o widget com a API dele e os
dados do Figma ([seção 5](../docs/FIGMA_CONNECT.md#5-cobertura)).

Para um widget **do app** (fora do DS) que já existe, `@FigmaLocal(key: '…', name: '…')` sobre um `typedef`, em
`figma/connect/` do pacote do widget; `figma2dart link` escreve o arquivo
([seção 5.1](../docs/FIGMA_CONNECT.md#51-componente-do-app-que-já-existe-figmalocal)).

`FigmaPolicy(tokens: TokenTable(...))` liga as coleções de variáveis do Figma às classes de tokens do DS, estáticas
ou pelo tema; os briefs já saem com o código Dart do token ([seção 7.3](../docs/FIGMA_CONNECT.md#73-tokens)).

## Anotar o DS com o agente

As anotações do DS não precisam ser escritas à mão. O agente `figma-ds-mapper` lê o arquivo do DS pelo MCP do
Figma (só leitura), faz o inventário do que falta anotar e escreve as anotações em lotes: o `*.figma.dart`, o doc
quando há parte guiada, a linha do README e os casos do teste. A skill `figma2dart-connect` diz como anotar cada
componente. Os dois ficam em [agent/](agent/). Para usar, copie para o pacote de mapeamentos:
`agents/` → `.github/agents/` e `skills/` → `.agents/skills/` (Copilot e opencode leem essas pastas).

## O que o pacote exporta

| Arquivo | Conteúdo |
|---|---|
| `lib/src/annotation.dart` | `@FigmaConnect`, `@FigmaLocal`, `@FigmaScreen`, `FigmaKind`, `Coverage`, `Status` |
| `lib/src/guidance.dart` | `FigmaNote`, `DevNote`, `Doc`, `Example` |
| `lib/src/props.dart` | `FigmaProps`, `FigmaScreenProps` |
| `lib/src/policy.dart` | `FigmaPolicy`, `KindPolicy`, `IconTable`, `Field`, `BriefDepth` |

Tudo é importado por `package:figma_connect/figma_connect.dart`.

## Desenvolvimento

```bash
flutter pub get
flutter analyze
flutter test
```

`test/api_test.dart` escreve mapeamentos como os da referência (componente, template parcial, ícone, tela e
política) e confere que compilam, inferem os tipos e guardam os valores. Mudou a API: atualize o teste e o
[FIGMA_CONNECT.md](../docs/FIGMA_CONNECT.md) no mesmo PR.

## Status

Os tipos estão prontos. A CLI que os consome (geração, brief e validação) ainda não existe: ver o roadmap em
[ARCHITECTURE.md](../docs/ARCHITECTURE.md#14-roadmap).
