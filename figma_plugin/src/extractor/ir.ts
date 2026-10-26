/**
 * IR v1 — the contract between Figma exporters (plugin, MCP) and figma2dart.
 * schema/ir.v1.schema.json is generated from these types (`npm run schema`); edit here, not there.
 */

export type IRVersion = '1.0.0' | '1.1.0' | '1.2.0' | '1.3.0' | '1.4.0';

export const IR_VERSION: IRVersion = '1.4.0';
export const EXTRACTOR_VERSION = '0.5.0';

export type Kind = 'component' | 'screen' | 'flow' | 'library';
export type Fidelity = 'exact' | 'inferred' | 'unresolved';
export type Via = 'plugin' | 'mcp-extractor' | 'mcp-native';

export interface IR {
  irVersion: IRVersion;
  kind: Kind;
  source: Source;
  intent?: { notes?: string };
  /** Tokens used by the export, keyed by `Collection/name` (e.g. `Spacing/lg`). */
  tokens: Record<string, Token>;
  /** Text styles used by the export, keyed by style name (e.g. `heading/md`). */
  textStyles: Record<string, TextStyleDef>;
  /** Color styles used by the export (files that use styles instead of, or besides, variables), keyed by name. */
  paintStyles?: Record<string, PaintStyleDef>;
  /** Every component referenced by an instance or instance swap, keyed by component (set) key. */
  componentRefs: Record<string, ComponentRef>;
  /** Components exported in depth: selected/library components and local dependencies found below any exported root. */
  components: ComponentDef[];
  screens: ScreenDef[];
  flow?: FlowDef;
  lint: LintIssue[];
}

export interface Source {
  via: Via;
  extractor: string;
  /** Present via MCP. The plugin only gets it as a private organization plugin; imported as a development plugin it is absent. */
  fileKey?: string;
  /** `figma.root.name`. The MCP `use_figma` runtime reports `Document` here; rely on `fileKey` instead. */
  fileName: string;
  pageName: string;
  exportedAt: string;
}

// ---------------------------------------------------------------- tokens & styles

export interface Token {
  /** Variable name inside its collection, e.g. `text/primary`. */
  name: string;
  collection: string;
  /** Figma resolved type: COLOR, FLOAT, STRING, BOOLEAN (newer Figma versions add more). */
  type: string;
  /** Resolved value in the collection's default mode. Colors are `#RRGGBB` or `#RRGGBBAA`. */
  value: string | number | boolean;
  /** Qualified name of the token this one aliases, when it is an alias. */
  aliasOf?: string;
  /** Value per mode name (e.g. `Light`, `Dark`), when the collection has more than one mode. */
  modes?: Record<string, { value: string | number | boolean; aliasOf?: string }>;
  codeSyntax?: { WEB?: string; ANDROID?: string; iOS?: string };
  id: string;
  key: string;
  remote: boolean;
}

export interface TextStyleDef {
  name: string;
  fontFamily: string;
  fontStyle: string;
  fontSize: number;
  lineHeight: number | 'auto' | { percent: number };
  letterSpacing: number | { percent: number };
  id: string;
  key: string;
  remote: boolean;
}

export interface PaintStyleDef {
  name: string;
  paints: Paint[];
  id: string;
  key: string;
  remote: boolean;
}

/** A value that may come from a variable. `token` is the key into `IR.tokens`. */
export interface Value<T> {
  value: T;
  token?: string;
}

// ---------------------------------------------------------------- components

export type PropType = 'VARIANT' | 'TEXT' | 'BOOLEAN' | 'INSTANCE_SWAP' | 'SLOT';

export interface PropDef {
  type: PropType;
  default: string | boolean;
  /** VARIANT only. */
  options?: string[];
}

export interface ComponentRef {
  key: string;
  name: string;
  remote: boolean;
  description?: string;
  props: Record<string, PropDef>;
}

export interface ComponentDef {
  id: string;
  key: string;
  name: string;
  /** `exported`: part of the selection. `dependency`: local component referenced below an exported root. */
  role: 'exported' | 'dependency';
  description?: string;
  props: Record<string, PropDef>;
  variants: VariantDef[];
}

export interface VariantDef {
  id: string;
  name: string;
  /** Variant values, e.g. `{ "size": "md" }`. Empty for components without variants. */
  props: Record<string, string>;
  tree: IRNode;
  /** Path inside the export zip (plugin only). */
  image?: string;
  /** SVG markup, for vector-only components such as icons (when the environment can export it). */
  svg?: string;
}

// ---------------------------------------------------------------- screens & flow

export interface ScreenDef {
  /** Base name: the part before ` / ` in the frame name. */
  name: string;
  states: ScreenState[];
}

export interface ScreenState {
  /** Part after ` / ` in the frame name, or `default`. */
  state: string;
  id: string;
  frameName: string;
  tree: IRNode;
  image?: string;
  /** Scale of `image` (pixels per Figma unit), to crop instances from it by their `bounds`. */
  imageScale?: number;
}

export interface FlowDef {
  /** Frame id of the starting screen state. */
  start: string | null;
  edges: FlowEdge[];
}

export interface FlowEdge {
  /** Frame id of the screen state where the trigger lives. */
  from: string;
  trigger: { node: string; name: string; type: string };
  /** Destination frame id, `back`, `close`, a URL, or null when the destination was removed. */
  to: string | null;
  action: string;
  navigation?: string;
  transition?: string;
}

// ---------------------------------------------------------------- nodes

export type Sizing = 'FIXED' | 'HUG' | 'FILL';

export interface IRNode {
  id: string;
  type: string;
  name: string;
  fidelity: Fidelity;
  visible?: false;
  size: { width: number; height: number };
  /** Degrees, counterclockwise as in Figma (-180..180); only when rotated (a back chevron is often `chevron-right` at 180). */
  rotation?: number;
  /** Variables bound to the node's width/height (e.g. icon sizes), keys into `IR.tokens`. */
  sizeTokens?: { width?: string; height?: string };
  limits?: { minWidth?: Value<number>; maxWidth?: Value<number>; minHeight?: Value<number>; maxHeight?: Value<number> };
  /** Variable modes set explicitly on this node, collection name → mode name (e.g. `{ "Theme": "Dark" }`). */
  modes?: Record<string, string>;
  /** Present when the node is not placed by auto layout (free positioning or absolute). */
  position?: { x: number; y: number };
  /** Every node on a screen (1.4; only instances in 1.3): box relative to the screen frame, to crop it from the image. */
  bounds?: { x: number; y: number; width: number; height: number };
  sizing?: { horizontal: Sizing; vertical: Sizing };
  layout?: Layout;
  style?: Style;
  text?: TextInfo;
  instance?: InstanceInfo;
  /** Inside component trees: which component property drives this node. */
  bindings?: { characters?: string; visible?: string; mainComponent?: string };
  children?: IRNode[];
}

export interface Layout {
  direction: 'HORIZONTAL' | 'VERTICAL' | 'GRID';
  gap: Value<number> | 'auto';
  padding: { top: Value<number>; right: Value<number>; bottom: Value<number>; left: Value<number> };
  align: { main: string; cross: string };
  wrap: boolean;
  counterGap?: Value<number>;
  /** direction=GRID only. */
  grid?: { rows: number; columns: number; rowGap: Value<number>; columnGap: Value<number> };
}

export type Paint =
  | { type: 'SOLID'; color: Value<string>; opacity?: number }
  | { type: 'IMAGE'; scaleMode: string }
  | { type: 'GRADIENT'; kind: string; stops: { position: number; color: Value<string> }[] }
  | { type: 'OTHER'; kind: string };

export interface Style {
  fills?: Paint[];
  /** Color style applied to the fills (key into `IR.paintStyles`). */
  fillStyle?: string;
  strokes?: Paint[];
  strokeStyle?: string;
  strokeWeight?: Value<number> | { top: Value<number>; right: Value<number>; bottom: Value<number>; left: Value<number> };
  strokeAlign?: string;
  radius?: Value<number> | { topLeft: Value<number>; topRight: Value<number>; bottomRight: Value<number>; bottomLeft: Value<number> };
  opacity?: number;
  effects?: Effect[];
  clipsContent?: boolean;
}

export interface Effect {
  type: string;
  style?: string;
  color?: string;
  offset?: { x: number; y: number };
  radius?: number;
  spread?: number;
}

export interface TextInfo {
  characters: string;
  /** Text style name (key into `IR.textStyles`), when the whole text uses one style. */
  style?: string;
  /** Raw font, when there is no text style. */
  font?: { family: string; style: string; size: number };
  color?: Value<string>;
  /** Color style of the text (key into `IR.paintStyles`). */
  colorStyle?: string;
  align?: string;
  /** Line limit set in Figma (`maxLines`). */
  maxLines?: number;
  /** `ENDING`: text cut with an ellipsis when it does not fit. */
  truncation?: 'ENDING';
  /**
   * How the text box grows, when not the default `WIDTH_AND_HEIGHT` (one line, grows sideways): `HEIGHT` wraps at a
   * fixed width, `NONE` is a fixed box, `TRUNCATE` cuts at the box.
   */
  autoResize?: string;
  /** Present when the text mixes styles or colors. */
  segments?: { characters: string; style?: string; color?: Value<string>; colorStyle?: string }[];
}

export type PropValue = string | boolean | SwapValue;

/** INSTANCE_SWAP value: the swapped-in component. */
export interface SwapValue {
  componentKey: string;
  /**
   * Key of the exact main component: the variant inside a set, or the component itself when it has no variants.
   * Finds a mapping that targets one variant (e.g. each icon of an `Icon` set). Absent in IR 1.0.
   */
  mainComponentKey?: string;
  componentName: string;
  /** Variant values of the swapped-in component, e.g. `{ "name": "lock" }` for an Icon. */
  variant?: Record<string, string>;
}

export interface InstanceInfo {
  /** Key of the component set (or of the component, when it has no variants). Key into `IR.componentRefs`. */
  componentKey: string;
  /**
   * Key of the exact main component: the variant inside a set, or the component itself when it has no variants.
   * Finds a mapping that targets one variant (e.g. each icon of an `Icon` set). Absent in IR 1.0.
   */
  mainComponentKey?: string;
  componentName: string;
  remote: boolean;
  /** Component property values on this instance, names without the `#id` suffix. */
  props: Record<string, PropValue>;
  /** Nested instances exposed through this instance ("expose nested instances"), at any depth. */
  exposed: ExposedInstance[];
  /**
   * Instances on a screen: what is inside, as shown (texts and nested instances, visible only), so a generator can
   * assemble a component whose content is not in its props (lists, templates). Capped at `CONTENT_LIMIT` items.
   */
  content?: InstanceContent[];
  /** `content` stopped at the limit. */
  contentTruncated?: true;
  /**
   * Customizations beyond what this IR already records as props: style changes, and text, visibility or nested
   * instances changed directly on a layer that is not driven by a recorded component property.
   */
  overrides: Override[];
}

export interface InstanceContent {
  /** Layer path inside the instance. */
  path: string;
  /** TEXT layer: what it shows. */
  text?: string;
  /** Nested instance: its component (set) name and props. */
  component?: string;
  props?: Record<string, PropValue>;
}

export interface Override {
  /** Stable Figma layer id. Added in IR 1.2; old exports only contain `node`. */
  id?: string;
  /** Layer path inside the instance; `.` is the instance itself. */
  node: string;
  fields: string[];
  /** New values of the overridden fields, so the generator can reproduce the customization. */
  values?: {
    fills?: Paint[];
    strokes?: Paint[];
    opacity?: number;
    characters?: string;
    visible?: boolean;
    /** Nested instance: the component it shows (after a swap) and its props. */
    component?: SwapValue;
    props?: Record<string, PropValue>;
  };
}

export interface ExposedInstance {
  /** Layer name path inside the instance, e.g. `trailing/Badge` or `.Nested / Global Switcher/1. Flag`. */
  path: string;
  componentKey: string;
  /**
   * Key of the exact main component: the variant inside a set, or the component itself when it has no variants.
   * Finds a mapping that targets one variant (e.g. each icon of an `Icon` set). Absent in IR 1.0.
   */
  mainComponentKey?: string;
  componentName: string;
  props: Record<string, PropValue>;
}

// ---------------------------------------------------------------- lint

export type LintRule =
  | 'raw-color'
  | 'raw-spacing'
  | 'raw-radius'
  | 'text-without-style'
  | 'renamed-instance'
  | 'detached-instance'
  | 'style-override'
  | 'missing-code-syntax'
  | 'absolute-layout'
  | 'duplicate-name';

export interface LintIssue {
  node: string;
  name: string;
  rule: LintRule;
  detail: string;
  /** False for variables and styles, which cannot be focused on the canvas. Added in IR 1.2. */
  locatable?: boolean;
}
