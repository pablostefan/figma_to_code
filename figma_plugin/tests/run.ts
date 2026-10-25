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
