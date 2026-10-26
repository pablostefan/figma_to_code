# 05 · `check` que confere as regras

**Status: feita.** Decisão: **nada novo bloqueia** — a cultura é informar a LLM com a sugestão e deixar a decisão com
ela. As regras saem em `hints`; `ok` continua só com marcadores e `dart analyze`.

## Problema

O `check` hoje só olha marcadores (`f2d:guided|gap|sketch`) e o analyzer. Passa com cor solta, com parâmetro
faltando e com qualquer widget no lugar de um sketch. As regras das skills ficam só na boa vontade da LLM.

## Proposta

Regras determinísticas, rodando sobre os arquivos escritos e o `resolved.json` da tarefa:

| Regra | Onde | Nível |
|---|---|---|
| Valor solto: `Color(0x…)`, `EdgeInsets.all(12)`, `fontSize:` com número | widgets construídos e tela | dica (`hints`) |
| No lugar de cada sketch ou `local`, o widget do mapeamento (`AcmeStatementTemplate(`) | tela | dica (`hints`) |
| O construtor cobre as props e as expostas da API proposta (por texto: `this.<param>`) | widgets construídos | dica (`hints`) |
| Textos do Figma que não aparecem no código | tela e widgets | dica (`hints`) |

## Tarefas

- [x] `check` lê o `resolved.json`/`component.json` da tarefa para saber o esperado.
- [x] As quatro regras, com mensagem que diz o que fazer.
- [x] Skills: tratar os novos itens do `check`.

## Verificação

Testes com um arquivo de tela/widget errado de propósito para cada regra.

## Resultado

- `hints.dart`: valor solto (`Color(0x…)`, `Colors.*`, números em `EdgeInsets`, `Radius.circular`, `width/height/
  spacing/gap/size`, `fontSize`) com o token do mesmo valor, escolhido pelo contexto e semântico antes de primitivo;
  widget a montar que sumiu; parâmetro proposto ausente; texto fixo do Figma ausente. `f2d:inferred` na linha cala a
  dica de valor.
- `resolve` grava `check.json` por tarefa: tokens por valor (da tabela de tokens da 04), widgets a montar da tela,
  parâmetros e textos de cada componente a construir. O `check` lê as tarefas do pacote.
- Agente e skills: depois do `ok`, ler os `hints` e corrigir ou explicar; o relatório final lista os que ficaram.

## Prova

- `hints_test.dart` (3): sugestões por contexto (`EdgeInsets.all(12)` → `DsSpacing.md`, `circular(12)` →
  `DsRadius.md`, cor → `DsColors.textSecondary` antes de `DsPrimitives.gray500`), `f2d:inferred` cala, widget/param/
  texto; `resolve` → `check` de ponta a ponta sem reprovar por dica.
- Sample app: `check` dos widgets feitos à mão apontou os dois `size: 20` soltos (sem token equivalente), `ok: true`.

## Limites

- Valor solto é por texto (regex, no arquivo inteiro: pega chamada quebrada em linhas), não pelo analyzer: número em
  outra API (ex.: `Offset(0, 2)`) ou `Color.fromRGBO` não é visto.
- "Texto ausente" compara o texto sem os escapes do Dart (`'R\$ 150,00'` bate com `R$ 150,00`); texto formatado ou
  traduzido vira dica que a LLM ignora.
- `size:` só vira dica quando há token de tamanho com o valor (ícone de 20 sem token é o que o brief manda passar).
- Sem token com o valor, a dica diz "nenhum token **usado nesta tela**": o export só traz os tokens da tela, e o DS
  pode ter um; a LLM procura antes de explicar.

## Auditoria

Achados e correções em [AUDITORIA.md](../AUDITORIA.md#auditoria-dos-hints-05).
