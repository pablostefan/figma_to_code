# 02 · Acme × app: retrato da biblioteca e anotação do app

**Status: feita.** Decisões tomadas pelas recomendações: retrato por página (vários exports), `@FigmaLocal` sobre
`typedef` em `figma/connect/` (configurável com `connect:`), templates do `acme_templates` como `sketch`. O plugin
não mudou: o modo biblioteca já exporta key e nome de cada componente. Resultado e análise no fim do arquivo.

## Problema

1. **"Do DS" hoje = "remoto no Figma"** (`shortcut:` em [resolve.dart](../../figma2dart/lib/src/resolve.dart)). No
   monorepo há bibliotecas de produto além do Acme: um componente delas vira `gap` (Acme sem mapeamento) quando
   deveria ser do app ou a construir.
2. **Componente do app que já existe** não tem como ser reconhecido: sai como `placeholder`, gera brief de
   construção e o agente pergunta de novo a cada tela e a cada execução.
3. Hoje só existe `@FigmaConnect`, pensado para o DS. Componente do app tem outras regras (não tem `FigmaPolicy`
   do Acme, não fica no pacote do Acme).

## Proposta

### Retrato do Acme

O plugin em modo biblioteca exporta as keys de todos os componentes do Acme. `figma2dart library <zip>` grava o
retrato no pacote de mapeamentos (ex.: `acme_figma/figma/library.json`). Regra nova:

| Instância | Status |
|---|---|
| key do Acme com mapeamento | `mapped` / `sketch` |
| key do Acme sem mapeamento | `gap` |
| key com `@FigmaLocal` | `local` (montar) |
| key fora do Acme, sem anotação | `placeholder` (construir) |

Sem retrato, vale a regra atual e o `doctor` avisa.

### Anotação do app

```dart
// <app ou pacote de feature>/figma/connect/contact_item.figma.dart  — fora de lib/
import 'package:app/flow/widgets/contact_item.dart';
import 'package:figma_connect/figma_connect.dart';

@FigmaLocal(key: '267291286c16eafc32e9a66b9571700954952086', name: 'ContactItem')
typedef ContactItemFigma = ContactItem;
```

- Mínimo: `key` e `name`; `guide` opcional. O "onde está" a CLI tira do typedef (analyzer) e põe no brief como
  `import`.
- Fora de `lib/`: `figma_connect` só como dev_dependency; produção não carrega nada do Figma.

| | `@FigmaConnect` (Acme) | `@FigmaLocal` (app) |
|---|---|---|
| Onde | só no pacote de mapeamentos do Acme | `figma/connect/` do app e dos pacotes de feature |
| Resultado | código pronto, ou montagem (sketch) | montagem: API, import, usos, expostas |
| Regras | `FigmaPolicy` do Acme | "não altere o widget sem perguntar" |
| Erro se | key fora do Acme | key do Acme ("mapeie no acme_figma"), ou key repetida |

### Como a anotação nasce (você nunca digita a key)

- **Pista `existing`:** tarefa de construção com classe de mesmo nome no app ou nas dependências dele → o
  `resolve` devolve `"existing": "<arquivo>"`; o agente pergunta "já existe, usar?" e escreve a anotação.
- **Usuário indica** um componente existente → o agente escreve a anotação.
- **Subagente construiu** o componente → escreve a anotação no fim.

Depois, opcional por componente: trocar por um `@FigmaConnect` completo do app (código exato, sem LLM). Não é o
padrão: a mínima nunca fica errada quando a API muda.

## Tarefas

- [ ] Plugin: modo biblioteca grava o retrato (keys + nomes) num formato que a CLI lê.
- [ ] CLI: `library <zip>`; ler o retrato; nova regra de status; tirar o `shortcut:`.
- [ ] `figma_connect`: `@FigmaLocal` (+ testes).
- [ ] CLI: carregar `@FigmaLocal` só de `figma/connect/` do app e das dependências dele dentro do repo (sem varrer
      o monorepo); validações da tabela; status `local` com brief de montagem e `import`.
- [ ] CLI: pista `existing`.
- [ ] Agente e skills: perguntar sobre `existing`, escrever a anotação nos três casos.
- [ ] Docs: FIGMA_CONNECT (nova anotação), ARCHITECTURE (status).

## Verificação

No fixture do monorepo: `@FigmaLocal` vindo de um pacote de feature vira `local`; key do Acme no app dá erro; key
repetida dá erro; componente de outra biblioteca (remoto, fora do retrato) vira `placeholder`, não `gap`;
`existing` aparece quando a classe existe.

### `acme_templates`

No monorepo, `libraries/design_ops/packages/acme_templates` tem componentes Flutter que são telas prontas. Eles são
do Acme (mapeados no `acme_figma`, `@FigmaConnect`), e o caso natural é o `sketch`, como o `Template / Extrato` do
Carteira: a LLM monta o template com a API dele e o conteúdo da tela. Depende do conteúdo das instâncias
([07](07-plugin.md)).

## Decisões em aberto

- Os templates do `acme_templates` estão no Figma como componentes da biblioteca do Acme (com key), ou como frames?
- **O Acme é um arquivo só no Figma?** Se forem vários, `library` aceita vários exports.
- **Nome:** `@FigmaLocal`, `@FigmaApp` ou outro?
- **Onde fica:** arquivo separado fora de `lib/` com typedef (recomendado) ou direto na classe em `lib/` (fica junto
  do widget, mas `figma_connect` vira dependência de produção).
- `figma/connect/` como pasta padrão, configurável no `figma2dart.yaml`?

## Resultado

| Peça | Onde |
|---|---|
| `@FigmaLocal(key, name, guide?)` | `figma_connect/lib/src/annotation.dart` |
| Retrato do DS (`figma_library.json`), regra do `gap` por ele | `figma2dart library`; `MappingSet.fromDs` |
| `@FigmaLocal` carregado do pacote alvo e das dependências por path dele (menos o DS); key do DS, já mapeada ou repetida é erro | `loadLocalMappings`, `MappingSet.withLocal` |
| Status `local`, marcador `f2d:local` (bloqueia o `check`), tarefa `"kind": "local"` com `import` e brief de montagem | resolvedor e briefs |
| `figma2dart link <key> <arquivo>#<Classe>`: escreve a anotação e o `pub add` do `figma_connect` | `commands.dart` |
| Pista `existing` em tarefa de construção (classe de mesmo nome no app, fora do DS) | `Workspace.findClasses` |
| `doctor`: páginas e data do retrato; `warnings` sem ele. `screens` conta "fora do DS" pelo retrato | `commands.dart` |
| Agente e skills de referência: `existing` → `link`; `local` nunca é perguntado; construtor termina com `link` | `figma2dart/agent/` |

## Verificação

- 61 testes na CLI (`local_test.dart`: 8 novos), 5 no `figma_connect`, 29 no `carteira_ds_figma`; analyze limpo.
- Monorepo de teste (Carteira dentro de `libraries/design_ops/packages`, sample app como pacote de setor):
  1. `library` com um export de biblioteca (montado com os 10 componentes remotos do export real do fluxo);
  2. `resolve` de Transferir: `TopBar` e `ContactItem` a construir, **com `existing`** apontando para os widgets
     feitos à mão em `lib/widgets/local_components.dart`;
  3. `link` dos dois: escreveu `figma/connect/*.figma.dart` e rodou `flutter pub add` do `figma_connect` com o
     caminho relativo certo (`../../design_ops/packages/figma2dart/figma_connect`); `dart analyze figma/` limpo;
  4. `resolve` de Transferir e Confirmar juntos: os 4 + 2 placeholders viraram `local` nas duas telas; `SummaryRow`
     (sem widget) continua a construir;
  5. `link` num arquivo do DS é recusado.

## Análise: vai funcionar?

**Funciona como planejado** no que foi exercitado acima: a decisão de reaproveitar fica gravada no código e vale em
todas as telas e execuções; ninguém digita key; o DS não recebe `@FigmaLocal`.

**Riscos, do maior para o menor:**

1. ~~Key do retrato × key da instância.~~ **Confirmado no Carteira:** as keys dos mapeamentos foram lidas no arquivo
   do DS (`sgwwQGDTn2rhRA1PMaqL5f`) e os 10 componentes remotos do export do fluxo (outro arquivo) têm exatamente
   essas keys. Componente publicado tem a mesma key nos dois lados. Exceção a lembrar: uma **cópia** do arquivo do
   Acme (fork, duplicata) gera keys novas; o retrato tem que vir do arquivo publicado.
2. **Retrato incompleto ou velho.** Página do DS não exportada (ou componente novo) faz um componente do DS sair
   como **a construir** em vez de `gap`, e o agente oferece construir algo que existe no DS. O `doctor` mostra páginas
   e datas para o agente avisar; não há como detectar sozinho.
3. **Export de biblioteca pesado.** O modo biblioteca exporta árvore e PNG de todos os componentes da página; com o
   Acme inteiro o zip pode ficar grande e lento. A CLI só usa key e nome: se pesar, vale um modo "só keys" no plugin.
4. **`link` mexe no pubspec do time** (`flutter pub add`): muda `pubspec.yaml` e o lock do pacote, entra no PR.
5. **`existing` é por nome e só nas dependências diretas.** Nome diferente do Figma não é achado; homônimo é falso
   positivo (por isso o agente pergunta antes). Dependência transitiva não entra.
6. **Custo:** cada pacote com `figma/connect/` acrescenta uma análise ao `resolve`/`doctor`: ~1,5 s com o cache do
   SDK compartilhado (eram ~4,3 s antes da auditoria).
7. **Templates do `acme_templates`:** só funcionam como `sketch` se forem componentes da biblioteca (com key); se
   forem frames, a tela inteira precisa de outro tratamento. Pergunta em aberto.
8. **Agente:** as instruções de referência mudaram, mas nenhum LLM rodou o fluxo `existing → link → resolve`.
