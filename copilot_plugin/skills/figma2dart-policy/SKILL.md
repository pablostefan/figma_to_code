---
name: figma2dart-policy
description: Monta e confere o lib/figma_policy.dart do pacote de mapeamentos do DS (tabela de tokens, tabela de ícones, ignorados) a partir do retrato do Figma e do código do DS, com o figma2dart doctor como conferência. Use ao criar o pacote de mapeamentos, quando o doctor apontar tokens ou ícones sem Dart, ou quando o DS mudar.
---

# Montar o `FigmaPolicy`

Entrada: o pacote de mapeamentos (a pasta com `lib/figma_policy.dart` e o `figma_connect` no `pubspec.yaml`) e o pacote do
DS, que é dependência dele.

A política diz à CLI onde estão, no código, os tokens e os ícones do Figma. Com ela, o brief escreve
`context.acmeSpacing.md` e `AcmeIcons.activity` em vez de `Spacing/md` e `activity`. Referência da API:
`docs/FIGMA_CONNECT.md` §7 e o guia `docs/DESIGN_OPS.md` §2–4, no repositório do figma2dart.

**O ciclo é sempre o mesmo:** edite o `lib/figma_policy.dart`, rode `figma2dart doctor --json` de dentro do pacote e
leia `policy`. Repita até `missing` ficar vazio ou só com o que não tem par no DS.

```json
"policy": {
  "tokens": {"total": 340, "withDart": 310, "missing": [
    {"group": "MarcaA/Colors/Feedback/Success", "count": 12, "fix": "nenhuma classe: …", "examples": ["…"]},
    {"group": "context.acme.designTokens.colorScheme.content", "count": 3, "fix": "a classe não tem o membro: …",
     "examples": ["MarcaA/Colors/Content/02 → x02"]}
  ]},
  "textStyles": {"total": 24, "withDart": 24, "missing": []},
  "icons": {"total": 352, "withDart": 340, "missing": [{"name": "ia-sparkle", "key": "6249…", "expected": "iaSparkle"}]}
}
```

## 1. Retrato com tokens e ícones

O `doctor` confere contra o `figma_library.json` do pacote. O retrato precisa trazer `files` (tokens e estilos de
texto) e as páginas de ícones.

- **Sem `policy` no doctor**, ou com o aviso "retrato sem tokens nem ícones", peça ao usuário:
  1. no Figma, em cada página de componentes do DS **e na página de ícones**, sem nada selecionado, rodar o plugin
     e **Exportar .zip** (modo Biblioteca);
  2. se as variáveis estiverem em outro arquivo do Figma (uma biblioteca de tokens), exportar também uma página
     dele.

  Depois disso, rode `figma2dart library <zips> --json`.
- **Ícones:** entram os componentes de uma página com "Icons" ou "Ícones" no nome, e os sets chamados `Icon`/`Icons`
  em qualquer página. Se `policy.icons` não aparecer, pergunte ao usuário qual página tem os ícones.

## 2. Tokens

1. **Ver os caminhos.** Do retrato:

   ```sh
   # coleção e caminho (sem o último nível), com a contagem
   jq -r '.files[].tokens[] | split("/") | "\(.[0])\t\(.[1:-1] | join("/"))"' figma_library.json | sort | uniq -c
   # caminhos que aparecem em mais de uma coleção: a coleção é a marca
   jq -r '[.files[].tokens[] | split("/") | {c: .[0], p: (.[1:-1] | join("/"))}] | map(select(.p != ""))
     | group_by(.p)[] | select(([.[].c] | unique | length) > 1) | "\(.[0].p)\t\([.[].c] | unique | join(", "))"' \
     figma_library.json
   ```

2. **`collections` ou `scopes`:**
   - a coleção é o tipo de token (`Spacing/md`, `Radius/sm`): `collections: {'Spacing': …}`;
   - a coleção é a marca (o mesmo caminho em `MarcaA` e `MarcaB`, como mostra o segundo comando): `scopes`, pelo caminho
     sem a marca (`'Colors/Surface': …`). Não liste as marcas: o tema escolhe, e uma marca nova funciona sozinha;
   - os dois podem coexistir. A CLI procura primeiro em `collections` e, depois, o caminho mais longo de `scopes`.
3. **Achar a classe e o `via` de cada grupo.**
   - **Como o código do DS já usa os tokens:** o jeito mais rápido de achar o `via`.

     ```sh
     grep -rhoE "context\.[A-Za-z_.]+" <pacote do DS>/lib | sort | uniq -c | sort -rn | head -40
     ```

     `context.acme.designTokens.colorScheme.surface.primary` dá o `via` `context.acme.designTokens.colorScheme.surface`.
   - **A classe:** o tipo que esse `via` devolve. Siga os getters a partir da extensão em `BuildContext`
     (`grep -rn "extension .* on BuildContext" <DS>/lib`) até a classe com um membro por token. Com o LSP do Dart
     (Copilot CLI), o hover em cada parte do `via` dá o tipo, e os símbolos do arquivo listam os membros da classe.
   - **Constantes estáticas** (sem tema): sem `via`; o código fica `DsSpacing.md`.
   - Confira que os membros batem com o último nível do nome do Figma em camelCase (`On Brand` → `onBrand`).
4. **Nomes que não batem** (`02` → `two`): `names: {'02': 'two'}` no `TokenSource`. Não mude a classe do DS. Ponha
   em `names` só o que o doctor apontar em "a classe não tem o membro", e só com o membro que existe de verdade na
   classe; se não houver par, deixe de fora e relate.
5. **Estilos de texto:** `textStyles: TokenSource(<classe>, via: …)`, achados do mesmo jeito.
6. Rode o doctor. `missing` com "nenhuma classe" é um grupo que falta em `collections`/`scopes`; com "a classe não tem
   o membro", falta `names` ou o membro não existe.

## 3. Ícones

1. **Achar a classe ou o enum dos ícones no DS:**

   ```sh
   grep -rnE "enum \w*Icon|class \w*Icons?\b" <DS>/lib | head
   ```

   - enum: `IconTable(values: AcmeIconName.values)`;
   - classe com uma constante estática por ícone (`static const activity = AcmeIconData('activity')`):
     `IconTable.constants(AcmeIcons)`.
2. **A convenção já cobre a maioria:** o nome do Figma em camelCase (`arrow-up-right` → `arrowUpRight`).
3. Rode o doctor. Para cada `icons.missing`:
   - procure a constante certa no DS (`grep -n "<parte do nome>" <arquivo dos ícones>`); achando, ponha em
     `byKey: {'<key do missing>': AcmeIcons.<constante>}`. A key vem do doctor, copiada;
   - sem constante parecida, não invente: relate como ícone só do Figma.
   - Muitos `missing` com o mesmo padrão (sufixo `-fill`, prefixo de pasta) indicam convenção diferente: mostre ao
     usuário antes de encher o `byKey`.

## 4. Ignorados e regras por tipo

- **`ignored`:** componente que só existe no Figma e não começa com `_` ou `.` (anotação de handoff, nota de
  design). Pergunte ao usuário; nunca deduza pelo nome.
- **`kinds`:** só se o usuário pedir regras (ex.: template exige `guide`). Veja FIGMA_CONNECT §7.1.

## 5. Conferir e relatar

- `flutter analyze` no pacote e `figma2dart doctor --json`.
- Relate: tokens, estilos e ícones com Dart / total; o que ficou em `missing` e por quê (sem par no DS, decisão do
  usuário pendente); o que foi para `names` e `byKey`.

## Não fazer

- Alterar classes do DS para casar com o Figma.
- Digitar key de ícone: copie do `missing[].key` do doctor.
- Pôr em `names` ou `byKey` um membro que não existe: o doctor continua apontando, e o código gerado quebraria.
- Listar marcas: a coleção-marca entra por `scopes`.
