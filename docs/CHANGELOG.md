# Changelog

## 2026-10-25 — IR 1.2 e robustez do exportador

Auditoria de qualidade do plugin e do extrator. A atualização corrige perdas silenciosas de dados, valida melhor as
entradas e reduz o pico de memória na criação do ZIP.

### Contrato IR

- O extrator passa para `0.3.0` e escreve IR `1.2.0`.
- `Override.id` identifica a camada original do Figma. O campo é opcional para que exports IR 1.0 e 1.1 continuem
  válidos; todo export novo o preenche.
- `LintIssue.locatable: false` identifica avisos de variável ou estilo que não apontam para uma camada do canvas.
- O schema aceita somente `1.0.0`, `1.1.0` e `1.2.0`. Versões desconhecidas são rejeitadas na entrada.

### Correções

- Overrides de camadas homônimas não são mais deduplicados pelo nome. A identidade usa o ID estável do nó.
- Componentes locais não publicados usados dentro de outro componente entram no IR como dependências profundas.
- Textos, vetores e outras camadas soltas não podem mais ser exportados acidentalmente como telas.
- Sections sem telas retornam um erro claro.
- A paginação MCP aceita somente índices inteiros existentes.
- A exportação falha de forma explícita se um PNG solicitado não puder ser gerado; o JSON não aponta mais para um
  arquivo ausente.
- Avisos sem uma camada correspondente deixam de parecer clicáveis na interface.

### ZIP e memória

O plugin deixou de acumular todos os PNGs no sandbox e depois executar `zipSync`. Cada arquivo agora é enviado à UI
assim que fica pronto e adicionado a um ZIP incremental com `ZipPassThrough`. PNG já é comprimido, portanto não é
recomprimido. A UI ainda precisa manter os bytes finais do ZIP até iniciar o download, que é uma restrição do browser.

### Verificação

`npm test` cobre:

- tipos de seleção aceitos e rejeitados;
- paginação com Unicode e índices inválidos;
- preservação de dois overrides com o mesmo caminho por nome;
- descoberta de dependência local durante um export de componente;
- leitura de fixtures IR 1.0 e rejeição de versão desconhecida.

`npm run check` executa typecheck, geração do schema, testes, build e validação das fixtures.

### Compatibilidade e rollback

O caminho de leitura é retrocompatível: o schema novo continua aceitando IR 1.0 e 1.1. Leitores antigos que rejeitam
campos desconhecidos precisam receber o schema 1.2 antes do novo extrator. Como os campos adicionados são opcionais,
o rollback do writer consiste em voltar `IR_VERSION` e `EXTRACTOR_VERSION`; nenhum dado persistido é migrado ou
reescrito pelo plugin.
