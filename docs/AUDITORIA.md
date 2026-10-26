# Auditoria da solução figma-to-code — plano de correções

Data: 2026-10-25. Escopo: `figma_plugin`, `figma_connect`, `figma2dart` (CLI, briefs, sketch, API do widget, docs e
exemplos, agente e skills), `design_system/carteira_ds_figma`, `carteira_ds_examples`, widgets novos do
`carteira_design_system` e o setup do `carteira_sample_app`.

**O que é:** um fluxo de Figma para Flutter. O plugin exporta a tela (IR), os mapeamentos `@FigmaConnect` ligam os
componentes do Figma aos widgets do DS, e a CLI `figma2dart` gera os briefs da tela, dos componentes a construir e
dos sketches a montar. Um agente do Copilot opera essa CLI e implementa a tela.

**Carga considerada:** uma pessoa por vez, algumas telas por fluxo, DS real com mais de 300 componentes e muitos
ícones.

**Verificado antes da auditoria:**

| Pacote | Resultado |
|---|---|
| `figma2dart` | analyze limpo, 43 testes passando |
| `figma_connect` | analyze limpo, 4 testes |
| `carteira_design_system` | analyze limpo, 12 testes |
| `carteira_ds_figma` | analyze limpo, 29 testes |
| `carteira_ds_examples` | analyze limpo, 2 testes |
| `carteira_sample_app` | analyze limpo (sem testes) |
| `figma_plugin` | typecheck, testes e validação dos exemplos passando |
| CLI ponta a ponta | `doctor`, `screens`, `resolve` e `check` no `carteira_sample_app` |

Nada quebra no uso esperado. Os achados são o que ainda não funciona como os documentos de arquitetura
([ARCHITECTURE](ARCHITECTURE.md) e [FIGMA_CONNECT](FIGMA_CONNECT.md)) prometem.

**Status (2026-10-25):** os 8 itens foram implementados. Decisões tomadas nos pontos em aberto:

- `TODO(f2d)` não reprova o `check`: conta e entra no relatório (`todos`), como o placeholder.
- Valor provisório do ícone: o primeiro valor do enum. O "neutro por enum" no `FigmaPolicy` fica para quando
  houver necessidade.
- Item 4 implementado (não só documentado): `ignored` e prefixo `_`/`.`, `devNotes` por tipo, `figmaNotes` e
  `IconTable` (`values` e `byKey`). Fora: `require`, `expectedCoverage` e `BriefDepth` (validação de cobertura).
- Item 6: `--screen` repetível; o agente pede todas as telas num `resolve` só. A medição com o DS real continua
  pendente.
- Ilustrações como componente com enum: resolvidas como ícone quando o mapeamento usa `f.icon`; a tabela própria
  espera a resposta sobre o DS real.

Verificação: `figma2dart` com 48 testes (cada item tem teste), analyze limpo em todos os pacotes.

Revisão depois da implementação (três falhas encontradas lendo o código novo, já corrigidas e com teste):

- Instância ignorada pela política sumia da lista, mas aparecia na "Estrutura da tela" como uma instância comum;
  agora aparece como **não implementar**.
- Duas telas pedidas no mesmo `resolve` com o mesmo nome sem a numeração (`05 · Sucesso`, `07 · Sucesso`) iam para a
  mesma pasta e a segunda apagava a primeira; agora a segunda ganha o id do frame no nome.
- Componente local que é só vetor (um logo) virava um placeholder por pedaço; agora é um só.

**Veredito:** funciona e está pronto para o teste com o Luna. Antes do teste, corrigir 1, 2 e 3: são os que mudam o
que o modelo recebe (o 3 inclui o placeholder com `TODO(f2d)` para ícone e imagem).

---

## Deveria corrigir

### 1. O esqueleto da tela (`@FigmaScreen`) nunca chega ao brief

- [x] Decidido · [x] Feito

`figma2dart/lib/src/mappings.dart`, `figma2dart/lib/src/brief.dart`

- **O que é:** o `screen.figma.dart` do Carteira define a regra de toda tela:
  `Scaffold(backgroundColor: DsColors.bg, body: SafeArea(...))`.
- **Problema:** a CLI só lê `@FigmaConnect`. A skill da tela manda usar "a regra de tela do DS, se houver", mas o
  agente não tem como encontrá-la. Na Confirmar, por exemplo, ele pode escrever um `Scaffold` sem o fundo e sem o
  `SafeArea`.
- **Correção:** no `loadMappings`, guardar o código da função anotada com `@FigmaScreen`; no brief da tela, uma
  seção "Esqueleto da tela" com esse código, onde `s.body()` é o conteúdo da tela. Cerca de 15 linhas.
- **Se não corrigir:** cada tela gerada sai com um esqueleto diferente e o revisor corrige à mão.

### 2. Docs e exemplo do sketch aparecem duas vezes

- [x] Decidido · [x] Feito

`figma2dart/lib/src/brief.dart`, seção "Componentes desta tela"

- **O que é:** essa seção do brief da tela mostra o norte, os docs e os exemplos dos componentes que não são
  `complete`.
- **Problema:** o sketch também entra nela, e o mesmo conteúdo já está no brief de montagem dele. Testado: o brief
  da tela com o `Template / Extrato` traz o doc inteiro e a classe `StatementExample`, e o
  `components/template_extrato/BRIEF.md` repete tudo.
- **Correção:** filtrar `coverage != 'sketch'` em `described`. Uma condição; o brief da tela continua apontando
  para o do sketch.
- **Se não corrigir:** é texto em dobro para o Luna ler, e o modelo pode montar o sketch pelo brief da tela, que não
  tem a API do widget.

### 3. Ícones e imagens: enum gigante na API, valor que não resolve

- [x] Decidido · [x] Feito

`figma2dart/lib/src/api.dart` (`_interface`), `figma2dart/lib/src/resolve.dart` (`_icon`),
`figma2dart/lib/src/component_brief.dart` (brief do sketch), `figma2dart/lib/src/commands.dart` (`check`)

- **O que é:** a API extraída do código do DS lista os valores de cada enum usado pelos parâmetros.
- **Problema:**
  - No DS real, com muitos ícones, qualquer sketch ou parcial que receba um ícone despeja o `DsIconName` inteiro,
    com centenas de valores, no brief.
  - Cortar a lista sozinho cria outro risco: no sketch, o ícone chega cru dos dados do Figma
    (`{"variant": {"name": "arrow-up-right"}}`) e a LLM converte pela regra do nome. Se o ícone foge da regra e não
    está na parte visível da lista, ela erra o nome. O analyzer reprova no `check`, então o erro não passa calado,
    mas custa uma rodada.
  - Hoje, um ícone que não existe no enum derruba a instância inteira, que vira `f2d:gap` com `Placeholder()`. O
    componente some da tela por causa de um ícone.
  - Imagens do Figma (preenchimento `IMAGE`) não têm arquivo no export (asset é roadmap). Na estrutura aparece só
    `fill IMAGE`, sem orientação.
- **Quando a falta de uma opção na lista pode gerar erro:**

  | Caso | Risco |
  |---|---|
  | Ícone vem do Figma num mapeamento `complete`/`partial` | nenhum: a CLI converte e confere contra o enum |
  | Ícone vem do Figma num sketch | a LLM converte pela regra; ícone fora da regra e fora da lista visível sai errado (o analyzer reprova no `check`) |
  | Ícone não está no Figma e a LLM escolhe | precisa conhecer as opções; raro, o Figma quase sempre define o ícone |

  O erro silencioso seria um ícone válido mas errado, e esse risco é o mesmo com ou sem a lista completa.

  **Imagens seguem a mesma regra**, conforme como aparecem no Figma:

  | Caso | Hoje | Proposta |
  |---|---|---|
  | Ilustração do DS como componente, mapeada para um enum (`f.icon` aceita qualquer enum, ex.: `DsIllustrationName`) | igual ao ícone: resolve pela convenção; nome inexistente derruba a instância | igual ao ícone: resolvida e validada pela CLI; enum grande cortado com caminho; nome inexistente vira valor provisório + `TODO(f2d)` |
  | Foto ou bitmap (preenchimento `IMAGE` num frame) | só `fill IMAGE` na estrutura; o export não traz o arquivo | `Placeholder` do tamanho do nó + `TODO(f2d)` com nome e id do nó; quando o plugin exportar assets, o TODO aponta o arquivo na pasta da tarefa |
  | Vetor solto, fora de componente | aparece como camada na estrutura | `Placeholder` do tamanho do nó + `TODO(f2d)`; quando houver SVG no export, o TODO aponta o arquivo |
- **Correção:**
  1. **Ícone já resolvido nos dados do Figma:** no brief do sketch, a CLI converte as props de ícone para o nome
     Dart, validado contra o enum (`"icon": "DsIconName.arrowUpRight"`), usando a mesma conversão dos mapeamentos e,
     quando o item 4 entrar, as exceções do `IconTable.byKey`. A LLM não converte nada.
  2. **Enum grande cortado com caminho:** acima de cerca de 30 valores, mostrar os primeiros e uma linha com o
     total, a regra do nome e o arquivo onde o enum está declarado:
     `… 412 valores, nome do Figma em camelCase; lista em carteira_design_system/lib/src/components/ds_icon.dart`.
     Enum pequeno continua inteiro.
  3. **Valor que não resolve vira placeholder com TODO, não lacuna:** ícone que não existe no enum (ou que não dá
     para ler) mantém a instância mapeada, com um valor válido qualquer (o primeiro do enum) e o aviso no código:

     ```dart
     leadingIcon: /* TODO(f2d): ícone "cartao-novo" do Figma não existe em DsIconName */ DsIconName.home,
     ```

     Imagem do Figma sem arquivo vira um placeholder do tamanho do nó com TODO:

     ```dart
     /* TODO(f2d): imagem do Figma "banner" (12:345), asset ainda não exportado */
     const SizedBox(width: 342, height: 120, child: Placeholder()),
     ```

  4. **`check`:** conta os `TODO(f2d)` e lista no relatório, como faz com os placeholders.
- **Se não corrigir:** o brief cresce em milhares de tokens por componente; um ícone inexistente apaga o componente
  inteiro da tela; imagens ficam sem orientação.
- **Para conversar:**
  - `TODO(f2d)` bloqueia o `check` ou só entra no relatório? Proposta: só relatório (é pendência do dev, como o
    placeholder).
  - Valor provisório do ícone (e da ilustração): o primeiro do enum, ou um valor "neutro" por enum definido no
    `FigmaPolicy`?
  - O DS real tem ilustrações como componentes com enum, como os ícones? Se sim, entram na mesma tabela de nomes
    (`IconTable`) ou numa tabela própria?

### 4. `FigmaPolicy`, `figmaNotes` e `IconTable.byKey` são ignorados sem aviso

- [x] Decidido · [x] Feito

A CLI não lê nenhum dos três.

- **O que é:** a API de anotações (FIGMA_CONNECT §4.3 e §7) promete:
  - regras por tipo de componente (`KindPolicy.devNotes`);
  - componentes a ignorar (`FigmaPolicy.ignored`);
  - notas por prop do Figma (`FigmaNote.derive` / `FigmaNote.map`);
  - exceções de ícone por key (`IconTable.byKey`).
- **Problema:** nada disso chega ao brief.
  - Um time que escreve `ignored: {'4a7e': 'Anotação de handoff'}` continua vendo essa anotação como componente
    fora do DS, e o agente pergunta se deve construí-la.
  - Um `FigmaNote.derive` num componente parcial some, e era justamente o norte daquela prop.
  - O Carteira não usa nada disso hoje, então nada quebra agora. O README só cita `figmaNotes` e `byKey` como
    limitação.
- **Correção:**
  - ler a constante `FigmaPolicy` no `loadMappings`;
  - `ignored` faz o `_walk` pular a instância;
  - os `devNotes` do tipo entram junto com os do componente;
  - `figmaNotes` (`derive` e `map`) viram linhas em "Componentes desta tela".

  Alternativa menor: registrar no README e no FIGMA_CONNECT que essas partes ainda não funcionam.
- **Se não corrigir:** no piloto com o DS real, quem usar essas partes vai achar que estão funcionando.
- **Para conversar:** implementar agora ou só documentar até o piloto?

### 5. A pasta da tarefa acumula briefs antigos

- [x] Decidido · [x] Feito

`figma2dart/lib/src/commands.dart`, `resolveTask`

- **O que é:** cada `resolve` escreve em `.figma2dart/tasks/<tela>/`.
- **Problema:** se o designer remove o `SummaryRow` e você exporta de novo, o `components/summary_row/BRIEF.md`
  continua lá. O JSON está certo, mas quem listar a pasta, pessoa ou agente, encontra uma tarefa que não existe
  mais.
- **Correção:** quando a saída é a pasta padrão (dentro de `.figma2dart/`, que é só da ferramenta), apagar a pasta
  da tela antes de escrever. Com `--out`, não apagar nada. Duas linhas.
- **Se não corrigir:** o agente pode construir um componente que saiu da tela.

---

## Melhorias pequenas

### 6. Cada chamada recompila todos os mapeamentos

- [x] Decidido · [x] Feito

- **Problema:** `doctor` e cada `resolve` carregam e analisam o pacote inteiro de mapeamentos. Medido: cerca de
  10 s com 13 mapeamentos; um fluxo de 5 telas gasta uns 60 s só nisso. Com 300 componentes, o tempo cresce junto.
- **Correção:** aceitar `--screen` repetido no `resolve` (uma carga para várias telas) e fazer o agente pedir todas
  as telas escolhidas de uma vez.
- **Para conversar:** medir com um pedaço do DS real antes de decidir.

### 7. Docs citam comandos que não existem

- [x] Decidido · [x] Feito

`docs/FIGMA_CONNECT.md` §9, `docs/ARCHITECTURE.md` (diagrama e §10.6)

- **Problema:** `figma2dart brief <tela>` virou `resolve`. Quem seguir o doc recebe o texto de uso.
- **Correção:** trocar por `resolve` e indicar que o `generate` é da fase 2.

### 8. Sketch dentro de um componente local aponta para um brief que não existe

- [x] Decidido · [x] Feito

`figma2dart/lib/src/resolve.dart` (`_localComponents`), `figma2dart/lib/src/component_brief.dart`

- **Problema:** as tarefas de sketch só nascem das instâncias que estão direto na tela. Se um componente local tiver
  um template sketch dentro, a estrutura dele linka `../template_extrato/BRIEF.md`, que nunca é escrito.
- **Correção:** juntar também os sketches das variantes dos componentes locais em `_localComponents`.

---

## Achados menores (fora da lista)

- Dois mapeamentos com o mesmo `name` e `when` diferentes: o brief fica com as regras e o norte de um só (`_used`
  é indexado pelo nome).
- Um `Doc.path` relativo é procurado subindo pastas a partir do pacote de mapeamentos até a raiz do disco; um
  arquivo homônimo numa pasta acima pode ser lido por engano.

## Não verificado

- O agente rodando de verdade no Copilot: nomes das ferramentas (`execute`, `edit`, `vscode/askQuestions`) e o
  subagente.
- O modo biblioteca do plugin com a CLI (base do "retrato da biblioteca").
- Um export real com os casos parcial (`TransactionList`) e sketch (`Template / Extrato`); depende de publicar o DS.
- A escala com 300 componentes: tempo do analyzer e tamanho dos briefs.
- Windows: a CLI monta caminhos com `/` e o instalador é um script `sh`.

---

## Auditoria das questões 01–03

Depois do monorepo (01), do Acme × app (02) e do brief completo (03). Todos os itens corrigidos e verificados no
monorepo de teste (Carteira dentro de `libraries/design_ops/packages`, sample app como pacote de setor).

| # | Achado | Correção | Prova |
|---|---|---|---|
| 1 | `@FigmaLocal` quebrado (widget renomeado) travava o `resolve` de **todas** as telas; `doctor` dizia ok | anotação com problema (não compila, key do DS, repetida, `@FigmaConnect` no app, `pub get` que falha) fica de fora com aviso; `doctor` carrega o mesmo que o `resolve` e lista em `warnings`; `resolve` devolve `warnings` | `local_test`; no monorepo: Dashboard resolve, só o `ContactItem` volta a construir, `TopBar` segue `local` |
| 2 | Depois de tocar o `pubspec.yaml`, todo comando rodava `pub get` de novo (o pub não regrava o `package_config.json` sem mudança) | `ensurePubGet` e o script atualizam a data do `package_config.json` | `monorepo_test`; no monorepo: 1 `pub get`, depois 0 |
| 3 | `link` num widget de dependência indireta gravava uma anotação que o `resolve` nunca lê | `link` exige o pacote da tela ou uma dependência direta | `local_test`; erro explicando no monorepo |
| 4 | `link` recusava widget com `..` ou link simbólico no caminho | caminho real dos dois lados | `local_test` |
| 5 | Cada pacote com `figma/connect/` acmeva ~4,3 s | cache do analyzer (`byteStore`) dividido entre as análises: ~1,5 s | medido: 11,6 s → ~9 s (7,3 s sem anotação). Dividir também o `unlinkedUnitStore` não ganhou nada |
| 6 | Agente e skills do sample app eram da versão anterior | `figma2dart init --force` (config intacto) | arquivos iguais à fonte |
| 7 | `mappings()` recalculado várias vezes por comando | `late final` | — |
| 8 | Getter `configPath` sem uso | apagado | — |
| 9 | Índice do plano com decisões já tomadas como abertas | atualizado | — |

---

## Auditoria dos hints (05)

| # | Achado | Correção | Prova |
|---|---|---|---|
| 1 | Texto escrito certo em Dart (`'R\$ 150,00'`, `'d\'água'`, `\n`) virava "texto do Figma não aparece" | compara sem os escapes do Dart | `hints_test` |
| 2 | Sketch/`local` dentro de componente a construir: dica falsa na tela e nenhuma no widget do componente | o `check.json` põe o widget esperado no arquivo de quem o usa (`within`) | `hints_test` de ponta a ponta (`resolve` → `check`) |
| 3 | "nenhum token tem esse valor" quando o DS tinha (o export só traz os tokens da tela) | "nenhum token usado nesta tela…; procure no DS" | `hints_test` |
| 4 | Valor solto em chamada quebrada em linhas não era visto | busca no arquivo inteiro, linha pelo deslocamento; `f2d:inferred` cala só a linha dele | `hints_test` |
| 5 | `size: 20` (o tamanho do Figma que o brief manda passar) virava dica | `size:` só com token de tamanho do mesmo valor | `hints_test`; sample app: 2 dicas falsas → 0 |
| 6 | Sem teste para 1, 2 e 4 | 4 testes novos | 70 testes |
| 7 | Nome dos parâmetros calculado em dois lugares (brief e `check`) | uma regra só (`_propParam`, `_exposedParam`) | — |
| 8 | Texto repetido no Figma dava dica repetida | sem repetição | `hints_test` |

Além disso, as dicas saem na ordem do arquivo (as sem linha no fim).

## Validação dos exports reais (07)

Três exports do plugin novo (extrator 0.4.0, IR 1.3.0) do arquivo de exemplo do fluxo: `screen-05_sucesso`,
`flow-01_login_senha_incorreta` (5 telas) e `screen-transactions` (um pedaço do Dashboard).

**O que chegou certo**

- Os três passam no schema; `screens` e `resolve` rodam em todas as telas.
- O PNG de cada tela tem frame × `imageScale` (390×844 → 780×1688; 342×256 → 684×512) e toda `bounds` cabe nele.
- `content` traz textos e instâncias de dentro, na ordem das camadas; definições de componente não ganham caixa nem
  conteúdo; `autoResize: HEIGHT` aparece nos textos de largura fixa e vira "quebra linha (largura fixa)".
- Recorte com dado real: com o ContactItem ligado por `link` a um widget do app (numa cópia do sample app), o
  `resolve` gerou um PNG por instância (684×132 = 342×66 × 2; no Confirmar, 616×132), cada um só com o seu contato,
  e o brief `local` com o conteúdo certo (avatar, nome, detalhe, chevron).

| # | Achado | Correção | Prova |
|---|---|---|---|
| 1 | Rotação não ia para o IR: o "voltar" do TopBar é `chevron-right` girado 180°, e o brief mandava `DsIconName.chevronRight` sem dizer nada (só a descrição do designer salvava) | plugin grava `rotation` (extrator 0.4.1); a estrutura mostra "**girado 180°**" | `npm run check`; `structure_test`; export real com a rotação injetada |
| 2 | `link` aceitava a key curta do placeholder (`key 26729128`): o `@FigmaLocal` era gravado, o `doctor` contava, e o `resolve` nunca casava, sem aviso | `link` exige a key inteira (40 hex) e diz onde achar | `local_test` (cada guard confere a própria mensagem) |
| 3 | PNG da tela maior que o frame (sombra no frame, filho para fora de frame sem recorte) deslocaria todos os recortes | sem recorte quando o PNG não tem frame × escala (±1 px); o resto do brief fica | `crop_test` |
| 4 | O zip do fluxo levava o nome da primeira tela (`flow-01_login_senha_incorreta`) | nome da section selecionada ou da página, sem acento | — (só no plugin rodando no Figma) |
| 5 | Lint repetia `style-override` quando um ícone tem dois vetores com o mesmo nome (`Vector`) | o mesmo aviso no mesmo nó sai uma vez | `npm run check` |
| 6 | Brief `local`/`sketch` repetia as instâncias expostas em JSON cru (com keys) logo depois do `content` | com `content`, só ele; sem (IR 1.2), as expostas no mesmo formato compacto | `crop_test` |
| 7 | `content` trazia troca de instância de camada oculta (Avatar `type=initials` com `icon`) | o `content` tira a troca cuja camada não aparece; as props das instâncias mapeadas ficam inteiras (os mapeamentos leem) | `npm run check` |

**Não deu para validar com estes exports:** `maxLines`/reticências (nenhum texto do arquivo usa) e sketch do DS
(o `Template / Extrato` não está no fluxo).

## Auditoria geral (CLI, captura, revisão, agentes)

Contrato agente × CLI conferido campo a campo (`doctor`, `screens`, `resolve`, `check`, `review`, `link`). Os três
primeiros quebravam justamente no ambiente real: monorepo com o agente na raiz e CI.

| # | Achado | Correção | Prova |
|---|---|---|---|
| 1 | `check` chamado da raiz com `--package` e caminho relativo: o `dart analyze` (rodando no pacote) não achava o arquivo e devolvia `"ok": true` para código que nem compila | caminhos absolutos no `check` | `commands_test` (chamada com caminho relativo à pasta atual) |
| 2 | `resolve` devolvia `screenFile`/`widgetFile` (e o `review`, `testFile`) relativos ao pacote: com o agente na raiz do monorepo, a tela ia para `<raiz>/lib/…` | absolutos, como `brief` e `dir`; o `check.json` segue relativo | `commands_test`, `review_test` |
| 3 | Teste de captura versionado quebrava na CI e em outra máquina: o `review.json` fica em `.figma2dart/` (fora do git) | sem a tarefa, `figmaCapture` avisa e passa sem capturar | `capture_test` |
| 4 | `review` com PNG do Figma maior que o frame (sombra) recortava as seções deslocadas: achado falso | `coversFrame` também no `review`; sem pares por seção e aviso no `REVIEW.md` | `review_test` |
| 5 | Anotação do designer (`_Nota`, ignorada pela política) entrava nos fatos como texto ausente e aparecia no PNG sem aviso: o revisor cobraria "elemento faltando" | fora dos textos e das seções; listada em "Só do Figma (não implementar)" | `review_test` |
| 6 | Dois recortes quase iguais (brief e revisão) | um só, `cropBox` | `crop_test`, `review_test` |
| 7 | Skill de setup dizia três chaves no config; são quatro (`connect:`) | skill corrigida | — |
| 8 | `review --screen "07 · Sucesso"` resolvida com "05 · Sucesso" abria a tarefa da outra (mesmo nome base) | acha pelo nome exato gravado no `review.json` primeiro | `review_test` |
| 9 | README do `figma_connect` não citava a captura nem o `flutter_test` | parágrafo com o link para a FIGMA_CONNECT §10.1 | — |

Além disso, o teste "docs e exemplos citados pelos mapeamentos do Carteira existem" validava os dados do Carteira (e,
por eles, o sample app), não a CLI: falhava quando o sample app mudava. Virou um teste com pasta própria do mesmo
comportamento (doc e exemplo que existem entram; o que sumiu é avisado).
