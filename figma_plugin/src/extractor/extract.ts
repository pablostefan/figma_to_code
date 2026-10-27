import { Ctx, type ComponentOwner, IMAGE_SCALE, type ImageRequest, isVectorOnly, ownerOf, propDefs } from './context';
import { EXTRACTOR_VERSION, IR_VERSION } from './ir';
import type { ComponentDef, FlowDef, FlowEdge, IR, Kind, ScreenDef, VariantDef, Via } from './ir';
import { serializeNode } from './serialize';

export interface ExtractOptions {
  via: Via;
  /** Selection (plugin) or nodes resolved from ids (MCP). Empty = library export of `page`. */
  nodes: readonly SceneNode[];
  /** Page for a library export; defaults to the page of the nodes or the current page. */
  page?: PageNode;
  kind?: Kind;
  notes?: string;
  images: boolean;
  svg: boolean;
  /** Fixed timestamp, so repeated runs produce byte-identical IR (needed for MCP paging). */
  exportedAt?: string;
}

export interface ExtractResult {
  ir: IR;
  images: ImageRequest[];
}

export interface Plan {
  kind: Kind;
  components: ComponentOwner[];
  frames: SceneNode[];
  /** Why a forced kind could not be honored, if that happened. */
  warning?: string;
}

const SCREEN_TYPES = new Set(['FRAME', 'GROUP', 'COMPONENT', 'INSTANCE']);

/** Screens of a section, including those inside nested sections. */
function screensIn(section: SectionNode): SceneNode[] {
  return section.children.flatMap((c) => (c.type === 'SECTION' ? screensIn(c) : SCREEN_TYPES.has(c.type) ? [c] : []));
}

/** Canvas position; `x`/`y` are relative to the parent, which differs between sections. */
const canvasX = (n: SceneNode) => n.absoluteTransform[0][2];
const canvasY = (n: SceneNode) => n.absoluteTransform[1][2];

/** Decides what is being exported from the selection, without serializing anything. Cheap enough for live UI. */
export function plan(nodes: readonly SceneNode[], forced?: Kind): Plan {
  if (!nodes.length) return { kind: 'library', components: [], frames: [] };
  if (forced === 'library') return { kind: 'library', components: [], frames: [] };

  const components = new Map<string, ComponentOwner>();
  for (const node of nodes) {
    if (node.type === 'COMPONENT_SET') components.set(node.id, node);
    else if (node.type === 'COMPONENT') {
      const owner = ownerOf(node);
      components.set(owner.id, owner);
    }
  }
  const allComponents = components.size > 0 && nodes.every((n) => n.type === 'COMPONENT_SET' || n.type === 'COMPONENT');

  const unsupported = allComponents ? [] : nodes.filter((n) => n.type !== 'SECTION' && !SCREEN_TYPES.has(n.type));
  if (unsupported.length) {
    return {
      kind: forced ?? 'screen',
      components: [],
      frames: [],
      warning: `Seleção incompatível: use frames, grupos, instâncias, componentes ou sections; "${unsupported[0].name}" é ${unsupported[0].type}`,
    };
  }

  const frames: SceneNode[] = [];
  let section = false;
  for (const node of nodes) {
    if (node.type === 'SECTION') {
      section = true;
      frames.push(...screensIn(node));
    } else {
      frames.push(node);
    }
  }
  frames.sort((a, b) => canvasX(a) - canvasX(b) || canvasY(a) - canvasY(b));

  const inferred: Kind = allComponents ? 'component' : section || frames.length > 1 ? 'flow' : 'screen';
  if (!frames.length && !allComponents) {
    return {
      kind: forced ?? inferred,
      components: [],
      frames: [],
      warning: 'A section selecionada não contém nenhuma tela exportável',
    };
  }
  if (!forced || forced === inferred) return { kind: inferred, components: [...components.values()], frames };
  if (forced === 'component' && !allComponents) {
    return {
      kind: inferred,
      components: [...components.values()],
      frames,
      warning: 'Para exportar como componente, selecione apenas componentes ou component sets',
    };
  }
  return { kind: forced, components: [...components.values()], frames };
}

function pageOf(node: BaseNode): PageNode | undefined {
  let current: BaseNode | null = node;
  while (current && current.type !== 'PAGE') current = current.parent;
  return current ?? undefined;
}

export async function extract(options: ExtractOptions): Promise<ExtractResult> {
  const pages = new Set(options.nodes.map((n) => pageOf(n)?.id));
  if (pages.size > 1) throw new Error('Selecione nós de uma única página.');
  const page = (options.nodes[0] && pageOf(options.nodes[0])) || options.page || figma.currentPage;
  if (page.id !== figma.currentPage.id) await figma.setCurrentPageAsync(page);

  const p = plan(options.nodes, options.kind);
  if (p.warning) throw new Error(p.warning);
  const ctx = new Ctx({ via: options.via, kind: p.kind, images: options.images, svg: options.svg });
  const components: ComponentDef[] = [];
  const screens: ScreenDef[] = [];
  let flow: FlowDef | undefined;

  switch (p.kind) {
    case 'library': {
      const owners = page
        .findAllWithCriteria({ types: ['COMPONENT_SET', 'COMPONENT'] })
        .filter((n) => n.type === 'COMPONENT_SET' || n.parent?.type !== 'COMPONENT_SET');
      for (const owner of owners) components.push(await componentDef(owner, 'exported', ctx));
      for (const variable of await figma.variables.getLocalVariablesAsync()) await ctx.variable(variable.id);
      for (const style of await figma.getLocalTextStylesAsync()) await ctx.textStyle(style.id);
      break;
    }
    case 'component':
      for (const owner of p.components) components.push(await componentDef(owner, 'exported', ctx));
      break;
    case 'screen':
    case 'flow':
      screens.push(...(await screenDefs(p.frames, ctx)));
      if (p.kind === 'flow') flow = flowDef(p.frames, page);
      break;
  }

  // Map iteration includes dependencies discovered while serializing another dependency.
  if (p.kind !== 'library') {
    for (const [id, owner] of ctx.dependencies) {
      if (!components.some((c) => c.id === id)) components.push(await componentDef(owner, 'dependency', ctx));
    }
  }

  ctx.finish();
  const paintStyles = Object.keys(ctx.paintStyles).length ? ctx.paintStyles : undefined;
  const ir: IR = {
    irVersion: IR_VERSION,
    kind: p.kind,
    source: {
      via: options.via,
      extractor: EXTRACTOR_VERSION,
      ...(figma.fileKey ? { fileKey: figma.fileKey } : {}),
      fileName: figma.root.name,
      pageName: page.name,
      exportedAt: options.exportedAt ?? new Date().toISOString(),
    },
    ...(options.notes ? { intent: { notes: options.notes } } : {}),
    tokens: ctx.tokens,
    textStyles: ctx.textStyles,
    ...(paintStyles ? { paintStyles } : {}),
    componentRefs: ctx.componentRefs,
    components,
    screens,
    ...(flow ? { flow } : {}),
    lint: ctx.lint,
  };
  return { ir, images: ctx.images };
}

// ---------------------------------------------------------------- components

async function componentDef(owner: ComponentOwner, role: ComponentDef['role'], ctx: Ctx): Promise<ComponentDef> {
  ctx.componentRef(owner);
  const members = owner.type === 'COMPONENT_SET' ? owner.children.filter((c): c is ComponentNode => c.type === 'COMPONENT') : [owner];
  const variants: VariantDef[] = [];
  for (const member of members) {
    const variant: VariantDef = {
      id: member.id,
      key: member.key,
      name: member.name,
      props: member.variantProperties ? { ...member.variantProperties } : {},
      tree: await serializeNode(member, ctx, { root: true, inAutoLayout: false, inComponent: true }),
    };
    const image = ctx.image(member, slugFolder(owner.name));
    if (image) variant.image = image;
    if (ctx.options.svg && isVectorOnly(member)) {
      try {
        variant.svg = await member.exportAsync({ format: 'SVG_STRING' });
      } catch {
        // SVG export is not available in every environment (e.g. use_figma); the tree still describes the vectors.
      }
    }
    variants.push(variant);
  }
  return {
    id: owner.id,
    key: owner.key,
    name: owner.name,
    role,
    ...(owner.description ? { description: owner.description } : {}),
    props: propDefs(owner),
    variants,
  };
}

const slugFolder = (name: string) => name.replace(/[^\w-]+/g, '_').toLowerCase();

// ---------------------------------------------------------------- screens

/** Groups `Screen / state` frames into one screen with several states. */
async function screenDefs(frames: SceneNode[], ctx: Ctx): Promise<ScreenDef[]> {
  const screens = new Map<string, ScreenDef>();
  for (const frame of frames) {
    const [base, ...rest] = frame.name.split(' / ');
    const name = base.trim();
    const state = rest.join(' / ').trim() || 'default';
    const screen = screens.get(name) ?? { name, states: [] };
    screens.set(name, screen);
    const image = ctx.image(frame, 'screens');
    screen.states.push({
      state,
      id: frame.id,
      frameName: frame.name,
      tree: await serializeNode(frame, ctx, { root: true, inAutoLayout: false, inComponent: false, screen: frame }),
      ...(image ? { image, imageScale: IMAGE_SCALE } : {}),
    });
  }
  return [...screens.values()];
}

// ---------------------------------------------------------------- flow

function flowDef(frames: SceneNode[], page: PageNode): FlowDef {
  const ids = new Set(frames.map((f) => f.id));
  const edges: FlowEdge[] = [];
  for (const frame of frames) {
    const nodes: SceneNode[] = [frame, ...('findAll' in frame ? frame.findAll((n) => 'reactions' in n && n.reactions.length > 0) : [])];
    for (const node of nodes) {
      if (!('reactions' in node)) continue;
      for (const reaction of node.reactions) {
        const actions = reaction.actions ?? (reaction.action ? [reaction.action] : []);
        for (const action of actions) {
          const edge: FlowEdge = {
            from: frame.id,
            trigger: { node: node.id, name: node.name, type: reaction.trigger?.type ?? 'NONE' },
            to: null,
            action: action.type,
          };
          switch (action.type) {
            case 'NODE':
              edge.to = action.destinationId;
              edge.navigation = action.navigation;
              edge.transition = action.transition?.type ?? 'INSTANT';
              break;
            case 'BACK':
              edge.to = 'back';
              break;
            case 'CLOSE':
              edge.to = 'close';
              break;
            case 'URL':
              edge.to = action.url;
              break;
          }
          edges.push(edge);
        }
      }
    }
  }
  const start = page.flowStartingPoints.find((p) => ids.has(p.nodeId))?.nodeId ?? frames[0]?.id ?? null;
  return { start, edges };
}
