import { extract, plan, type ExtractResult } from '../extractor/extract';
import type { IR, Kind } from '../extractor/ir';
import type { Summary, ToPlugin, ToUi } from './messages';

figma.showUI(__html__, { width: 400, height: 660, themeColors: true });

const post = (message: ToUi) => figma.ui.postMessage(message);
let forced: Kind | null = null;

function describeSelection() {
  const p = plan(figma.currentPage.selection, forced ?? undefined);
  const roots =
    p.kind === 'library'
      ? [`página "${figma.currentPage.name}"`]
      : p.kind === 'component'
        ? p.components.map((c) => c.name)
        : p.frames.map((f) => f.name);
  post({ type: 'plan', kind: p.kind, forced, roots, page: figma.currentPage.name, ...(p.warning ? { warning: p.warning } : {}) });
}

function summarize(ir: IR): Summary {
  return {
    kind: ir.kind,
    components: ir.components.length,
    screens: ir.screens.length,
    states: ir.screens.reduce((n, s) => n + s.states.length, 0),
    edges: ir.flow?.edges.length ?? 0,
    tokens: Object.keys(ir.tokens).length,
    componentRefs: Object.keys(ir.componentRefs).length,
  };
}

const run = (images: boolean, notes = ''): Promise<ExtractResult> =>
  extract({
    via: 'plugin',
    nodes: figma.currentPage.selection,
    kind: forced ?? undefined,
    notes: notes.trim() || undefined,
    images,
    svg: true,
  });

async function exportImages(result: ExtractResult) {
  for (const [index, request] of result.images.entries()) {
    post({ type: 'busy', label: `Exportando imagens ${index + 1}/${result.images.length}…` });
    const node = await figma.getNodeByIdAsync(request.nodeId);
    if (!node || !('exportAsync' in node)) throw new Error(`Não foi possível exportar a imagem de ${request.nodeId}.`);
    const bytes = await node.exportAsync({ format: 'PNG', constraint: { type: 'SCALE', value: 2 } });
    post({ type: 'export-file', path: request.path, bytes });
  }
}

function zipName(ir: IR) {
  const base = ir.kind === 'library' ? ir.source.fileName : (ir.screens[0]?.name ?? ir.components[0]?.name ?? ir.kind);
  return `figma2dart-${ir.kind}-${base}`.replace(/[^\w-]+/g, '_').toLowerCase() + '.zip';
}

figma.ui.onmessage = async (message: ToPlugin) => {
  try {
    switch (message.type) {
      case 'kind':
        forced = message.kind;
        describeSelection();
        break;
      case 'check': {
        post({ type: 'busy', label: 'Verificando…' });
        const { ir } = await run(false);
        post({ type: 'checked', summary: summarize(ir), lint: ir.lint });
        break;
      }
      case 'copy': {
        post({ type: 'busy', label: 'Gerando JSON…' });
        const { ir } = await run(false, message.notes);
        post({ type: 'json', summary: summarize(ir), lint: ir.lint, json: JSON.stringify(ir, null, 2) });
        break;
      }
      case 'export': {
        post({ type: 'busy', label: 'Extraindo…' });
        const result = await run(message.images, message.notes);
        post({
          type: 'export-started',
          summary: summarize(result.ir),
          lint: result.ir.lint,
          json: JSON.stringify(result.ir, null, 2),
          fileName: zipName(result.ir),
        });
        if (message.images) await exportImages(result);
        post({ type: 'exported' });
        break;
      }
      case 'select': {
        const node = await figma.getNodeByIdAsync(message.nodeId);
        // Only moves the viewport: changing the selection would change what is being exported.
        if (node && node.type !== 'DOCUMENT' && node.type !== 'PAGE') figma.viewport.scrollAndZoomIntoView([node as SceneNode]);
        break;
      }
    }
  } catch (error) {
    post({ type: 'error', message: error instanceof Error ? error.message : String(error) });
  }
};

figma.on('selectionchange', describeSelection);
figma.on('currentpagechange', describeSelection);
describeSelection();
