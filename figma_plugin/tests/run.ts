import { Ctx } from '../src/extractor/context';
import { plan } from '../src/extractor/extract';
import { pageIndex, paginate } from '../src/mcp/entry';
import { serializeNode } from '../src/extractor/serialize';

function assert(condition: unknown, message: string): asserts condition {
  if (!condition) throw new Error(message);
}

function equal<T>(actual: T, expected: T, message: string) {
  if (actual !== expected) throw new Error(`${message}: esperado ${String(expected)}, recebido ${String(actual)}`);
}

const scene = (type: SceneNode['type'], name: string) =>
  ({
    id: `${type}:${name}`,
    type,
    name,
    width: 100,
    height: 100,
    visible: true,
    absoluteTransform: [
      [1, 0, 0],
      [0, 1, 0],
    ],
  }) as unknown as SceneNode;

equal(plan([scene('FRAME', 'Tela')]).kind, 'screen', 'um frame deve ser uma tela');
assert(plan([scene('TEXT', 'Título')]).warning?.includes('TEXT'), 'texto solto deve ser rejeitado');
equal(plan([scene('TEXT', 'Título')], 'library').kind, 'library', 'forçar biblioteca deve ignorar a seleção');

const emptySection = { ...scene('SECTION', 'Vazia'), children: [] } as unknown as SectionNode;
assert(plan([emptySection]).warning?.includes('não contém'), 'section vazia deve ser rejeitada');

const paged = '🙂"\\'.repeat(20_000);
const pages = paginate(paged);
assert(pages.length > 1, 'texto grande deve ser paginado');
equal(pages.join(''), paged, 'paginação deve preservar todos os caracteres');
equal(pageIndex(undefined, pages.length), 0, 'página omitida deve usar a primeira');
equal(pageIndex(1, pages.length), 1, 'índice inteiro válido deve ser aceito');
for (const invalid of [-1, 0.5, pages.length]) {
  let rejected = false;
  try {
    pageIndex(invalid, pages.length);
  } catch {
    rejected = true;
  }
  assert(rejected, `página inválida ${invalid} deve ser rejeitada`);
}

const main = {
  id: 'component:main',
  type: 'COMPONENT',
  name: 'Card',
  key: 'card-key',
  parent: null,
  remote: false,
  description: '',
  componentPropertyDefinitions: {},
  getPublishStatusAsync: async () => 'UNPUBLISHED',
} as unknown as ComponentNode;

const instanceRecord: Record<string, unknown> = {
  id: 'instance:card',
  type: 'INSTANCE',
  name: 'Card',
  width: 100,
  height: 40,
  visible: true,
  componentProperties: {},
  exposedInstances: [],
  getMainComponentAsync: async () => main,
};
const instance = instanceRecord as unknown as InstanceNode;
const firstLabel = { id: 'text:first', type: 'TEXT', name: 'Label', characters: 'Primeiro', parent: instance } as unknown as TextNode;
const secondLabel = { id: 'text:second', type: 'TEXT', name: 'Label', characters: 'Segundo', parent: instance } as unknown as TextNode;
instanceRecord.overrides = [
  { id: firstLabel.id, overriddenFields: ['characters'] },
  { id: secondLabel.id, overriddenFields: ['characters'] },
];

const targets = new Map<string, BaseNode>([
  [firstLabel.id, firstLabel],
  [secondLabel.id, secondLabel],
]);
(globalThis as unknown as { figma: { getNodeByIdAsync(id: string): Promise<BaseNode | null> } }).figma = {
  getNodeByIdAsync: async (id) => targets.get(id) ?? null,
};

const ctx = new Ctx({ via: 'plugin', kind: 'component', images: false, svg: false });
const serialized = await serializeNode(instance, ctx, { root: true, inAutoLayout: false, inComponent: true });
const overrides = serialized.instance?.overrides ?? [];
equal(overrides.length, 2, 'camadas homônimas devem manter seus dois overrides');
equal(overrides[0].id, firstLabel.id, 'primeiro override deve manter o id da camada');
equal(overrides[1].id, secondLabel.id, 'segundo override deve manter o id da camada');
assert(ctx.dependencies.has(main.id), 'componente local aninhado deve ser registrado como dependência');

// Instância numa tela: caixa relativa ao frame (para recortar o PNG) e o conteúdo de dentro (textos e instâncias).
const box = (x: number, y: number, width: number, height: number) => ({ x, y, width, height });
const screenFrame = { ...scene('FRAME', 'Extrato'), absoluteBoundingBox: box(100, 200, 390, 844) } as unknown as FrameNode;
const nestedMain = { ...main, id: 'component:row', name: 'Row', key: 'row-key' } as unknown as ComponentNode;
const nestedRecord: Record<string, unknown> = {
  id: 'instance:row',
  type: 'INSTANCE',
  name: 'Row',
  visible: true,
  // `icon` liga a uma camada oculta nesta instância (sai do conteúdo); `badge`, a uma visível (fica).
  componentProperties: {
    'value#1:2': { type: 'TEXT', value: 'R$ 10,00' },
    'icon#1:3': { type: 'INSTANCE_SWAP', value: 'swap:icon' },
    'badge#1:4': { type: 'INSTANCE_SWAP', value: 'swap:badge' },
  },
  getMainComponentAsync: async () => nestedMain,
};
const listRecord: Record<string, unknown> = {
  ...instanceRecord,
  id: 'instance:list',
  name: 'Lista',
  overrides: [],
  absoluteBoundingBox: box(116, 300, 358, 120),
};
const day = { id: 'text:day', type: 'TEXT', name: 'day', visible: true, characters: 'Hoje' };
const hidden = { id: 'text:hidden', type: 'TEXT', name: 'hidden', visible: false, characters: 'não aparece' };
listRecord.children = [day, hidden, nestedRecord];
for (const child of listRecord.children as Record<string, unknown>[]) child.parent = listRecord;
nestedRecord.children = [
  { id: 'text:value', type: 'TEXT', name: 'value', visible: true, characters: 'R$ 10,00', parent: nestedRecord },
  { id: 'frame:icon', type: 'FRAME', name: 'icon', visible: false, componentPropertyReferences: { mainComponent: 'icon#1:3' } },
  { id: 'frame:badge', type: 'FRAME', name: 'badge', visible: true, componentPropertyReferences: { mainComponent: 'badge#1:4' } },
];
const listed = await serializeNode(listRecord as unknown as InstanceNode, ctx, {
  root: false,
  inAutoLayout: true,
  inComponent: false,
  screen: screenFrame,
});
equal(JSON.stringify(listed.bounds), JSON.stringify(box(16, 100, 358, 120)), 'instância na tela guarda a caixa relativa ao frame');
equal(
  JSON.stringify(listed.instance?.content),
  JSON.stringify([
    { path: 'day', text: 'Hoje' },
    { path: 'Row', component: 'Row', props: { value: 'R$ 10,00', badge: 'swap:badge' } },
    { path: 'Row/value', text: 'R$ 10,00' },
  ]),
  'conteúdo da instância: textos e instâncias visíveis, na ordem das camadas, sem troca de instância oculta',
);
const inComponent = await serializeNode(listRecord as unknown as InstanceNode, ctx, { root: false, inAutoLayout: true, inComponent: true });
assert(!inComponent.bounds && !inComponent.instance?.content, 'fora de uma tela (definição de componente) não há caixa nem conteúdo');
console.log('✔ conteúdo e caixa das instâncias na tela');

// Texto: limite de linhas, reticências e como a caixa cresce.
const limited = {
  ...scene('TEXT', 'descrição'),
  characters: 'Um texto longo',
  textAlignHorizontal: 'LEFT',
  rotation: 180,
  maxLines: 2,
  textTruncation: 'ENDING',
  textAutoResize: 'HEIGHT',
  fills: [],
  strokes: [],
  effects: [],
  getStyledTextSegments: () => [],
} as unknown as TextNode;
const limitedNode = await serializeNode(limited, ctx, { root: false, inAutoLayout: true, inComponent: false });
const text = limitedNode.text;
equal(JSON.stringify([text?.maxLines, text?.truncation, text?.autoResize]), JSON.stringify([2, 'ENDING', 'HEIGHT']), 'texto guarda limite de linhas, reticências e crescimento');
equal(limitedNode.rotation, 180, 'nó girado guarda a rotação');
const flat = await serializeNode({ ...limited, rotation: 0 } as unknown as TextNode, ctx, { root: false, inAutoLayout: true, inComponent: false });
assert(!('rotation' in flat), 'sem rotação, o campo não aparece');
console.log('✔ limites de texto e rotação');

// Lint: o mesmo aviso no mesmo nó (dois vetores `Vector` num ícone) sai uma vez.
const lintCtx = new Ctx({ via: 'plugin', kind: 'screen', images: false, svg: false });
const icon = { id: 'instance:input', name: 'Input' };
lintCtx.issue(icon, 'style-override', 'estilo sobrescrito em "leftIcon/Vector" (strokes)');
lintCtx.issue(icon, 'style-override', 'estilo sobrescrito em "leftIcon/Vector" (strokes)');
lintCtx.issue(icon, 'style-override', 'estilo sobrescrito em "rightIcon/Vector" (strokes)');
equal(lintCtx.lint.length, 2, 'aviso repetido no mesmo nó sai uma vez');
console.log('✔ lint sem repetição');
