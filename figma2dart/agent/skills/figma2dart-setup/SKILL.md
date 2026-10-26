---
name: figma2dart-setup
description: Prepara o app para o figma2dart e descobre os caminhos (app, mapeamentos do DS, exports do Figma, pasta das telas). Use antes de implementar uma tela do Figma, ou quando um comando figma2dart devolver "error" ou "problems".
---

# Preparar o figma2dart

Tudo parte de `figma2dart doctor --json`, rodado **de dentro do pacote** onde a tela vai (ou com `--package <pasta>`;
num monorepo, de qualquer pasta do repositório). Ele devolve
os caminhos que a CLI descobriu e uma lista `problems`, cada um com `fix`. Resolva na ordem abaixo e rode o
`doctor` de novo até `"ok": true` (ou até sobrar só o que o usuário decidiu deixar).

| Situação | O que fazer |
|---|---|
| `figma2dart: command not found` | Peça ao usuário para rodar uma vez `<pasta da CLI>/tool/figma2dart setup` (ou a tarefa do time que faz isso) e garantir `~/.pub-cache/bin` no `PATH`. Não instale nada sem ele confirmar. |
| `Nenhum pubspec.yaml` ou `Chamada da raiz do repositório` | Ache o pacote: o do arquivo aberto, ou `figma2dart packages <parte do nome> --json` com o setor que o usuário citar (os com `"ds": true` primeiro). Um resultado: use; vários: pergunte. Passe `--package <path>` nos comandos seguintes. |
| nenhum `figma2dart.yaml` | Monorepo: o config com `mappings:` existe mas não está no git? Peça ao usuário o `git add`. App só: `figma2dart init --json` (cria o config, ignora `.figma2dart/` e instala agente e skills). |
| pacote de mapeamentos não encontrado | Procure no workspace um pacote com `lib/connect/*.figma.dart` (ex.: `*_ds_figma`). Achou: grave `mappings: <caminho relativo ao app>` no `figma2dart.yaml`. Não achou: pergunte ao usuário. |
| mapeamentos com erro | Mostre a mensagem ao usuário: o problema é no pacote do DS, não no app. |
| nenhum `figma2dart-*.zip` | Pergunte ao usuário onde está o export (ou peça para exportar pelo plugin figma2dart no Figma). Se for uma pasta fixa, grave `exports:` no config; se for um arquivo, passe o caminho direto para `screens`/`resolve`. |
| pasta das telas não definida | Veja onde o app guarda telas (`search` por `*_page.dart`, `*_screen.dart`, pastas `features/`, `pages/`). Proponha a pasta e confirme com o usuário; grave `screens: <pasta relativa ao app>`. |

`warnings` não impedem de seguir: conte ao usuário uma vez. **`@FigmaLocal` ignorado** aponta o arquivo
(`figma/connect/…`) que não compila ou conflita: o dono do widget corrige ou apaga; até lá o componente volta a ser
"a construir". O outro aviso comum é **sem retrato do DS**: sem ele, um
componente de outra biblioteca do Figma sai como `gap` (DS sem mapeamento) em vez de componente a construir. O
`library` do `doctor` mostra as páginas do retrato e a data: se o usuário disser que o DS mudou, peça para exportar de
novo as páginas que mudaram (plugin sem seleção) e rode `figma2dart library <zips> --json`.

O `figma2dart.yaml` tem quatro chaves, todas opcionais:

```yaml
mappings: ../design_system/carteira_ds_figma   # pacote com lib/connect/*.figma.dart
exports: ~/Downloads                            # onde o plugin salva os figma2dart-*.zip
screens: lib/features/transferencia             # telas geradas; widgets novos em <screens>/widgets/
connect: figma/connect                          # onde o `link` grava os @FigmaLocal (padrão: figma/connect)
```

Depois disso, todos os caminhos de que você precisa vêm nas respostas `--json` (`brief`, `screenFile`,
`widgetFile`, `image`, `testFile`), sempre absolutos. Não monte caminhos à mão.
