# 08 · Revisão visual pela LLM

**Status: feita**, calibrada no sample app com uma tela boa e uma com erros de propósito. Falta rodar o subagente de
verdade no Copilot e no opencode (2–3 vezes por caso). Decisões:

- **Não é pixel perfect nem golden.** Já foi testado e não funciona: fonte, serrilhado e ambiente geram diferença
  que não importa. A análise é da LLM olhando as imagens, com um **critério fixo** do que importa e do que ignorar.
- **Revisor separado:** um subagente que não escreveu a tela revisa; quem escreveu corrige.
- **A CLI dá o material, não o veredito:** as imagens (tela inteira e por seção, Figma | Flutter) e alguns **fatos
  que não dependem de pixel** (ordem dos textos, texto que não apareceu, overflow) como pista.
- Roda **sempre depois do `check`**. Como o resto: **dica, não bloqueia**.

## Problema

Nada confere o resultado com o Figma. O `check` olha marcadores, analyzer e dicas de código; uma tela que compila
com ordem trocada, cor errada, ícone apontando para o lado errado ou texto cortado passa. As imagens do export hoje
só são referência: a LLM pode abrir, mas ninguém compara.

O medo é o contrário também: a revisão gastar rodadas em diferença de ambiente ou sem impacto. Por isso o critério,
a base obrigatória no brief, o teto de achados e a calibração antes de confiar.

## Fluxo

```
resolve → LLM escreve a tela → check ok
  → LLM escreve o teste de captura (monta a tela com os dados do Figma) → flutter test
       grava .figma2dart/tasks/<tela>/capture/{screen.png, layout.json}
  → figma2dart review --screen <tela>
       grava review/: lado a lado da tela, pares por seção, facts.json, REVIEW.md
  → subagente revisor: até 5 achados, cada um com a base no brief
  → quem escreveu corrige → captura e revisa de novo (até 2 rodadas)
  → relatório final: o que foi corrigido e o que ficou (com o motivo)
```

## Critério (a skill do revisor)

| Nível | O quê | Faz |
|---|---|---|
| **Importa** | elemento faltando ou sobrando; ordem trocada; componente errado; cor de fundo, destaque ou texto trocada; ícone errado ou na direção errada; alinhamento trocado (centro × esquerda); hierarquia de texto invertida; texto cortado que o Figma não corta | corrige |
| **Talvez** | espaçamento claramente diferente a olho (meio gap ou mais); tamanho de componente visivelmente diferente | corrige se o brief diz o valor; senão relata |
| **Ignorar** | renderização de fonte e serrilhado; sombra sutil; 1–3 px; status bar e área segura; dado diferente do exemplo do Figma (nome maior, mais itens); placeholders `f2d` e imagens `TODO(f2d)` | não menciona |

Regras do revisor:

- **Base obrigatória:** cada achado aponta a linha do brief ou da estrutura que diz como deve ser (o token, a ordem,
  o componente). "Parece diferente" sem base não é achado.
- **No máximo 5 achados por rodada**, os mais graves primeiro. Termina quando não há achado do nível "Importa".
- Os fatos do `facts.json` são pista, não achado: o revisor confirma na imagem antes de relatar.

## O que a CLI entrega (`review/`)

- `screen.png`: Figma | Flutter lado a lado, na mesma escala.
- `sections/<n>.png`: um par por seção da tela (os filhos diretos do frame, pelas caixas do Figma). Pedaço pequeno
  a LLM compara melhor que a tela inteira. A seção do lado Flutter é recortada na mesma caixa; se o layout deslocou,
  o recorte mostra, e a tela inteira é a referência.
- `facts.json`, sem pixel:
  - **ordem dos textos:** a sequência de leitura no Figma × na tela renderizada (fora de ordem, faltando);
  - **texto que não apareceu** (com a ressalva: pode vir de dado);
  - **overflow** que o Flutter reportou na captura.
- `REVIEW.md`: o critério, as seções com o trecho da estrutura do brief de cada uma (a base dos achados) e os fatos.

## Captura (no app, `package:figma_connect/capture.dart`)

`figmaCapture(tester, tela, task: '<tela>')`: superfície do tamanho do frame na escala do PNG do Figma (do
`resolved.json`); carrega **todas as fontes do app** pelo `FontManifest.json` (sem config; sem isso o texto sai como
caixas); `pumpAndSettle`; grava o PNG e o `layout.json` (textos renderizados com o retângulo, erros de overflow).
O teste a LLM escreve (só ela sabe o construtor e os dados); a skill dá o modelo de 5 linhas.

## O que já existe e serve de base

Nada pronto compara Figma × Flutter com critério; as peças existem separadas.

| Peça | O que é | Uso aqui |
|---|---|---|
| [design-review da OneRedOak](https://github.com/OneRedOak/claude-code-workflows) | subagente revisor de UI (web, Playwright): severidade `[Blocker]`/`[High-Priority]`/`[Medium-Priority]`/`[Nitpick]`, print como evidência, relatório fixo | **modelo do revisor**: estrutura, triagem e evidência. Troca "problema, não solução" por "achado + base no brief" (quem corrige é uma LLM com o brief) |
| [Dart & Flutter MCP](https://dart.googlesource.com/ai.git/+show/6a71aeb/pkgs/dart_mcp_server/README.md) (oficial, experimental) | `take_screenshot` e `get_widget_tree` do app rodando | **captura opcional**: se o agente já está com o app aberto, print real sem teste; precisa navegar até a tela |
| [Marionette MCP](https://pub.dev/packages/marionette_flutter) (LeanCode) | print, árvore e toques no app rodando (binding no `main.dart`) | alternativa à de cima quando a tela precisa de interação para chegar no estado; DS próprio pede configuração |
| [Alchemist](https://pub.dev/packages/alchemist) | golden com fontes reais ("platform goldens") | referência de como carregar as fontes no `flutter test`; não precisa da dependência, o `figmaCapture` faz o mesmo pelo `FontManifest` |
| Skill oficial `figma-design-to-code` | manda usar o print do Figma como alvo e verificar no fim | só a ideia; é para web e sem critério |
| [Applitools](https://applitools.com/tutorials/concepts/best-practices/match-levels) e [Percy Visual Review Agent](https://www.browserstack.com/docs/percy/ai-agents/visual-review-agent/overview) | IA que ignora ruído de renderização e resume o que mudou | **não serve**: comparam versões do app (regressão), não Figma × código; pagos. A ideia de ignorar por região vale para o critério |

Captura padrão: `flutter test` com o `figmaCapture` (sem aparelho, igual em toda máquina, roda no Copilot e no
opencode). Com o app aberto, o MCP oficial é o atalho.

## Calibração (antes de ligar no fluxo)

1. **Telas boas:** as telas feitas à mão do sample app (`lib/flow`) contra o export real do fluxo. A revisão deve
   achar quase nada; cada alarme falso vira item do "Ignorar".
2. **Erros de propósito**, um por vez: ordem trocada, cor errada, chevron sem rotação, texto que estoura, componente
   faltando, gap muito maior. Cada um precisa aparecer como "Importa".
3. Repetir 2–3 vezes cada caso (a análise não é determinística): o que aparece só às vezes conta como não pego.

## Tarefas

- [x] **Plugin:** caixa (`bounds`) em todo nó da tela (`boundsIn` já existia). IR 1.4, extrator 0.5.
- [x] **figma_connect:** `capture.dart` com `figmaCapture` (e `prepare`, que a calibração pediu).
- [x] **CLI:** `review` (lado a lado, pares por seção, `facts.json`, `REVIEW.md`); o `resolve` grava o `review.json`.
- [x] **Agente:** subagente `figma-visual-reviewer` e skill `figma2dart-review`; no orquestrador, o passo 5 depois
  do `check`, até 2 rodadas.
- [x] **Calibração** no sample app (abaixo).
- [x] **Docs:** README da CLI, FIGMA_CONNECT §10.1, DESIGN_OPS §8, README do plugin.

## Riscos

- **Tela que depende de back-end** (cubit, rede): a LLM monta com dados falsos do Figma; imagem de rede vira o
  placeholder que já é `TODO(f2d)`.
- **Ferramenta sem visão** (modelo que não abre PNG): sem revisão; o agente avisa e segue só com os fatos.
- **Tempo e custo:** um `flutter test` e uma chamada de revisor por rodada.
- **Tela mais alta que o celular** (frame de 390×1600): a superfície usa o tamanho do frame, sem rolagem.

## Resultado

- **Captura:** `figmaCapture(tester, app, task:, prepare:)` no tamanho do frame e na escala do PNG, com as fontes do
  `FontManifest` (as do DS sem config). Grava `screen.png` e `layout.json`: textos visíveis com o retângulo
  (inclusive o valor digitado; sem placeholder escondido nem rota de baixo) e os erros de layout, que não reprovam.
- **`review`:** sem captura, prepara (`figma_connect` nas dev_dependencies) e devolve o arquivo e o modelo do teste.
  Com captura: `screen.png` (Figma | Flutter, 1x), um par por seção (caixa do Figma + 8 de margem, 2x),
  `facts.json` e `REVIEW.md` (critério, regras, fatos e, por seção, a estrutura com o código do DS na linha: a base
  dos achados).
- **Fatos sem pixel:** texto do Figma ausente, só no Flutter, cortado, overflow, e fora de ordem. Fora de ordem só
  quando um texto ficou **inteiramente acima** de quem vinha antes (ou inteiramente à esquerda na mesma faixa):
  avatar ao lado do nome não conta.
- **Agente:** o orquestrador revisa cada tela depois do `check` com a skill `figma2dart-review`; quem revisa é o
  subagente `figma-visual-reviewer` (só leitura), no máximo 5 achados com base, até 2 rodadas.
- O teste de captura fica no repositório (`test/<pasta das telas>/<tela>_figma_test.dart`): é o teste de widget da
  tela.

## Calibração (o que aconteceu)

Cópia do sample app (as telas feitas à mão), tela Transferir, contra o export real do fluxo:

| Caso | Fatos | Revisão (eu, pelo critério) | Ajuste |
|---|---|---|---|
| Tela boa, 1ª | `AS`/`BL`/`CD` fora de ordem; `R$ 150,00` ausente, `R$ 0,00` só no Flutter | botão desabilitado e campo vazio: estado do teste, não da tela | ordem por "inteiramente acima"; `prepare` no `figmaCapture`; regra de estado no critério |
| Tela boa, 2ª (com `prepare`) | `R$ 150,00` ainda ausente | — | captura lê o campo digitado e pula texto invisível |
| Tela boa, 3ª | **nenhum** | nada além do estado do botão (o Figma o mostra habilitado sem contato escolhido) | — |
| 4 erros plantados | "Contatos recentes" fora de ordem | os 4: chevron sem girar, título depois da lista, gap maior, botão secundário | base do botão não estava à mão → código do DS na linha da seção |

As fontes do DS saíram certas no teste (sem caixas), e a tela feita à mão ficou visualmente igual ao Figma: a
revisão não inventou diferença de ambiente.

## Falta

- Rodar o subagente de verdade (Copilot e opencode), 2–3 vezes por caso: a calibração acima foi feita por mim com o
  critério, e a análise não é determinística.
- Confirmar que o Copilot abre PNG com a ferramenta `read` (se não, o revisor responde `Imagens abertas: não`).
- Export novo (IR 1.4) para as seções que são frame terem caixa; com o export atual (1.3), só as instâncias têm, e
  as outras seções saem sem recorte (a tela inteira cobre).
