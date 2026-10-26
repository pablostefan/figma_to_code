---
name: figma2dart-connect
description: Escreve a anotação @FigmaConnect (*.figma.dart) de um componente do Design System a partir do Figma (MCP do Figma) e do código do widget. Use para anotar componentes do DS no pacote de mapeamentos.
---

# Anotar um componente do DS

Entrada: o componente do inventário (`id`, `key`, `name`) e o pacote de mapeamentos (o que tem `lib/connect/`).

- Referência da API: `docs/FIGMA_CONNECT.md` do repositório do figma2dart (o `figma_connect` do `pubspec.yaml` do
  pacote aponta para ele: o doc fica em `<figma_connect>/../docs/`).
- As anotações que já existem em `lib/connect/` são o modelo: siga o estilo delas.

## 1. Ler o Figma

- `use_figma` com o script **Detalhe** (fim desta skill), trocando o id. Volta as props (nome, tipo, padrão,
  opções), a descrição, o número de variants e as instâncias expostas (caminho, componente, props).
- `get_screenshot` do mesmo id, para ver as variants.
- **Nunca digite a key:** copie do resultado. É a do component set (ou do componente, quando não há variants).

## 2. Achar o widget

- No pacote do DS (dependência do pacote de mapeamentos), procure a classe pelo nome (`Button` → `DsButton`, com o
  mesmo prefixo das anotações que já existem) e pela descrição do Figma.
- Leia todos os construtores (os nomeados também), os enums dos parâmetros e o doc da classe.
- Dois candidatos ou nenhum: **pergunte**, não adivinhe. Sem widget no DS, não anote. Relate como "só no Figma",
  ou como falta no DS.

## 3. Ligar cada prop a um parâmetro

Monte esta tabela antes de escrever, com uma linha por prop do Figma:

| Prop do Figma | Vira |
|---|---|
| TEXT | `f.text('label')` |
| BOOLEAN | `f.boolean('x')`. Se só mostra ou esconde outra prop: `f.boolean('showIcon') ? f.icon('icon') : null` |
| VARIANT | `f.variant('size', {'md': DsXSize.md, …})` com **todas** as opções. Opção que é estado vira o valor de outro parâmetro: `'disabled'` → `onPressed: null`, `'error'` → `errorText` |
| INSTANCE_SWAP de ícone | `f.icon('icon')` (nome do Figma em camelCase: `arrow-up-right` → `arrowUpRight`) |
| INSTANCE_SWAP de outra coisa | `f.instance('x')` |
| Instância exposta | `f.nested('<caminho>').text('label')` quando o widget recebe só o dado; `f.instance('<caminho>')` quando recebe o widget |
| Prop sem parâmetro no código | `figmaNotes`: `FigmaNote.ignore('<motivo>')` (só visual, ou só vale noutra variant), `.derive('<como>')`, `.map({...})` |
| Parâmetro sem prop (callback, acessibilidade, controller) | `f.guided('onPressed', guide: '<o que a tela decide>', or: <valor neutro>)`, só se for obrigatório ou mudar o que se vê. Parâmetro opcional sem efeito no Figma fica de fora |

- **Variant que troca o widget** (`type=icon` → `DsAvatar.icon`): uma função por caso, com a mesma `key` e
  `when: {'type': 'icon'}`. As props que não valem naquele caso vão em `figmaNotes`.
- **Prop do Figma que o widget calcula sozinho** (o tom do Badge sai do `direction`): `FigmaNote.ignore` com o
  motivo.

## 4. Escolher a cobertura

- **`complete`** (padrão): toda prop é lida ou tem `FigmaNote`.
- **`partial`**: parte do conteúdo é exemplo ou depende da tela (as linhas de uma lista). Use `f.guided` para essa
  parte, mais o `guide`. Bloco composto leva `kind: FigmaKind.section`.
- **`sketch`**: o conteúdo são camadas, não props (template de tela). Use `@FigmaConnect.sketch(…, guide: …)`
  sobre um `typedef` para o widget, sem função.
- O `figma_policy.dart` do pacote pode exigir mais por tipo (template: `guide`, `docs` e um `Example.code`).

## 5. Escrever

1. **`lib/connect/<arquivo do widget>.figma.dart`** (`DsButton` → `ds_button.figma.dart`):
   - imports do DS, do `figma_connect` e de `flutter/widgets.dart`;
   - doc de uma linha: ``/// Figma `Name` → [DsWidget]. <o que não é óbvio>``.
2. **`docs/<arquivo>.md`**, só se houver `f.guided`, `partial`, `sketch` ou uma armadilha conhecida:
   - `## Geral`, uma seção `## <parte>` por parte guiada, e `## Erros comuns` (com ❌);
   - sem repetir o construtor nem as props (a CLI já lê os dois).
3. **README do pacote**: uma linha na tabela de mapeamentos.
4. **`test/mappings_test.dart`**, se existir:
   - em `defaults`, os valores padrão do Figma: o `default` de cada prop do script. Para um ícone, use só o nome
     (`Icon name=mail` → `'mail'`). Uma instância exposta é um mapa com as props dela;
   - em `variantOptions`, todas as opções de cada VARIANT;
   - `sketch` não entra (não tem função).

## 6. Conferir

`flutter analyze` e `flutter test` de dentro do pacote, até passar.

- "variant x=y sem mapeamento": falta essa opção no `f.variant`.
- "prop ausente no teste": falta o valor em `defaults`.

## Não fazer

- Alterar o widget do DS.
- Inventar uma key, uma opção de variant ou um parâmetro.
- Usar `f.guided` para algo que o Figma tem: vira lacuna em toda tela.
- Copiar o texto de exemplo do Figma (o padrão da prop) como valor fixo no código.
- Escrever no arquivo do Figma: os scripts são só de leitura.

## Scripts do `use_figma`

São só de leitura. Se a ferramenta pedir, abra a sessão do arquivo do DS antes (`create_session` com a `fileKey`
da URL).

**Inventário**: os componentes do arquivo. `pages` vazio lê todas as páginas. Se o resultado passar do limite da
ferramenta, rode por página.

```js
const pages = []; // ex.: ['Components']
const out = [];
for (const page of figma.root.children) {
  if (pages.length && !pages.includes(page.name)) continue;
  await page.loadAsync();
  for (const n of page.findAllWithCriteria({ types: ['COMPONENT_SET', 'COMPONENT'] })) {
    if (n.type === 'COMPONENT' && n.parent?.type === 'COMPONENT_SET') continue; // variant: conta o set
    out.push({ page: page.name, id: n.id, key: n.key, name: n.name });
  }
}
return out;
```

**Detalhe**: um componente, pelo `id` do inventário.

```js
const id = 'COLE_O_ID';
const node = await figma.getNodeByIdAsync(id);
let page = node;
while (page.type !== 'PAGE') page = page.parent;
await page.loadAsync();
const strip = (name) => name.replace(/#\d+:\d+$/, '');
const label = async (componentId) => {
  const c = await figma.getNodeByIdAsync(componentId);
  if (!c) return componentId;
  return c.parent?.type === 'COMPONENT_SET' ? `${c.parent.name} ${c.name}` : c.name;
};
const props = {};
for (const [raw, d] of Object.entries(node.componentPropertyDefinitions)) {
  props[strip(raw)] = {
    type: d.type,
    default: d.type === 'INSTANCE_SWAP' ? await label(d.defaultValue) : d.defaultValue,
    ...(d.variantOptions ? { options: d.variantOptions } : {}),
  };
}
const base = node.type === 'COMPONENT_SET' ? node.defaultVariant : node;
const pathFrom = (n) => {
  const names = [];
  for (let c = n; c && c.id !== base.id; c = c.parent) names.unshift(c.name);
  return names.join('/');
};
const exposed = [];
for (const inst of base.findAllWithCriteria({ types: ['INSTANCE'] })) {
  if (!inst.isExposedInstance) continue;
  const main = await inst.getMainComponentAsync();
  const owner = main?.parent?.type === 'COMPONENT_SET' ? main.parent : main;
  const values = {};
  for (const [k, p] of Object.entries(inst.componentProperties)) {
    values[strip(k)] = p.type === 'INSTANCE_SWAP' ? await label(p.value) : p.value;
  }
  exposed.push({ path: pathFrom(inst), component: owner?.name, props: values });
}
return {
  key: node.key,
  name: node.name,
  description: node.description,
  variants: node.type === 'COMPONENT_SET' ? node.children.length : 1,
  props,
  exposed,
};
```
