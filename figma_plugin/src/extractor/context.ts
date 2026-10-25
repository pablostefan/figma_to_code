import type {
  ComponentRef,
  Kind,
  LintIssue,
  LintRule,
  Paint,
  PaintStyleDef,
  PropDef,
  PropType,
  TextStyleDef,
  Token,
  Value,
  Via,
} from './ir';

export type ComponentOwner = ComponentSetNode | ComponentNode;

export interface ImageRequest {
  nodeId: string;
  path: string;
}

export interface ContextOptions {
  via: Via;
  kind: Kind;
  /** Queue image exports (plugin). MCP gets images from `get_screenshot` instead. */
  images: boolean;
  /** Try to export SVG markup for vector-only components. */
  svg: boolean;
}

export const round = (n: number) => Math.round(n * 100) / 100;

/** `label#4:0` → `label`. Variant property names carry no suffix. */
export const propName = (raw: string) => raw.replace(/#\d+:\d+$/, '');

/** The node that owns component properties: the set for a variant, the component otherwise. */
export function ownerOf(component: ComponentNode): ComponentOwner {
  return component.parent?.type === 'COMPONENT_SET' ? component.parent : component;
}

export function hex(color: RGB | RGBA, opacity = 1): string {
  const to = (v: number) =>
    Math.round(Math.min(1, Math.max(0, v)) * 255)
      .toString(16)
      .padStart(2, '0')
      .toUpperCase();
  const a = ('a' in color ? color.a : 1) * opacity;
  return `#${to(color.r)}${to(color.g)}${to(color.b)}${a < 1 ? to(a) : ''}`;
}

const VECTOR_TYPES = new Set(['VECTOR', 'BOOLEAN_OPERATION', 'ELLIPSE', 'LINE', 'STAR', 'POLYGON', 'RECTANGLE']);

/** Icons and illustrations: every leaf is a vector shape. */
export function isVectorOnly(node: SceneNode): boolean {
  if (!('findAll' in node)) return false;
  const leaves = node.findAll((n) => !('children' in n));
  return leaves.length > 0 && leaves.every((n) => VECTOR_TYPES.has(n.type));
}

const isAlias = (v: VariableValue): v is VariableAlias =>
  typeof v === 'object' && v !== null && 'type' in v && v.type === 'VARIABLE_ALIAS';

/** Shared state of one extraction: everything referenced, deduplicated, plus lint and image requests. */
export class Ctx {
  readonly tokens: Record<string, Token> = {};
  readonly textStyles: Record<string, TextStyleDef> = {};
  readonly paintStyles: Record<string, PaintStyleDef> = {};
  readonly componentRefs: Record<string, ComponentRef> = {};
  readonly lint: LintIssue[] = [];
  readonly images: ImageRequest[] = [];
  /** Local components found while serializing screens, to be exported in depth. */
  readonly dependencies = new Map<string, ComponentOwner>();

  private readonly variableNames = new Map<string, string | undefined>();
  /** Token names already taken, reserved before aliases resolve (an alias can share its target's name). */
  private readonly tokenNames = new Set<string>();
  private readonly collections = new Map<string, Promise<VariableCollection | null>>();
  private readonly styleNames = new Map<string, string | undefined>();
  private readonly libraryComponents = new Map<string, boolean>();
  private readonly missingCodeSyntax: { id: string; name: string }[] = [];

  constructor(readonly options: ContextOptions) {}

  issue(node: BaseNode | { id: string; name: string }, rule: LintRule, detail: string, locatable = true): void {
    this.lint.push({ node: node.id, name: node.name, rule, detail, ...(locatable ? {} : { locatable: false }) });
  }

  image(node: SceneNode, folder: string): string | undefined {
    if (!this.options.images) return undefined;
    const slug = node.name
      .normalize('NFD')
      .replace(/[̀-ͯ]/g, '')
      .replace(/[^\w=,-]+/g, '_')
      .replace(/^_+|_+$/g, '');
    const path = `images/${folder}/${slug || 'node'}--${node.id.replace(/[:;]/g, '-')}.png`;
    this.images.push({ nodeId: node.id, path });
    return path;
  }

  /** Issues about the extraction as a whole; call once, after serializing everything. */
  finish(): void {
    const missing = this.missingCodeSyntax;
    if (!missing.length) return;
    const sample = missing.slice(0, 5).map((v) => v.name).join(', ');
    const detail = missing.length === 1 ? 'variável sem code syntax WEB' : `${missing.length} variáveis sem code syntax WEB (${sample}${missing.length > 5 ? ', …' : ''})`;
    this.issue(missing[0], 'missing-code-syntax', detail, false);
  }

  // ------------------------------------------------------------ variables

  private collection(id: string): Promise<VariableCollection | null> {
    let collection = this.collections.get(id);
    if (!collection) {
      collection = figma.variables.getVariableCollectionByIdAsync(id);
      this.collections.set(id, collection);
    }
    return collection;
  }

  /** Registers a variable (and what it aliases) and returns its qualified name, e.g. `Spacing/lg`. */
  async variable(id: string): Promise<string | undefined> {
    if (this.variableNames.has(id)) return this.variableNames.get(id);
    this.variableNames.set(id, undefined); // guards alias cycles
    const variable = await figma.variables.getVariableByIdAsync(id);
    if (!variable) return undefined;
    const collection = await this.collection(variable.variableCollectionId);
    const collectionName = collection?.name ?? 'Unknown';
    let qualified = `${collectionName}/${variable.name}`;
    // Two libraries (e.g. core and brand) can share collection and variable names: keep both, told apart by key.
    if (this.tokenNames.has(qualified)) {
      qualified = `${qualified}#${variable.key.slice(0, 8)}`;
      this.issue(
        { id: variable.id, name: qualified },
        'duplicate-name',
        `outra variável já usa o nome "${collectionName}/${variable.name}"`,
        false,
      );
    }
    this.tokenNames.add(qualified);
    this.variableNames.set(id, qualified);

    const resolve = async (raw: VariableValue) => {
      const aliasOf = isAlias(raw) ? await this.variable(raw.id) : undefined;
      const value = aliasOf ? (this.tokens[aliasOf]?.value ?? '') : this.convert(raw, variable.resolvedType);
      return aliasOf ? { value, aliasOf } : { value };
    };
    const defaultMode = collection?.defaultModeId ?? Object.keys(variable.valuesByMode)[0];
    const { value, aliasOf } = await resolve(variable.valuesByMode[defaultMode]);
    let modes: Token['modes'];
    if (collection && collection.modes.length > 1) {
      modes = {};
      for (const mode of collection.modes) {
        if (mode.modeId in variable.valuesByMode) modes[mode.name] = await resolve(variable.valuesByMode[mode.modeId]);
      }
    }
    const codeSyntax = Object.keys(variable.codeSyntax).length ? { ...variable.codeSyntax } : undefined;
    this.tokens[qualified] = {
      name: variable.name,
      collection: collectionName,
      type: variable.resolvedType,
      value,
      ...(aliasOf ? { aliasOf } : {}),
      ...(modes ? { modes } : {}),
      ...(codeSyntax ? { codeSyntax } : {}),
      id: variable.id,
      key: variable.key,
      remote: variable.remote,
    };
    if (!codeSyntax?.WEB && variable.scopes.length > 0) this.missingCodeSyntax.push({ id: variable.id, name: qualified });
    return qualified;
  }

  /** `explicitVariableModes` (collection id → mode id) as collection name → mode name. */
  async modes(explicit: Record<string, string>): Promise<Record<string, string> | undefined> {
    const out: Record<string, string> = {};
    for (const [collectionId, modeId] of Object.entries(explicit)) {
      const collection = await this.collection(collectionId);
      out[collection?.name ?? collectionId] = collection?.modes.find((m) => m.modeId === modeId)?.name ?? modeId;
    }
    return Object.keys(out).length ? out : undefined;
  }

  private convert(raw: VariableValue, type: VariableResolvedDataType): Token['value'] {
    if (type === 'COLOR' && typeof raw === 'object' && raw !== null && 'r' in raw) return hex(raw);
    if (typeof raw === 'number') return round(raw);
    if (typeof raw === 'string' || typeof raw === 'boolean') return raw;
    return String(raw);
  }

  /** Wraps a raw value with the token bound to it, if any. */
  async value<T>(value: T, alias: VariableAlias | undefined): Promise<Value<T>> {
    const token = alias ? await this.variable(alias.id) : undefined;
    return token ? { value, token } : { value };
  }

  // ------------------------------------------------------------ styles

  /** Style name, suffixed with its key when another style of the same kind already took the name. */
  private styleName(taken: Record<string, unknown>, style: BaseStyle): string {
    if (!(style.name in taken)) return style.name;
    const name = `${style.name}#${style.key.slice(0, 8)}`;
    this.issue({ id: style.id, name }, 'duplicate-name', `outro estilo já usa o nome "${style.name}"`, false);
    return name;
  }

  async paintStyle(id: string | PluginAPI['mixed']): Promise<string | undefined> {
    if (typeof id !== 'string' || !id) return undefined;
    if (this.styleNames.has(id)) return this.styleNames.get(id);
    const style = await figma.getStyleByIdAsync(id);
    if (!style || style.type !== 'PAINT') {
      this.styleNames.set(id, undefined);
      return undefined;
    }
    const name = this.styleName(this.paintStyles, style);
    this.styleNames.set(id, name);
    this.paintStyles[name] = {
      name,
      paints: await readPaints((style as PaintStyle).paints, this),
      id: style.id,
      key: style.key,
      remote: style.remote,
    };
    return name;
  }

  async textStyle(id: string): Promise<string | undefined> {
    if (!id) return undefined;
    if (this.styleNames.has(id)) return this.styleNames.get(id);
    const style = await figma.getStyleByIdAsync(id);
    if (!style || style.type !== 'TEXT') {
      this.styleNames.set(id, undefined);
      return undefined;
    }
    const name = this.styleName(this.textStyles, style);
    const lineHeight: TextStyleDef['lineHeight'] =
      style.lineHeight.unit === 'AUTO'
        ? 'auto'
        : style.lineHeight.unit === 'PERCENT'
          ? { percent: round(style.lineHeight.value) }
          : round(style.lineHeight.value);
    this.textStyles[name] = {
      name,
      fontFamily: style.fontName.family,
      fontStyle: style.fontName.style,
      fontSize: style.fontSize,
      lineHeight,
      letterSpacing:
        style.letterSpacing.unit === 'PERCENT'
          ? { percent: round(style.letterSpacing.value) }
          : round(style.letterSpacing.value),
      id: style.id,
      key: style.key,
      remote: style.remote,
    };
    this.styleNames.set(id, name);
    return name;
  }

  async effectStyle(id: string): Promise<string | undefined> {
    if (!id) return undefined;
    const style = await figma.getStyleByIdAsync(id);
    return style?.name;
  }

  // ------------------------------------------------------------ components

  /** Registers a component (set) in `componentRefs` and returns its key. */
  componentRef(owner: ComponentOwner): string {
    const key = owner.key;
    if (!this.componentRefs[key]) {
      this.componentRefs[key] = {
        key,
        name: owner.name,
        remote: owner.remote,
        ...(owner.description ? { description: owner.description } : {}),
        props: propDefs(owner),
      };
    }
    return key;
  }

  /**
   * Whether instances of `owner` are library components (remote, or published from this file) rather than
   * components of this file only. Decides depth: library components stay shallow, file components are exported.
   */
  async fromLibrary(owner: ComponentOwner): Promise<boolean> {
    if (owner.remote) return true;
    let library = this.libraryComponents.get(owner.id);
    if (library === undefined) {
      try {
        library = (await owner.getPublishStatusAsync()) !== 'UNPUBLISHED';
      } catch {
        library = false;
      }
      this.libraryComponents.set(owner.id, library);
    }
    return library;
  }
}

export async function readPaints(paints: readonly globalThis.Paint[] | PluginAPI['mixed'], ctx: Ctx): Promise<Paint[]> {
  if (!Array.isArray(paints)) return [];
  const out: Paint[] = [];
  for (const paint of paints as readonly globalThis.Paint[]) {
    if (paint.visible === false) continue;
    switch (paint.type) {
      case 'SOLID': {
        const color = await ctx.value(hex(paint.color), paint.boundVariables?.color);
        out.push(paint.opacity !== undefined && paint.opacity < 1 ? { type: 'SOLID', color, opacity: round(paint.opacity) } : { type: 'SOLID', color });
        break;
      }
      case 'IMAGE':
        out.push({ type: 'IMAGE', scaleMode: paint.scaleMode });
        break;
      case 'GRADIENT_LINEAR':
      case 'GRADIENT_RADIAL':
      case 'GRADIENT_ANGULAR':
      case 'GRADIENT_DIAMOND': {
        const stops = [];
        for (const stop of paint.gradientStops) {
          stops.push({ position: round(stop.position), color: await ctx.value(hex(stop.color), stop.boundVariables?.color) });
        }
        out.push({ type: 'GRADIENT', kind: paint.type, stops });
        break;
      }
      default:
        out.push({ type: 'OTHER', kind: paint.type });
    }
  }
  return out;
}

export function propDefs(owner: ComponentOwner): Record<string, PropDef> {
  const result: Record<string, PropDef> = {};
  let definitions: ComponentPropertyDefinitions;
  try {
    definitions = owner.componentPropertyDefinitions;
  } catch {
    return result;
  }
  for (const [raw, def] of Object.entries(definitions)) {
    result[propName(raw)] = {
      type: def.type as PropType,
      default: def.defaultValue,
      ...(def.variantOptions ? { options: [...def.variantOptions] } : {}),
    };
  }
  return result;
}
