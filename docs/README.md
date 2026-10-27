# Docs

| Doc | Para quem | O que explica |
|---|---|---|
| [COMO_FUNCIONA.md](COMO_FUNCIONA.md) | todos; comece aqui | as peças, o fluxograma e as etapas: preparar o DS, preparar o app, implementar telas |
| [ARQUITETURA.md](ARQUITETURA.md) | quem mantém a solução | por dentro: o IR, como a CLI acha as coisas e resolve uma tela, e por que é assim |
| [FIGMA_CONNECT.md](FIGMA_CONNECT.md) | time do DS | a API das anotações: `@FigmaConnect`, `FigmaProps`, cobertura, docs, `FigmaPolicy` |
| [DESIGN_OPS.md](DESIGN_OPS.md) | time do DS | o que configurar e manter: tokens, ícones, anotações, retrato; o que fazer quando o DS muda |
| [MONOREPO.md](MONOREPO.md) | quem instala | onde a solução fica no monorepo, o que cada pessoa instala, config e como conferir |

Nos exemplos, `Acme` é um DS fictício: o padrão de um DS com tokens no tema, tipografia num enum e ícones como
constantes de uma classe.

Cada pasta também tem o seu README: [figma_plugin](../figma_plugin/README.md) (exportar do Figma),
[figma2dart](../figma2dart/README.md) (a CLI e os comandos), [figma_connect](../figma_connect/README.md) (o pacote das
anotações) e [copilot_plugin](../copilot_plugin/README.md) (agentes e skills).
