# 09 · Bases travadas: um widget, várias keys no Figma

## Decisão (feita)

**Uma anotação só, na key do componente público.** A anotação lê as props pelo nome. A CLI procura a prop no
componente e, se não achar, nas instâncias expostas dele, como o painel do Figma mostra. As bases (`.Icon Button /
Large`, …) não ganham anotação. A prop que aparece em duas expostas vira lacuna pedindo `f.nested`.

**Como gerar a anotação:** o usuário seleciona o público e as bases e exporta o zip em modo Componente. A instância
exposta vem com `exposedInstance: true` na `tree`, e as props dela vêm em `componentRefs`. O agente
`figma-ds-mapper` anota só o público e, antes do `flutter test`, confere cada nome usado contra o export (skill
`figma2dart-connect`, passo 6).

**Testado com um export real** (página "Teste · Bases travadas" no arquivo do Carteira DS, mesma estrutura do
Acme):

| | A: uma por base | **B: uma no público (escolhida)** |
|---|---|---|
| Anotações | 4 (43 linhas) | 1 (16 linhas) |
| `Button Icon` Large, Medium e Small | ✅ | ✅ código idêntico ao de A |
| Base solta na tela | ✅ | ❌ fica de fora, como "só do Figma" |
| Tempo do `resolve` | ~9 s | ~9 s (o custo é o analyzer) |

- **O que o export mostrou:**
  - o caminho da base (`✏️ Icon Button`) é igual nos três tamanhos;
  - só a key da base muda;
  - as props da base chegam em `exposed`.
- **Base solta:** só aparece se alguém desanexar o público (componente com `.` não é publicado). Se aparecer num
  export real, a saída é o `locked` da proposta B abaixo.
- **Também entrou:** a correção do prefixo `.`/`_`. Ele só esconde componente sem anotação própria.
- **Feito:**
  - `_Scope.prop` em `figma2dart/lib/src/resolve.dart`, com o teste `figma2dart/test/locked_variants_test.dart`;
  - skill `figma2dart-connect` e agente `figma-ds-mapper`;
  - FIGMA_CONNECT §3.3 e §4.1, README da CLI e COMO_FUNCIONA.

O que vem abaixo é a análise que levou à decisão.

## Problema

No Acme, um componente público costuma embrulhar **bases travadas**. Exemplo real, da página Buttons:

| Componente | Key | Props |
|---|---|---|
| `Button Icon` (público) | `e8186571…` | `👉 Size`: Medium, Small, Large |
| `.Icon Button / Large` | `4d37082c…` | `🔄 Icon` (swap), `🔔 Notification` (boolean), `✏️ Type` (Primary, Secondary, Tertiary), `🔒 Disabled` (True, False), `🎨 Remove Color` (False, True) |
| `.Icon Button / Medium` | `d6846469…` | as mesmas |
| `.Icon Button / Small` | ? | as mesmas |
| `.Icon Button / Exclusive` | ? | ? (4 variantes; não é opção do `Size`) |

No código há **um** widget (o botão de ícone). No Figma há uma key por tamanho, para travar o tamanho em cada base.
O `Button Icon` só escolhe o tamanho; as props que importam ficam na base, dentro dele.

O que trava hoje:

1. **Uma anotação tem uma key.** Para o mesmo widget, são 4 ou 5 anotações.
2. **A CLI descartava `.`/`_` mesmo com anotação** (bug: a FIGMA_CONNECT §3.3 diz o contrário). A base exposta
   resolvia, mas a base solta na tela sumia como "só do Figma".
3. **As props do público estão na base.** O `Button Icon` precisa ler as props da instância exposta, e o caminho
   dela muda por tamanho.
4. **Nomes de prop com emoji** (`✏️ Type`). A anotação lê pelo nome exato do Figma; digitar à mão erra fácil.
5. **O agente pulava os `.`** no inventário, como "só do Figma".

**Confirmado no Figma** ("Explorar comportamento do componente" no `Button Icon`):

- **Exposta: sim.** O painel mostra o `👉 Size` e, logo abaixo, um grupo **`✏️ Icon Button`** com `Type`,
  `Disabled`, `Remove Color`, `Icon` e `Notification`. Esse grupo é a base exposta, e o título dele é o nome da
  camada.
- **O export está certo.** No modelo do Figma, essas props são da base, não do `Button Icon`. O painel só as mostra
  juntas porque a base é exposta. Por isso o `Button Icon` tem só `Size` no export. Numa tela, a instância dele vem
  com `exposed: [{path: '✏️ Icon Button', componentKey: <key da base daquele tamanho>, props: {…}}]`.
- **O nome da camada é `✏️ Icon Button`.** Falta só conferir se é o mesmo nos três tamanhos. Se for, o caminho não
  muda, e o público fica com uma linha (abaixo).

**Ainda a confirmar:**

- **Mesmo nome:** a camada se chama `✏️ Icon Button` também em Medium e Small?
- **Uso solto:** o designer põe a base solta na tela, sem o `Button Icon` em volta?
- **`Exclusive`:** onde a `.Icon Button / Exclusive` aparece?

Um export do plugin de uma tela com dois `Button Icon` de tamanhos diferentes responde as quatro.

**Pista:** o painel mostra **Code Connect: Conectado** no `Button Icon`. O Acme já tem Code Connect para ele. O MCP
local do Figma tem o `get_code_connect_map`, que devolve, por nó, o componente de código ligado (nome e arquivo). Se
for o widget Flutter, o agente acha o widget sem adivinhar pelo nome. A confirmar: para qual código está ligado (web
ou Flutter)?

## Proposta A — uma anotação por key, com helpers (sem mudar a API)

```dart
// Props que todas as bases têm: um helper por prop, escrito uma vez.
AcmeIconButtonType _type(FigmaProps f) => f.variant('✏️ Type', {
  'Primary': AcmeIconButtonType.primary, 'Secondary': …, 'Tertiary': …,
});
VoidCallback? _onPressed(FigmaProps f) =>
    f.variant('🔒 Disabled', {'True': null, 'False': f.guided('onPressed', guide: '…', or: () {})});
const _notes = {'🎨 Remove Color': FigmaNote.ignore('Só visual')};

// Uma por base: o tamanho fica fixo no corpo.
@FigmaConnect(key: '4d37082c…', name: '.Icon Button / Large', figmaNotes: _notes)
Widget iconButtonLarge(FigmaProps f) => AcmeIconButton(
  icon: f.icon('🔄 Icon'), size: AcmeIconButtonSize.large, type: _type(f),
  notification: f.boolean('🔔 Notification'), onPressed: _onPressed(f),
);
// … iconButtonMedium, iconButtonSmall, iconButtonExclusive

// O público só delega para a base exposta. A key da instância diz qual base é, e com isso o tamanho.
@FigmaConnect(
  key: 'e8186571…',
  name: 'Button Icon',
  figmaNotes: {'👉 Size': FigmaNote.derive('Vem da base exposta: cada tamanho é uma base com a sua key.')},
)
Widget buttonIcon(FigmaProps f) => f.instance('✏️ Icon Button');
```

Se o nome da camada mudar por tamanho, volta a ser um `f.variant('👉 Size', {'Large': f.instance('…'), …})`.

- **Na CLI:** só o bug 2 (o prefixo `.`/`_` vale só para componente **sem** anotação).
- **Na skill e no agente:** este padrão, e o inventário deixa de pular as bases `.` que aparecem dentro de um
  componente público.
- **Prós:**
  - nenhuma API nova, e já foi validado num teste (abaixo);
  - funciona com a base exposta ou solta na tela;
  - cada key fica explícita.
- **Contras:**
  - o construtor se repete uma vez por base (são as 5 linhas do widget);
  - o caminho da camada precisa bater: é o título do grupo no painel (`✏️ Icon Button`), e o agente confere no
    export.

## Proposta B — várias keys numa anotação (`locked`)

```dart
@FigmaConnect(
  key: 'e8186571…', name: 'Button Icon',
  // Cada base vale como o público com o tamanho travado; as props dela entram junto com as do público.
  locked: {'4d37082c…': {'👉 Size': 'Large'}, 'd6846469…': {'👉 Size': 'Medium'}, …},
)
Widget buttonIcon(FigmaProps f) => AcmeIconButton(
  size: f.variant('👉 Size', {'Large': …, 'Medium': …, 'Small': …}),
  icon: f.icon('🔄 Icon'), type: _type(f), notification: f.boolean('🔔 Notification'), onPressed: _onPressed(f),
);
```

- **Na CLI:**
  - `find` aceita as keys de `locked` (base solta: as props dela mais o valor travado);
  - no público, as props da base exposta são achatadas no escopo, sem caminho.
- **Prós:** uma anotação por widget, igual ao que existe no código; sem caminho de camada.
- **Contras:**
  - API nova no `figma_connect` e regra de achatamento na CLI (prop com o mesmo nome no público e na base:
    quem vence?);
  - mais "mágica" para quem lê a anotação;
  - o drift por key fica menos direto.

## Proposta C — achatar automaticamente (descartada)

O público sem anotação, com uma base exposta só, seria resolvido pela anotação da base. Fica implícito demais: não
dá para saber pela anotação o que acontece, e um público com duas bases expostas cai em ambiguidade.

## Complementar (vale para A ou B) — nomes de prop com emoji

| Opção | Como | Custo |
|---|---|---|
| **E1. Copiar exato** (recomendado) | a skill manda copiar o nome do `export.json` e o `flutter test` do pacote pega o erro (`prop ausente`) | nenhum |
| E2. Comparar sem emoji | a CLI compara nomes sem símbolos no começo e sem diferença de maiúsculas (`f.boolean('Notification')` acha `🔔 Notification`) | regra a mais; dois nomes que só diferem no emoji colidem |

## Recomendação

**A + E1 agora.**

- Resolve o caso com uma correção de bug, sem API nova.
- Os 4 ou 5 arquivos por família de botão são pequenos, e o agente escreve todos.
- Reavaliar **B** se, depois de anotar algumas páginas do Acme, as famílias com bases travadas passarem de umas 10,
  ou se a repetição começar a gerar divergência entre as bases.

## Tarefas (proposta A)

- [ ] CLI: prefixo `.`/`_` só ignora sem anotação, com teste. *Já feito antes da pausa para o planejamento; ver
  Estado.*
- [ ] Skill `figma2dart-connect`: seção "Bases travadas" com o padrão, o helper por prop e o `f.variant` + `f.instance`
  no público.
- [ ] Agente `figma-ds-mapper`: no inventário, `.` deixa de ser "só do Figma" quando a base aparece dentro de um
  componente público; anotar a família inteira no mesmo lote.
- [ ] FIGMA_CONNECT §3.3: linha "base travada" na tabela, com o exemplo.
- [ ] COMO_FUNCIONA: no fluxograma "Do DS ou fora do DS", o prefixo só vale sem anotação.

## Verificação

- Teste da CLI com o `Button Icon` e as bases (base exposta e base solta). *Já escrito:
  `figma2dart/test/locked_variants_test.dart`.*
- No Acme: anotar a família `Button Icon` com o agente e rodar o `resolve` de uma tela real que a use.

## Estado

Antes do pedido de planejar, já tinham sido feitos (não commitados):

- a correção do bug 2 (`ignoreReason(…, annotated:)` em `mappings.dart` e `resolve.dart`);
- o teste `locked_variants_test.dart`, com os dois casos passando.

Se a escolha for outra, isso volta.
