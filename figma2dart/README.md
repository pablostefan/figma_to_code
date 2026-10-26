# figma2dart

CLI que liga o export do plugin do Figma (IR) aos mapeamentos `@FigmaConnect` e entrega à LLM o código de cada
instância do DS já resolvido. Arquitetura: [docs/ARCHITECTURE.md](../docs/ARCHITECTURE.md), seções 9 e 10.

**Fase 1 (atual): `resolve`.** Para cada instância da tela, acha o mapeamento (pela `mainComponentKey`, depois pela
`componentKey` e pelo `when`) e reescreve o corpo da função trocando cada `f.*` pelo valor do Figma. O resto do
código do mapeamento fica igual. Partes guiadas viram `/* f2d:guided Gn parte */ <valor provisório>`, componentes
locais viram placeholder. A escrita da tela inteira (layout, `@FigmaScreen`) é a fase 2.

## Quem usa: o agente

Quem opera a CLI é o agente `figma-to-flutter` (Copilot), não a pessoa. Ela pede "implementa a tela X do Figma";
o agente roda os comandos com `--json`, pergunta só o que é escolha dela (tela, construir ou não cada componente
fora do DS) e confere com `check`. Agente e skills ficam em [agent/](agent/) e o `init` instala no app.

```
agent/
  agents/figma-to-flutter.agent.md         orquestrador: etapas, quando perguntar, relatório
  agents/figma-component-builder.agent.md  subagente: constrói um componente fora do DS
  agents/figma-visual-reviewer.agent.md    subagente: revisa a tela contra o Figma (não edita código)
  skills/figma2dart-setup/                 descobrir caminhos e resolver o que o doctor apontar
  skills/figma2dart-screen/                escrever a tela a partir do BRIEF.md
  skills/figma2dart-component/             construir um componente a partir do brief de construção
  skills/figma2dart-review/                revisão visual depois do check: captura, review, revisor, correções
```

## Instalar

```bash
<pasta da CLI>/tool/figma2dart setup   # uma vez por máquina: põe o comando figma2dart em ~/.pub-cache/bin
```

Num monorepo com rake, copie [tool/figma2dart.rake](tool/figma2dart.rake) para `rakelib/` (ou cole no `Rakefile`):
cada pessoa roda `rake figma2dart:setup`, de qualquer pasta do repositório. A tarefa acha a CLI pelo índice do git
e avisa se `~/.pub-cache/bin` não está no PATH.

O comando instalado não é uma cópia da CLI: em cada chamada ele usa a CLI do repositório git de onde foi chamado
(achada pelo índice do git, `**/bin/figma2dart.dart`, onde quer que esteja num monorepo) e, fora de um, a do
`setup`. Roda de dentro da pasta da CLI com `dart run`, que usa o executável em cache (~1 s de partida; recompila
sozinho depois de um `git pull`) e escreve o "Building…" no stderr: o stdout fica só com o JSON. O `pub get` da CLI
roda sozinho quando falta.

Num app só: `figma2dart init` cria o `figma2dart.yaml`, `.figma2dart/` no `.gitignore` e instala agente e skills; o
pacote de mapeamentos do DS entra como `dev_dependency` do app e a CLI o acha sozinha.

## Monorepo

Nenhum caminho fixo. De qualquer pasta do repositório, a CLI acha:

| O quê | Como |
|---|---|
| Pacote alvo | `--package <pasta>`, ou o `pubspec.yaml` mais próximo (o da raiz sem `lib/`, do melos, não conta) |
| Config do repo | o `figma2dart.yaml` versionado que tem `mappings:` (pelo índice do git: precisa de `git add`) |
| Config do pacote | `figma2dart.yaml` no pacote, opcional; vence o do repo |
| Mapeamentos | `mappings:` (relativo ao config), a dependência do pacote com `lib/connect`, ou o único pacote do repo com `lib/figma_policy.dart` |
| `pub get` | roda sozinho no pacote alvo e no de mapeamentos quando falta o `package_config` ou o pubspec mudou (saída no stderr) |

```yaml
# config do repo, ex.: libraries/design_ops/packages/figma2dart/figma2dart.yaml
mappings: ../acme_figma   # relativo a este arquivo
screens: lib/figma        # padrão para todo pacote; relativo ao pacote
```

## Comandos

Todos aceitam `--json` e `--package <pasta>`; erro com `--json` sai como `{"error": …}` no stdout.

| Comando | Faz |
|---|---|
| `setup` | põe o comando `figma2dart` no PATH (veja Instalar) |
| `doctor` | pacote, repositório, configs lidos, mapeamentos (validados, com os `@FigmaLocal` do app em `local`), retrato do DS (páginas e data), exports, pasta das telas; `problems` com a correção e `warnings` (sem retrato, `@FigmaLocal` ignorado) |
| `packages [<texto>]` | pacotes do repositório cujo caminho ou nome contém o texto, os que usam o DS primeiro (`ds`), sem `example/`; até 30 |
| `screens [<zip>]` | telas e estados do export, ordem do fluxo, quantas instâncias ficam fora do DS |
| `resolve [<zip>] --screen <nome>…` | `--screen` repetível: carrega os mapeamentos uma vez e escreve uma pasta de tarefa por tela (a pasta padrão recomeça do zero). Devolve `tasks`, cada uma com `brief`, `image`, `screenFile` e `components` (todos os caminhos absolutos) (`kind`: `build` com `widgetFile`, `class`, `dependsOn`; `sketch`/`local` com `widget` e `import`; `build` ganha `existing` quando uma classe de mesmo nome já existe no app) |
| `check <arquivo.dart>…` | marcadores que sobraram (`guided`, `gap`, `sketch`, `local` reprovam; `placeholder`, `inferred` e `TODO(f2d)` só contam) + `dart analyze`; sai com 1 se reprovar. Mais `hints`, que **não reprovam**: valor solto com o token do mesmo valor (`EdgeInsets.all(12)` → `DsSpacing.md`), widget a montar que sumiu, parâmetro da API proposta ausente, texto do Figma ausente (o `resolve` grava em cada tarefa o `check.json` com o que esperar). `// f2d:inferred` na linha cala a dica de valor solto |
| `review --screen <tela>` | revisão visual, depois do `check`. Sem captura: põe o `figma_connect` nas dev_dependencies e devolve `capture: false` com `testFile` e o modelo do teste (`figmaCapture`, [FIGMA_CONNECT §10.1](../docs/FIGMA_CONNECT.md#101-captura-para-a-revisão-visual-figmacapture)). Com captura: grava `review/` na tarefa com `screen.png` (Figma \| Flutter), um par por seção (pela caixa do Figma), `facts.json` (texto ausente, fora de ordem, só no Flutter, cortado, overflow; nada em pixel) e o `REVIEW.md` com o critério (importa / talvez / ignorar) e a estrutura de cada seção como base. Não dá veredito: quem revisa é o subagente `figma-visual-reviewer` |
| `library [<zip>…]` | grava o retrato do DS (`figma_library.json`: key e nome de cada componente) no pacote de mapeamentos, a partir de exports do plugin em modo biblioteca; uma página por export, a mesma página de novo substitui. Sem zip: o `figma2dart-library-*.zip` mais novo |
| `link <key> <arquivo.dart>[#Classe] [--name <nome>]` | liga um componente do Figma (key inteira, 40 caracteres: a do `components[].key` do `resolve`) a um widget do app que já existe: escreve o `@FigmaLocal` em `figma/connect/` do pacote do widget e põe o `figma_connect` nas dev_dependencies, se faltar. O widget tem que estar no pacote da tela ou numa dependência direta dele (é onde o `resolve` procura) |
| `init [--force]` | app só: config, `.gitignore`, agente e skills (não sobrescreve sem `--force`) |

Sem `<zip>`, usa o `figma2dart-*.zip` mais novo da pasta de exports. Opções de `resolve`: `--state`, `--out`,
`--mappings` (passam por cima do que a CLI descobre).

`figma2dart.yaml` (tudo opcional; caminhos relativos ao arquivo, menos `screens`, relativo ao pacote):

```yaml
mappings: ../design_system/carteira_ds_figma   # senão: veja Monorepo
exports: ~/Downloads                            # onde o plugin salva os zips
screens: lib/figma                              # telas geradas; componentes novos em <screens>/widgets/
```

Saída:

- `BRIEF.md` — ponto de entrada da LLM: código de cada instância, estrutura da tela (layout com tokens),
  navegação do protótipo, decisões (`f2d:guided`), regras e docs dos componentes, o que ficou fora do mapeamento.
- `resolved.json` — o mesmo em JSON, para o MCP e testes.
- `components/<nome>/BRIEF.md` + `component.json` — **brief de construção** de cada componente fora do DS da tela
  (dependências primeiro): onde criar (`widgets/<nome>.dart` na pasta da tela), API proposta pelas props do Figma
  (mais um parâmetro por prop de instância exposta que muda entre os usos), estrutura com tokens (tamanhos,
  padding por lado, espaço entre, sombra, opacidade, clip, posição absoluta, limites, alinhamento e trechos de
  texto, overrides legíveis) e as instâncias do DS já resolvidas com o tamanho no Figma, uma árvore só e o que muda
  em cada variante, SVG dos componentes só de vetor, usos na tela com as instâncias expostas. Construir é escolha do usuário; até lá
  fica o placeholder.

Exemplo do que sai para o Input de senha do Login:

```dart
DsInput(
  label: 'Senha',
  placeholder: '••••••',
  helper: null,
  errorText: 'Senha incorreta. Tente novamente.',
  leadingIcon: DsIconName.lock,
  trailing: DsIconButton(
  icon: DsIconName.eye,
  variant: DsIconButtonVariant.ghost,
  showDot: false,
  semanticLabel: /* f2d:guided G2 semanticLabel */ '',
  onPressed: /* f2d:guided G3 onPressed */ () {},
),
  obscureText: /* f2d:guided G4 obscureText */ false,
)
```

## Como o corpo do mapeamento é avaliado

| No mapeamento | Vira |
|---|---|
| `f.text('x')` | o texto do Figma, como literal Dart. Vale para `text`, `boolean`, `variant` e `icon`: a prop que não está no componente é procurada nas instâncias expostas dele (a base travada do `Button Icon`); em duas expostas, é lacuna pedindo `f.nested` |
| `f.boolean('x')` | `true`/`false`; num ternário, só o ramo escolhido fica |
| `f.variant('x', {...})` | o valor do mapa para a opção do Figma; opção sem entrada é erro |
| `f.icon('x')` | `Enum.valor` pela convenção (`arrow-up-right` → `arrowUpRight`), conferido contra o enum |
| `f.nested('p').text('x')` | lê a instância exposta `p` |
| `f.instance('p')` | a instância exposta `p`, resolvida pelo mapeamento dela |
| `f.guided('parte', or: v)` | `/* f2d:guided Gn parte */ v` + entrada nas decisões |
| `_helper(f)` | função do mesmo arquivo, avaliada no lugar |

Mapeamento `@FigmaConnect.sketch` (um `typedef` para a classe do DS, sem função) não é avaliado: a instância vira
`/* f2d:sketch Componente → Widget */` + placeholder, e a tarefa `components/<nome>/BRIEF.md` traz o norte, a **API
do widget** lida do código do DS (construtores, parâmetros, tipos auxiliares e enums), os dados de cada instância no
Figma, docs e exemplos. Mapeamentos `partial` também mostram a API do widget no brief da tela. Com export IR 1.3, cada instância a montar traz o conteúdo de dentro (textos e instâncias, com props) e um recorte do
PNG da tela só com ela (`components/<nome>/<id>.png`, pela caixa da instância e a escala do PNG). `@FigmaLocal` (widget
do app que já existe) segue o mesmo caminho com o marcador `f2d:local`, o `import` do widget e sem docs do DS.

## Ícones e imagens

- Ícone: exceção do `IconTable.byKey` pela `mainComponentKey`, senão o nome do Figma em camelCase, conferido contra o
  enum (`IconTable(values:)`) ou contra as constantes estáticas da classe de ícones (`IconTable.constants(AcmeIcons)`,
  quando o parâmetro do widget não é enum). Nos dados do Figma de sketches e placeholders, o ícone já sai como código (`"DsIconName.arrowUpRight"`).
- Ícone que não existe no enum não derruba o componente: fica o primeiro valor do enum com
  `/* TODO(f2d): ícone "x" do Figma não existe em DsIconName */`.
- Imagem (preenchimento `IMAGE`) e vetor solto: a estrutura mostra um `Placeholder` do tamanho do nó com `TODO(f2d)`
  (o export ainda não traz os arquivos).
- Enum com mais de 30 valores entra cortado na API do widget, com o total e onde está a lista inteira.

## Docs e exemplos no brief

Seção "Componentes desta tela" do `BRIEF.md`, uma vez por componente (FIGMA_CONNECT §6 e §9):

| Componente | Entra |
|---|---|
| `complete` sem regra nem decisão na tela | nada (já está resolvido no código) |
| `complete` com decisão (`f.guided`) na tela | `devNotes` + do doc só `## Geral`, as seções das partes decididas e `## Erros comuns` |
| `partial` / `sketch` | norte + `devNotes` + doc inteiro (até 150 linhas) |

- Doc: os `docs` da anotação ou, sem eles, `docs/<arquivo>.md` do pacote com o nome do `*.figma.dart`. Caminhos
  relativos à raiz do repositório (a busca sobe a partir do pacote de mapeamentos). Arquivo ou seção que não existe
  aparece marcado no brief.
- Exemplo: no máximo 1 `Example.code` (modelo) e 1 `Example.usage` (contexto), extraídos pelo símbolo com o
  analyzer (`Classe`, `funcao` ou `Classe.metodo`); acima de 60 linhas entra só o caminho e a dica.

## Testes

```bash
dart test
```

Usam os exports reais em `test/fixtures/` (Login do plugin e o fluxo do MCP) e os mapeamentos do
`design_system/carteira_ds_figma`, que precisa estar no repositório irmão com `flutter pub get` feito.

## Limitações conhecidas

- O código de cada instância não é formatado nem tira argumentos iguais ao padrão (`leftIcon: null`): fase 2.
- "Do DS" é a key estar no retrato (`figma2dart library`); sem retrato, vale `remote` no IR, e componente de outra
  biblioteca vira `gap` por engano.
- `existing` procura `class <Nome>` por texto no `lib/` do pacote e das dependências por path dele: nome diferente
  do Figma não é achado, e nome igual de outra coisa é falso positivo (o agente pergunta antes de ligar).
- Do `FigmaPolicy`, a CLI lê `ignored` (e o prefixo `_`/`.`), os `devNotes` de cada tipo, o `IconTable`
  (`values` e `byKey`) e o `TokenTable` (tokens já em Dart nos briefs; paint styles ainda pelo nome). `require`, `expectedCoverage` e `BriefDepth` ainda não: não há validação de cobertura.
- O `@FigmaScreen` entra no brief como código ("Esqueleto da tela"); a montagem da tela com ele é da LLM (fase 2
  gera).
- `docs`/`examples` de uma parte (`f.guided(docs:, examples:)`) não são lidos: use a seção `## <parte>` no doc do
  componente. `Doc.link` sem `source` entra só com o `hint` (não baixa nem guarda em cache).
- O analyzer leva ~6 s (13 mapeamentos) para carregar os mapeamentos a cada execução, e mais ~1,5 s por pacote com
  `figma/connect/` (as análises dividem o cache do SDK): peça todas as telas num `resolve` só.
- `@FigmaLocal` que não compila (widget renomeado), com key do DS ou repetida fica de fora com aviso (`warnings` no
  `doctor` e no `resolve`): o componente volta a ser "a construir" e as outras telas seguem.
- O `pub get` automático roda quando falta o `package_config.json` ou o `pubspec.yaml` é mais novo; depois dele a
  CLI atualiza a data do `package_config.json` (o pub não regrava sem mudança de dependência).
- O comando instalado é um script `sh`: no Windows ainda não há equivalente.
- O config do repo é achado pelo índice do git: um `figma2dart.yaml` novo só vale depois de `git add`.
- `packages` marca `ds` só por dependência direta de um pacote do DS (as dependências por path do pacote de
  mapeamentos); quem usa o DS por um pacote intermediário sai `false`.
