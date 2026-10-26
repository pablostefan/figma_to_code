# Migração para Dart 3.5 e Flutter 3.24

**Commit:** `0578275` (`fix(compat): support Dart 3.5 and Flutter 3.24`), com o mínimo depois baixado de 3.5.3 para
**3.5.0**.
**Objetivo:** permitir executar `figma2dart` e `figma_connect` a partir do Flutter 3.24.0/Dart 3.5.0, preservando
as saídas e o fluxo existentes.

## Versões declaradas

| Pacote | Antes | Agora |
|---|---|---|
| `figma2dart` Dart | `^3.11.0` | `^3.5.0` |
| `figma2dart` analyzer | `^14.5.0` | `^7.7.1` |
| `figma2dart` lints | `^6.0.0` | `^5.0.0` |
| `figma_connect` Dart | `^3.11.4` | `^3.5.0` |
| `figma_connect` Flutter | `>=3.41.0` | `>=3.24.0` |
| `figma_connect` flutter_lints | `^6.0.0` | `^5.0.0` |

O `pubspec.lock` versionado do `figma2dart` foi regenerado com Dart 3.5.0. Ele fixa versões das dependências que
resolvem nesse SDK.

## Mudanças de código

- **Coleções:** a sintaxe de elemento opcional (`?valor`) foi trocada por `if` com padrões de nulo, que existem no
  Dart 3.5. Os campos continuam omitidos quando o valor é `null`.
- **Leitor de mapeamentos:** ajustado para a API do analyzer 7.7:
  - localização via `source.uri`;
  - nomes atuais das propriedades da AST;
  - argumentos nomeados via `NamedExpression`;
  - `packagesFile` e `errors` na análise.
- **Enums e tokens:** o acesso às constantes de enums e aos membros de tokens foi adaptado às propriedades que esse
  analyzer oferece.
- **Testes:** os de fixture que compilam código também passaram para a sintaxe do Dart 3.5.
- **Doc:** a restrição de SDK no exemplo de integração do monorepo foi alinhada em
  [MIGRACAO_MONOREPO.md](MIGRACAO_MONOREPO.md).

Não houve mudança no formato dos briefs, no código gerado, nas anotações públicas do `figma_connect` nem no
contrato IR do plugin. A comparação de saídas abaixo confirma isso.

## Arquivos abrangidos

- **SDK e dependências:**
  - `figma2dart/pubspec.yaml` e `figma2dart/pubspec.lock`;
  - `figma_connect/pubspec.yaml`;
  - o exemplo em `docs/MIGRACAO_MONOREPO.md`.
- **Compatibilidade da CLI**, em `figma2dart/lib/src/`: `api.dart`, `commands.dart`, `component_brief.dart`,
  `export.dart`, `hints.dart`, `icons.dart`, `mappings.dart`, `references.dart`, `resolve.dart`, `review.dart`,
  `structure.dart` e `tokens.dart`.
- **Fixtures de compilação:** `figma2dart/test/policy_test.dart`, `figma2dart/test/structure_test.dart` e
  `figma_connect/test/api_test.dart`.

## Por que ainda há `ignore_for_file: deprecated_member_use`

O `figma2dart` suporta Dart 3.5 com o analyzer 7.7.1. Nesse analyzer, a API antiga de elementos está depreciada e
a substituta ainda é experimental. O analyzer 8.0.0 já exige Dart `^3.7.0`, então não pode substituir o 7.7.1
enquanto o mínimo for 3.5.

As supressões ficam só nos arquivos que leem tipos e elementos do analyzer e não mudam nada em execução. Reavalie
quando o mínimo do Dart puder subir e a API substituta estiver estável. Antes de tirar a supressão, compare as
saídas.

## Validação executada

### Flutter 3.24.0 / Dart 3.5.0 (o mínimo)

- `figma2dart`: `dart analyze` sem problemas; `dart test`: 78 testes passaram.
- `figma_connect`: `flutter analyze` sem problemas; `flutter test`: 7 testes passaram, incluindo a captura.

### Mesmas saídas antes e depois

O `resolve` das 5 telas do fluxo do Carteira (`figma2dart-flow-flow.zip`, no `carteira_sample_app`) foi rodado duas
vezes:

- com o código de antes da migração (`f3aef47`, analyzer 14, Dart 3.11.4);
- com o de agora (analyzer 7.7, Dart 3.5.0).

O que foi comparado:

| Saída | Resultado |
|---|---|
| `screens --json` | idêntico |
| `resolve --json` (stdout) | idêntico, fora o caminho da pasta de saída |
| Pasta da tarefa (`BRIEF.md`, `resolved.json`, `check.json`, `review.json`, briefs e recortes dos componentes) | idêntica byte a byte nas 5 telas |

### Flutter 3.24.3 / Dart 3.5.3 e Flutter 3.41.6 / Dart 3.11.4

Validado no commit `0578275`. Nas duas versões, os dois pacotes passaram:

- `figma2dart`: análise limpa e 78 testes;
- `figma_connect`: análise limpa e 7 testes.

## Repetir a validação

Com o fvm (`fvm install 3.24.0`), ponha o SDK no `PATH`, confirme a versão com `dart --version` e rode:

```sh
export PATH=~/fvm/versions/3.24.0/bin:$PATH

cd figma2dart
dart pub get
dart analyze
dart test

cd ../figma_connect
flutter pub get
flutter analyze
flutter test
```

## Fora desta migração

Os pacotes de exemplo em `design_system/` continuam exigindo Dart `^3.11.4` e Flutter `>=3.41.0`:
`carteira_design_system`, `carteira_ds_figma`, `carteira_ds_examples` e `carteira_sample_app`.

- **A CLI não é afetada:** rodando no Dart 3.5, ela lê os mapeamentos do Carteira normalmente, e os testes e a
  comparação acima usam esses mapeamentos.
- **O que não funciona no Flutter 3.24:** compilar, testar ou rodar esses pacotes, nem o `check` de uma tela do
  sample app, que chama o `dart analyze` do app.

## Checklist para revisão posterior

- [ ] Reavaliar as supressões de depreciação só quando o mínimo do Dart puder subir e o modelo substituto do
  analyzer estiver estável.
