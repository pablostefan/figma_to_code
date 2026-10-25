/**
 * Entry point for the Figma MCP `use_figma` tool. Bundled to dist/mcp-extractor.js as `var F2D = …`;
 * the caller appends a line such as:
 *
 *   return await F2D.run({ nodeIds: ['7:197'] });
 *
 * Same extractor as the plugin, so the IR is identical except for `source.via` and the absence of images
 * (use the `get_screenshot` tool for those).
 *
 * `use_figma` rejects return values above 48 000 bytes. When the IR is larger, `run` returns the first page
 * of its JSON: `{ page: 0, pages: N, exportedAt, data }`. Call again with `page: 1…N-1` and the same
 * `exportedAt`, then concatenate `data` in order and `JSON.parse` the result.
 */
import { extract } from '../extractor/extract';
import type { IR, Kind } from '../extractor/ir';

export interface McpOptions {
  /** Nodes to export. Empty or omitted = library export of `pageId` (or the first page). */
  nodeIds?: string[];
  pageId?: string;
  kind?: Kind;
  notes?: string;
  /** Page of a paged result to return. */
  page?: number;
  /** Timestamp returned by page 0; pass it back so every page comes from an identical IR. */
  exportedAt?: string;
}

export interface McpPage {
  page: number;
  pages: number;
  exportedAt: string;
  data: string;
}

/** Budget for `data` once JSON-escaped, leaving room for the wrapper object. */
const PAGE_BYTES = 46_000;

/** Bytes a char adds to the escaped JSON string (`"` and `\` double, controls become `\uXXXX`). */
function escapedBytes(code: number): number {
  if (code === 0x22 || code === 0x5c) return 2;
  if (code < 0x20) return 6;
  if (code < 0x80) return 1;
  if (code < 0x800) return 2;
  return 3;
}

/** Splits `json` into slices whose escaped UTF-8 size fits `PAGE_BYTES`, never inside a surrogate pair. */
export function paginate(json: string): string[] {
  const pages: string[] = [];
  let start = 0;
  let bytes = 0;
  for (let i = 0; i < json.length; i++) {
    const code = json.charCodeAt(i);
    const isPair = code >= 0xd800 && code <= 0xdbff && i + 1 < json.length;
    const cost = isPair ? 4 : escapedBytes(code);
    if (bytes + cost > PAGE_BYTES) {
      pages.push(json.slice(start, i));
      start = i;
      bytes = 0;
    }
    bytes += cost;
    if (isPair) i++;
  }
  pages.push(json.slice(start));
  return pages;
}

export function pageIndex(page: number | undefined, total: number): number {
  const index = page ?? 0;
  if (!Number.isInteger(index) || index < 0 || index >= total) {
    throw new Error(`Página ${index} inexistente (total ${total}).`);
  }
  return index;
}

export async function run(options: McpOptions = {}): Promise<IR | McpPage> {
  const nodes: SceneNode[] = [];
  for (const id of options.nodeIds ?? []) {
    const node = await figma.getNodeByIdAsync(id);
    if (!node || node.type === 'DOCUMENT' || node.type === 'PAGE') throw new Error(`Nó ${id} não encontrado ou não é uma camada.`);
    nodes.push(node as SceneNode);
  }
  let page: PageNode | undefined;
  if (options.pageId) {
    const node = await figma.getNodeByIdAsync(options.pageId);
    if (node?.type !== 'PAGE') throw new Error(`${options.pageId} não é uma página.`);
    page = node;
  }
  const exportedAt = options.exportedAt ?? new Date().toISOString();
  const { ir } = await extract({
    via: 'mcp-extractor',
    nodes,
    page,
    kind: options.kind,
    notes: options.notes,
    images: false,
    svg: true,
    exportedAt,
  });

  const pages = paginate(JSON.stringify(ir));
  if (pages.length === 1 && options.page === undefined) return ir;
  const index = pageIndex(options.page, pages.length);
  return { page: index, pages: pages.length, exportedAt, data: pages[index] };
}
