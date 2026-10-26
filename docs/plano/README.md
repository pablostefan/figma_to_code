# Plano: monorepo, Acme e componentes que a LLM monta

Objetivo: rodar o figma2dart no monorepo real, onde o DS (Acme) fica num caminho próprio, e fazer a LLM acertar
os dois casos em que ela escreve o componente sem código pronto:

- **Montar**: o componente já existe (sketch do Acme, ou widget do app) e a LLM monta com a API dele.
- **Construir**: o componente não existe em lugar nenhum e a LLM cria o widget pelo brief.

Passo a passo para levar a solução ao monorepo: [MIGRACAO_MONOREPO.md](../MIGRACAO_MONOREPO.md). O que o design ops
configura e mantém: [DESIGN_OPS.md](../DESIGN_OPS.md). Auditoria do que
foi feito em 01–03: [AUDITORIA.md](../AUDITORIA.md#auditoria-das-questões-0103).

Uma questão por arquivo. Cada um traz o problema, a proposta, as tarefas, a verificação e as decisões em aberto.

| # | Questão | Status |
|---|---|---|
| [01](01-monorepo-descoberta.md) | Monorepo: descobrir pacote, Acme e config; expor a CLI | feita (falta `.ps1` se houver Windows) |
| [02](02-acme-e-componentes-do-app.md) | Acme × app: retrato da biblioteca e anotação própria para componentes do app | feita |
| [03](03-brief-completo.md) | Brief completo com o que o IR já tem | feita |
| [04](04-tokens-em-dart.md) | Tokens já em Dart no brief | feita |
| [05](05-check.md) | `check` que confere as regras (dicas, sem bloqueio) | feita |
| [06](06-skills.md) | Skills de construir e de montar | aberta |
| [07](07-plugin.md) | Plugin: conteúdo das instâncias e texto (+ recorte do PNG) | feita (falta export real) |
| [08](08-comparacao-visual.md) | Comparação visual por golden | depois |

**Ordem:** 01 → 02 → 03 → 04 → 05 → 06 → 07. 01 e 02 primeiro porque sem elas a ferramenta não roda no monorepo;
03 e 04 são o maior ganho de acerto; 07 depende de um export real do Acme para validar.

**Decisões em aberto (todas):**

1. ~~Pub workspaces ou melos?~~ Melos, sem pub workspaces. Falta só: alguém usa Windows? ([01](01-monorepo-descoberta.md))
2. ~~O Acme é um arquivo só no Figma?~~ O retrato aceita vários exports (um por página, de um ou mais arquivos). ([02](02-acme-e-componentes-do-app.md))
3. ~~Nome da anotação do app~~ `@FigmaLocal`. ([02](02-acme-e-componentes-do-app.md))
4. ~~Anotação em arquivo separado ou na classe~~ `typedef` em `figma/connect/`, fora de `lib/`. ([02](02-acme-e-componentes-do-app.md))
5. ~~Recorte do PNG por instância?~~ Sim, com a dependência `image`. ([07](07-plugin.md))
6. Golden agora ou depois? ([08](08-comparacao-visual.md))
