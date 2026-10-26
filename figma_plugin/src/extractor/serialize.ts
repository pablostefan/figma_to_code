import { Ctx, hex, isVectorOnly, ownerOf, propName, readPaints, round } from './context';
import type {
  Effect,
  ExposedInstance,
  InstanceContent,
  InstanceInfo,
  IRNode,
  Layout,
  Override,
  Paint,
  PropValue,
  Sizing,
  Style,
  SwapValue,
  TextInfo,
} from './ir';

interface Placement {
  /** Root of a screen or a component variant: its own position is irrelevant. */
  root: boolean;
  /** Whether the parent places this node with auto layout. */
  inAutoLayout: boolean;
  /** Inside a component definition: record component property bindings. */
  inComponent: boolean;
  /** The screen frame this node is in: instances record their box relative to it and their content. */
  screen?: SceneNode;
}

/** Most items recorded in `InstanceInfo.content`, so a big list or template does not blow up the export. */
export const CONTENT_LIMIT = 200;

type Bound = Partial<Record<string, VariableAlias | VariableAlias[]>>;

const boundOf = (node: SceneNode, field: string): VariableAlias | undefined => {
  const bound = ('boundVariables' in node ? node.boundVariables : undefined) as Bound | undefined;
  const alias = bound?.[field];
  return Array.isArray(alias) ? undefined : alias;
};

/** Override fields that never mean "customized beyond the API". */
const IGNORED_OVERRIDES = new Set(['name', 'exposedInstances', 'reactions']);
/** Fields a component property can drive, through `componentPropertyReferences`. */
const PROP_FIELDS = new Set(['characters', 'visible', 'mainComponent']);
const STYLE_OVERRIDES = new Set(['fills', 'strokes', 'effects', 'opacity', 'cornerRadius', 'strokeWeight', 'fontSize']);

export async function serializeNode(node: SceneNode, ctx: Ctx, placement: Placement): Promise<IRNode> {
  const out: IRNode = {
    id: node.id,
    type: node.type,
    name: node.name,
    fidelity: 'exact',
    size: { width: round(node.width), height: round(node.height) },
  };
  if (!node.visible) out.visible = false;
  if ('rotation' in node && Math.abs(node.rotation) >= 0.5) out.rotation = round(node.rotation);

  if (placement.screen && !placement.root) {
    const bounds = boundsIn(node, placement.screen);
    if (bounds) out.bounds = bounds;
  }

  const absolute = 'layoutPositioning' in node && node.layoutPositioning === 'ABSOLUTE';
  if (!placement.root && (!placement.inAutoLayout || absolute)) out.position = { x: round(node.x), y: round(node.y) };

  const sizing = readSizing(node);
  if (sizing) out.sizing = sizing;

  const sizeTokens = await readSizeTokens(node, ctx);
  if (sizeTokens) out.sizeTokens = sizeTokens;
  const limits = await readLimits(node, ctx);
  if (limits) out.limits = limits;
  if ('explicitVariableModes' in node) {
    const modes = await ctx.modes(node.explicitVariableModes);
    if (modes) out.modes = modes;
  }

  if (placement.inComponent && 'componentPropertyReferences' in node && node.componentPropertyReferences) {
    const refs = node.componentPropertyReferences;
    const bindings: NonNullable<IRNode['bindings']> = {};
    if (refs.characters) bindings.characters = propName(refs.characters);
    if (refs.visible) bindings.visible = propName(refs.visible);
    if (refs.mainComponent) bindings.mainComponent = propName(refs.mainComponent);
    if (Object.keys(bindings).length) out.bindings = bindings;
  }

  // Instances are shallow: the component already exists, only its configuration matters.
  if (node.type === 'INSTANCE') {
    const { info, fidelity } = await instanceInfo(node, ctx);
    out.instance = info;
    out.fidelity = fidelity;
    if (placement.screen) {
      const content = await instanceContent(node, ctx);
      if (content.items.length) info.content = content.items;
      if (content.truncated) info.contentTruncated = true;
    }
    return out;
  }

  const layout = await readLayout(node, ctx);
  if (layout) out.layout = layout;

  const style = await readStyle(node, ctx);
  if (style) out.style = style;

  if (node.type === 'TEXT') out.text = await readText(node, ctx);

  if (node.type === 'FRAME' && node.detachedInfo) {
    const from = node.detachedInfo.type === 'library' ? node.detachedInfo.componentKey : node.detachedInfo.componentId;
    ctx.issue(node, 'detached-instance', `frame veio de uma instância desanexada (componente ${from})`);
  }

  if ('children' in node && node.children.length) {
    const autoLayout = 'layoutMode' in node && node.layoutMode !== 'NONE';
    if (!autoLayout && (node.type === 'FRAME' || node.type === 'COMPONENT') && node.children.length > 1 && !isVectorOnly(node)) {
      ctx.issue(node, 'absolute-layout', 'frame com filhos sem auto layout (posições absolutas)');
    }
    out.children = [];
    for (const child of node.children) {
      out.children.push(
        await serializeNode(child, ctx, {
          root: false,
          inAutoLayout: autoLayout,
          inComponent: placement.inComponent,
          screen: placement.screen,
        }),
      );
    }
  }
  return out;
}

function readSizing(node: SceneNode): IRNode['sizing'] {
  if (!('layoutSizingHorizontal' in node)) return undefined;
  try {
    return {
      horizontal: node.layoutSizingHorizontal as Sizing,
      vertical: node.layoutSizingVertical as Sizing,
    };
  } catch {
    return undefined;
  }
}

async function readSizeTokens(node: SceneNode, ctx: Ctx): Promise<IRNode['sizeTokens']> {
  const width = boundOf(node, 'width');
  const height = boundOf(node, 'height');
  if (!width && !height) return undefined;
  const tokens: NonNullable<IRNode['sizeTokens']> = {};
  const widthToken = width && (await ctx.variable(width.id));
  const heightToken = height && (await ctx.variable(height.id));
  if (widthToken) tokens.width = widthToken;
  if (heightToken) tokens.height = heightToken;
  return Object.keys(tokens).length ? tokens : undefined;
}

async function readLimits(node: SceneNode, ctx: Ctx): Promise<IRNode['limits']> {
  if (!('minWidth' in node)) return undefined;
  const limits: NonNullable<IRNode['limits']> = {};
  for (const field of ['minWidth', 'maxWidth', 'minHeight', 'maxHeight'] as const) {
    const raw = node[field];
    if (raw !== null) limits[field] = await ctx.value(round(raw), boundOf(node, field));
  }
  return Object.keys(limits).length ? limits : undefined;
}

// ---------------------------------------------------------------- layout

async function readLayout(node: SceneNode, ctx: Ctx): Promise<Layout | undefined> {
  if (!('layoutMode' in node) || node.layoutMode === 'NONE') return undefined;
  const num = (field: string, raw: number) => ctx.value(round(raw), boundOf(node, field));
  const padding = {
    top: await num('paddingTop', node.paddingTop),
    right: await num('paddingRight', node.paddingRight),
    bottom: await num('paddingBottom', node.paddingBottom),
    left: await num('paddingLeft', node.paddingLeft),
  };
  const gap =
    node.primaryAxisAlignItems === 'SPACE_BETWEEN' ? ('auto' as const) : await num('itemSpacing', node.itemSpacing);
  const layout: Layout = {
    direction: node.layoutMode,
    gap,
    padding,
    align: { main: node.primaryAxisAlignItems, cross: node.counterAxisAlignItems },
    wrap: node.layoutWrap === 'WRAP',
  };
  if (layout.wrap && typeof node.counterAxisSpacing === 'number') {
    layout.counterGap = await num('counterAxisSpacing', node.counterAxisSpacing);
  }
  if (node.layoutMode === 'GRID' && 'gridRowCount' in node) {
    layout.grid = {
      rows: node.gridRowCount,
      columns: node.gridColumnCount,
      rowGap: await num('gridRowGap', node.gridRowGap),
      columnGap: await num('gridColumnGap', node.gridColumnGap),
    };
  }
  const gaps = layout.grid ? [layout.grid.rowGap, layout.grid.columnGap] : [];
  for (const value of [gap, ...gaps, ...Object.values(padding)]) {
    if (value !== 'auto' && value.value > 0 && !value.token) {
      ctx.issue(node, 'raw-spacing', `espaçamento ${value.value} sem variável`);
      break;
    }
  }
  return layout;
}

// ---------------------------------------------------------------- style

const rawColor = (paints: Paint[]) => paints.some((p) => p.type === 'SOLID' && !p.color.token);

async function readStyle(node: SceneNode, ctx: Ctx): Promise<Style | undefined> {
  const style: Style = {};
  const num = (field: string, raw: number) => ctx.value(round(raw), boundOf(node, field));

  if ('fills' in node && node.type !== 'TEXT') {
    const fills = await readPaints(node.fills, ctx);
    const fillStyle = 'fillStyleId' in node ? await ctx.paintStyle(node.fillStyleId) : undefined;
    if (fills.length) style.fills = fills;
    if (fillStyle) style.fillStyle = fillStyle;
    else if (rawColor(fills)) ctx.issue(node, 'raw-color', 'preenchimento sem variável nem estilo');
  }
  if ('strokes' in node && node.strokes.length) {
    const strokes = await readPaints(node.strokes, ctx);
    if (strokes.length) {
      const strokeStyle = 'strokeStyleId' in node ? await ctx.paintStyle(node.strokeStyleId) : undefined;
      style.strokes = strokes;
      if (strokeStyle) style.strokeStyle = strokeStyle;
      else if (rawColor(strokes)) ctx.issue(node, 'raw-color', 'borda sem variável nem estilo');
      style.strokeAlign = node.strokeAlign;
      if ('strokeTopWeight' in node) {
        const sides = [node.strokeTopWeight, node.strokeRightWeight, node.strokeBottomWeight, node.strokeLeftWeight];
        style.strokeWeight = sides.every((w) => w === sides[0])
          ? await num('strokeWeight', sides[0])
          : {
              top: await num('strokeTopWeight', node.strokeTopWeight),
              right: await num('strokeRightWeight', node.strokeRightWeight),
              bottom: await num('strokeBottomWeight', node.strokeBottomWeight),
              left: await num('strokeLeftWeight', node.strokeLeftWeight),
            };
      } else if (typeof node.strokeWeight === 'number') {
        style.strokeWeight = await num('strokeWeight', node.strokeWeight);
      }
    }
  }

  if ('topLeftRadius' in node) {
    const corners = {
      topLeft: await num('topLeftRadius', node.topLeftRadius),
      topRight: await num('topRightRadius', node.topRightRadius),
      bottomRight: await num('bottomRightRadius', node.bottomRightRadius),
      bottomLeft: await num('bottomLeftRadius', node.bottomLeftRadius),
    };
    const list = Object.values(corners);
    if (list.some((c) => c.value > 0)) {
      const uniform = list.every((c) => c.value === list[0].value && c.token === list[0].token);
      style.radius = uniform ? list[0] : corners;
      if (list.some((c) => c.value > 0 && !c.token)) ctx.issue(node, 'raw-radius', 'raio sem variável');
    }
  } else if ('cornerRadius' in node && typeof node.cornerRadius === 'number' && node.cornerRadius > 0) {
    style.radius = await num('cornerRadius', node.cornerRadius);
  }

  if ('opacity' in node && node.opacity < 1) style.opacity = round(node.opacity);
  if ('clipsContent' in node && node.clipsContent) style.clipsContent = true;

  if ('effects' in node && node.effects.length) {
    const styleName = 'effectStyleId' in node ? await ctx.effectStyle(node.effectStyleId) : undefined;
    style.effects = node.effects
      .filter((e) => e.visible)
      .map((e): Effect => {
        if (e.type === 'DROP_SHADOW' || e.type === 'INNER_SHADOW') {
          return { type: e.type, style: styleName, color: hex(e.color), offset: e.offset, radius: e.radius, spread: e.spread };
        }
        return { type: e.type, style: styleName, radius: 'radius' in e ? e.radius : undefined };
      });
  }

  return Object.keys(style).length ? style : undefined;
}

// ---------------------------------------------------------------- text

async function readText(node: TextNode, ctx: Ctx): Promise<TextInfo> {
  const segments = node.getStyledTextSegments(['textStyleId', 'fills', 'fillStyleId', 'fontName', 'fontSize']);
  const describe = async (segment: (typeof segments)[number]) => {
    const style = await ctx.textStyle(segment.textStyleId);
    const colorStyle = await ctx.paintStyle(segment.fillStyleId);
    const fills = await readPaints(segment.fills, ctx);
    const solid = fills.find((f) => f.type === 'SOLID');
    return { style, colorStyle, color: solid?.type === 'SOLID' ? solid.color : undefined };
  };

  const info: TextInfo = { characters: node.characters };
  if (node.textAlignHorizontal !== 'LEFT') info.align = node.textAlignHorizontal;
  if (typeof node.maxLines === 'number') info.maxLines = node.maxLines;
  if (node.textTruncation === 'ENDING') info.truncation = 'ENDING';
  if (node.textAutoResize && node.textAutoResize !== 'WIDTH_AND_HEIGHT') info.autoResize = node.textAutoResize;

  if (segments.length <= 1) {
    const segment = segments[0];
    if (segment) {
      const { style, colorStyle, color } = await describe(segment);
      if (style) info.style = style;
      else info.font = { family: segment.fontName.family, style: segment.fontName.style, size: segment.fontSize };
      if (color) info.color = color;
      if (colorStyle) info.colorStyle = colorStyle;
    }
  } else {
    info.segments = [];
    for (const segment of segments) {
      const { style, colorStyle, color } = await describe(segment);
      info.segments.push({
        characters: segment.characters,
        ...(style ? { style } : {}),
        ...(color ? { color } : {}),
        ...(colorStyle ? { colorStyle } : {}),
      });
    }
  }

  if (segments.some((s) => !s.textStyleId)) ctx.issue(node, 'text-without-style', 'texto sem text style');
  const parts = info.segments ?? [info];
  if (parts.some((s) => s.color && !s.color.token && !s.colorStyle)) ctx.issue(node, 'raw-color', 'cor de texto sem variável nem estilo');
  return info;
}

// ---------------------------------------------------------------- instances

/** Box of [node] relative to the [screen] frame, to crop it from the screen image; null when Figma has no box. */
export function boundsIn(node: SceneNode, screen: SceneNode): IRNode['bounds'] | undefined {
  const box = 'absoluteBoundingBox' in node ? node.absoluteBoundingBox : null;
  const frame = 'absoluteBoundingBox' in screen ? screen.absoluteBoundingBox : null;
  if (!box || !frame) return undefined;
  return { x: round(box.x - frame.x), y: round(box.y - frame.y), width: round(box.width), height: round(box.height) };
}

/** What a screen instance shows inside: visible texts and nested instances (component and props), in layer order. */
export async function instanceContent(
  instance: InstanceNode,
  ctx: Ctx,
): Promise<{ items: InstanceContent[]; truncated: boolean }> {
  const items: InstanceContent[] = [];
  let truncated = false;
  const visit = async (node: SceneNode): Promise<void> => {
    for (const child of 'children' in node ? node.children : []) {
      if (!child.visible) continue;
      if (items.length >= CONTENT_LIMIT) {
        truncated = true;
        return;
      }
      const path = pathFrom(instance, child);
      if (child.type === 'TEXT') items.push({ path, text: child.characters });
      if (child.type === 'INSTANCE') {
        const main = await child.getMainComponentAsync();
        items.push({
          path,
          component: main ? ownerOf(main).name : child.name,
          props: await propValues(shownProps(child), ctx),
        });
      }
      await visit(child);
    }
  };
  await visit(instance);
  return { items, truncated };
}

/**
 * Props without the instance swaps whose layer is hidden here: Avatar `type=initials` still reports `icon`. Only for
 * `content` (what the instance shows); mapped instances keep every prop, the mappings read them.
 */
function shownProps(instance: InstanceNode): ComponentProperties {
  const shown = new Set<string>();
  const visit = (node: SceneNode): void => {
    if (!node.visible) return;
    const swap = 'componentPropertyReferences' in node ? node.componentPropertyReferences?.mainComponent : undefined;
    if (swap) shown.add(swap);
    if ('children' in node) node.children.forEach(visit);
  };
  instance.children.forEach(visit);
  return Object.fromEntries(
    Object.entries(instance.componentProperties).filter(([key, prop]) => prop.type !== 'INSTANCE_SWAP' || shown.has(key)),
  );
}

/** Layer-name path from `root` (exclusive) down to `node`, e.g. `field/leadingIcon`. */
function pathFrom(root: BaseNode, node: BaseNode): string {
  const names: string[] = [];
  let current: BaseNode | null = node;
  while (current && current.id !== root.id) {
    names.unshift(current.name);
    current = current.parent;
  }
  return names.join('/');
}

/** Nearest instance strictly above `node`, up to and including `root`. */
function instanceAbove(node: BaseNode, root: InstanceNode): InstanceNode | undefined {
  let current = node.parent;
  while (current) {
    if (current.type === 'INSTANCE') return current;
    if (current.id === root.id) return undefined;
    current = current.parent;
  }
  return undefined;
}

/**
 * Whether an overridden field is already captured by the IR as a prop value: the layer is bound to a property of
 * `root` or of one of its exposed instances (`recorded`). Text or visibility changed on an unbound layer, or inside
 * a nested instance that is not exposed, is not, and must be kept as an override.
 */
function capturedAsProp(target: BaseNode, field: string, root: InstanceNode, recorded: Set<string>): boolean {
  if (target.id === root.id) return field === 'componentProperties' || field === 'visible';
  if (field === 'componentProperties') return recorded.has(target.id);
  if (!PROP_FIELDS.has(field)) return false;
  const refs = 'componentPropertyReferences' in target ? target.componentPropertyReferences : null;
  if (!refs?.[field as keyof typeof refs]) return false;
  const owner = instanceAbove(target, root);
  return owner !== undefined && recorded.has(owner.id);
}

async function overrideValues(node: BaseNode, fields: string[], ctx: Ctx): Promise<Override['values']> {
  const values: NonNullable<Override['values']> = {};
  if (fields.includes('fills') && 'fills' in node) values.fills = await readPaints(node.fills, ctx);
  if (fields.includes('strokes') && 'strokes' in node) values.strokes = await readPaints(node.strokes, ctx);
  if (fields.includes('opacity') && 'opacity' in node) values.opacity = round(node.opacity);
  if (fields.includes('characters') && node.type === 'TEXT') values.characters = node.characters;
  if (fields.includes('visible') && 'visible' in node) values.visible = node.visible;
  if (node.type === 'INSTANCE' && (fields.includes('mainComponent') || fields.includes('componentProperties'))) {
    const main = await node.getMainComponentAsync();
    if (main) values.component = swapValue(main, ctx);
    values.props = await propValues(node.componentProperties, ctx);
  }
  return Object.keys(values).length ? values : undefined;
}

function swapValue(component: ComponentNode, ctx: Ctx): SwapValue {
  const owner = ownerOf(component);
  return {
    componentKey: ctx.componentRef(owner),
    mainComponentKey: component.key,
    componentName: owner.name,
    ...(component.variantProperties ? { variant: { ...component.variantProperties } } : {}),
  };
}

async function propValues(properties: ComponentProperties, ctx: Ctx): Promise<Record<string, PropValue>> {
  const out: Record<string, PropValue> = {};
  for (const [raw, prop] of Object.entries(properties)) {
    const name = propName(raw);
    if (prop.type === 'INSTANCE_SWAP' && typeof prop.value === 'string') {
      const swapped = await figma.getNodeByIdAsync(prop.value);
      if (swapped?.type === 'COMPONENT') {
        out[name] = swapValue(swapped, ctx);
        continue;
      }
    }
    out[name] = prop.value;
  }
  return out;
}

/** Exposed instances at every depth: an exposed instance can expose its own nested instances (`1. Flag`). */
function exposedInstances(node: InstanceNode, seen = new Set<string>()): InstanceNode[] {
  const out: InstanceNode[] = [];
  for (const exposed of node.exposedInstances) {
    if (seen.has(exposed.id)) continue;
    seen.add(exposed.id);
    out.push(exposed, ...exposedInstances(exposed, seen));
  }
  return out;
}

async function instanceInfo(node: InstanceNode, ctx: Ctx): Promise<{ info: InstanceInfo; fidelity: IRNode['fidelity'] }> {
  const main = await node.getMainComponentAsync();
  if (!main) {
    ctx.issue(node, 'detached-instance', 'instância sem componente principal (removido ou inacessível)');
    return {
      info: { componentKey: '', componentName: node.name, remote: false, props: {}, exposed: [], overrides: [] },
      fidelity: 'unresolved',
    };
  }
  const owner = ownerOf(main);
  const info: InstanceInfo = {
    componentKey: ctx.componentRef(owner),
    mainComponentKey: main.key,
    componentName: owner.name,
    remote: main.remote,
    props: await propValues(node.componentProperties, ctx),
    exposed: [],
    ...(node.isExposedInstance ? { exposedInstance: true as const } : {}),
    overrides: [],
  };

  if (ctx.options.kind !== 'library' && !(await ctx.fromLibrary(owner))) {
    ctx.dependencies.set(owner.id, owner);
  }

  if (node.name !== owner.name && node.name !== main.name) {
    ctx.issue(node, 'renamed-instance', `instância renomeada; componente "${owner.name}"`);
  }

  const exposedAll = exposedInstances(node);
  for (const exposed of exposedAll) {
    const exposedMain = await exposed.getMainComponentAsync();
    if (!exposedMain) continue;
    const exposedOwner = ownerOf(exposedMain);
    const entry: ExposedInstance = {
      path: pathFrom(node, exposed),
      componentKey: ctx.componentRef(exposedOwner),
      mainComponentKey: exposedMain.key,
      componentName: exposedOwner.name,
      props: await propValues(exposed.componentProperties, ctx),
    };
    info.exposed.push(entry);
  }

  // Nested instances can report the same override more than once; keep one per layer id and field set.
  const recorded = new Set([node.id, ...exposedAll.map((e) => e.id)]);
  const seen = new Set<string>();
  for (const override of node.overrides) {
    const target = override.id === node.id ? node : await figma.getNodeByIdAsync(override.id);
    const fields = override.overriddenFields
      .filter((f) => !IGNORED_OVERRIDES.has(f) && !(target && capturedAsProp(target, f, node, recorded)))
      .sort();
    if (!fields.length) continue;
    const path = target ? pathFrom(node, target) || '.' : override.id;
    const key = `${override.id}|${fields.join(',')}`;
    if (seen.has(key)) continue;
    seen.add(key);
    const values = target ? await overrideValues(target, fields, ctx) : undefined;
    info.overrides.push({ id: target?.id ?? override.id, node: path, fields, ...(values ? { values } : {}) });
    if (fields.some((f) => STYLE_OVERRIDES.has(f))) {
      ctx.issue(node, 'style-override', `estilo sobrescrito fora das props do componente em "${path}" (${fields.join(', ')})`);
    }
  }

  return { info, fidelity: 'exact' };
}
