# 04 · Tokens já em Dart

**Status: feita.** Decisão: o Acme expõe tokens pelo tema, por extensão do `BuildContext` (`context.acmeSpacing.md`,
cores e o resto também): `TokenSource(..., via: 'context.acmeSpacing')`. Constantes estáticas (Carteira) seguem
funcionando sem `via`.

## Problema

O brief cita tokens pelo nome do Figma (`Spacing/md`, `Color/text/secondary`, `label`) e a LLM tem que achar a
constante do DS com busca. Funciona no Carteira porque cada constante tem o nome do Figma no comentário
(`` /// `md` = 12 ``), mas é a etapa que mais erra e custa uma busca por token. Em DS sem esse comentário vira
chute.

## Proposta

Uma tabela no `FigmaPolicy` do Acme, no mesmo molde do `IconTable`:

```dart
tokens: TokenTable(
  collections: {'Spacing': AcmeSpacing, 'Color': AcmeColors, 'Radius': AcmeRadius},
  textStyles: AcmeTextStyles,
),
```

A CLI acha cada constante (analyzer): 1) nome do Figma no comentário; 2) senão, camelCase do nome. O brief passa a
mostrar `context.acmeSpacing.md` (ou `DsSpacing.md`) em vez de `Spacing/md` — na tela, nos componentes a construir e nos sketches. Token sem
correspondência vai para a lista "sem token Dart" no brief, com o valor.

## Tarefas

- [x] `figma_connect`: `TokenTable` no `FigmaPolicy`.
- [x] CLI: ler a tabela, montar o índice nome do Figma → expressão Dart, usar em `structure.dart`.
- [x] Brief: token sem correspondência fica no lugar, com o nome do Figma e o valor (`Spacing/huge (sem Dart, 48)`),
      em vez de uma seção à parte.
- [x] `carteira_ds_figma`: declarar a tabela (exemplo).
- [x] Skills: tirar o passo "ache a constante com search" quando o brief já traz o Dart.

## Verificação

Teste com o pacote temporário do `policy_test`: token por comentário, por camelCase e sem correspondência.

## Decisões em aberto

- ~~O Acme usa constantes estáticas ou tema?~~ Tema, por extensão do `BuildContext`: `via` na `TokenSource`.

## Resultado

- `figma_connect`: `TokenTable(collections:, textStyles:)` e `TokenSource(Type, {via})` no `FigmaPolicy`.
- CLI (`tokens.dart`): lê a tabela com o analyzer (membro pelo nome do Figma entre crases no doc, ou camelCase;
  campo, getter, estático ou de instância) e troca os tokens do IR por código Dart antes dos briefs: `{value, token}`
  (layout, cores, bordas, raio, overrides), `sizeTokens` e estilos de texto. Sem correspondência:
  `Spacing/huge (sem Dart, 48)`.
- Legenda da estrutura diz se os tokens estão em Dart e, com tokens do tema, que o código precisa de `BuildContext` e
  não é `const`.
- Carteira: tabela declarada (`DsSpacing`, `DsRadius`, `DsColors`, `DsPrimitives`, `DsTextStyles`).

## Prova

- 63 testes: tokens do tema (`context.acmeSpacing.xxs` pelo doc `2xs`, `md` pelo camelCase, estilo de texto estático,
  `Spacing/huge (sem Dart, 48)`, aviso de `BuildContext`); os testes do Carteira passaram a esperar `DsSpacing.md`.
- Export real: todos os 20 tokens das 5 telas saíram em Dart (nenhum `sem Dart`), inclusive `Spacing/2xs` →
  `DsSpacing.xxs`.

## Limites

- Estilos de cor do Figma (paint styles) ainda saem pelo nome do estilo; só variáveis e estilos de texto têm tabela.
- O código das instâncias do DS vem dos mapeamentos (não muda); a tabela vale para layout, estilos e overrides.
