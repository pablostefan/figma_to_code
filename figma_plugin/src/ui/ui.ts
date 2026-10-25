import { strToU8, Zip, ZipPassThrough } from 'fflate';
import type { Kind, LintIssue, LintRule } from '../extractor/ir';
import type { Summary, ToPlugin, ToUi } from '../plugin/messages';

const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T;
const send = (message: ToPlugin) => parent.postMessage({ pluginMessage: message }, '*');

const KIND_LABEL: Record<Kind, string> = {
  component: 'Componente',
  screen: 'Tela',
  flow: 'Fluxo',
  library: 'Biblioteca',
};

const RULE_LABEL: Record<LintRule, string> = {
  'raw-color': 'Cor sem variável nem estilo',
  'raw-spacing': 'Espaçamento sem variável',
  'raw-radius': 'Raio sem variável',
  'text-without-style': 'Texto sem text style',
  'renamed-instance': 'Instância renomeada',
  'detached-instance': 'Instância desanexada',
  'style-override': 'Estilo sobrescrito',
  'missing-code-syntax': 'Variável sem code syntax',
  'absolute-layout': 'Sem auto layout',
  'duplicate-name': 'Nome duplicado entre bibliotecas',
};

const buttons = ['check', 'copy', 'export'].map((id) => $<HTMLButtonElement>(id));
const setBusy = (label: string | null) => {
  buttons.forEach((b) => (b.disabled = label !== null));
  $('app').setAttribute('aria-busy', String(label !== null));
  status(label ?? '', label ? 'busy' : undefined);
};
const status = (text: string, tone?: 'busy' | 'success' | 'error') => {
  const el = $('status');
  el.textContent = text;
  el.className = `status${tone ? ` ${tone}` : ''}`;
  el.setAttribute('role', tone === 'error' ? 'alert' : 'status');
};

function renderSummary(summary: Summary) {
  const stats: [string, number][] = [
    ['telas', summary.screens],
    ['estados', summary.states],
    ['navegações', summary.edges],
    ['componentes', summary.components],
    ['refs DS', summary.componentRefs],
    ['tokens', summary.tokens],
  ];
  $('stats').innerHTML = '';
  for (const [label, value] of stats) {
    const el = document.createElement('div');
    el.className = 'stat';
    el.innerHTML = `<b>${value}</b><span class="muted"></span>`;
    el.querySelector('span')!.textContent = label;
    $('stats').append(el);
  }
  $('result').hidden = false;
}

function renderLint(lint: LintIssue[]) {
  const list = $('lint');
  list.innerHTML = '';
  $('lintTitle').textContent = lint.length ? `Lint — ${lint.length} ${lint.length === 1 ? 'aviso' : 'avisos'}` : 'Lint — nenhum aviso';
  $('lintHint').hidden = lint.length === 0;
  for (const issue of lint) {
    const li = document.createElement('li');
    const locatable = issue.locatable !== false;
    if (locatable) {
      li.tabIndex = 0;
      li.setAttribute('role', 'button');
      li.setAttribute('aria-label', `${RULE_LABEL[issue.rule] ?? issue.rule}: ${issue.name}. Localizar camada.`);
    } else {
      li.classList.add('static');
    }
    const rule = document.createElement('span');
    rule.className = 'rule';
    rule.textContent = RULE_LABEL[issue.rule] ?? issue.rule;
    const detail = document.createElement('div');
    detail.className = 'muted';
    detail.textContent = `${issue.name} · ${issue.detail}`;
    li.append(rule, detail);
    if (locatable) {
      li.onclick = () => send({ type: 'select', nodeId: issue.node });
      li.onkeydown = (event) => {
        if (event.key === 'Enter' || event.key === ' ') {
          event.preventDefault();
          li.click();
        }
      };
    }
    list.append(li);
  }
  $('lintCard').hidden = false;
}

function download(name: string, chunks: Uint8Array[]) {
  const parts = chunks.map((chunk) => chunk as Uint8Array<ArrayBuffer>);
  const url = URL.createObjectURL(new Blob(parts, { type: 'application/zip' }));
  const a = document.createElement('a');
  a.href = url;
  a.download = name;
  a.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
}

type ExportStarted = Extract<ToUi, { type: 'export-started' }>;

let archive: Zip | null = null;

function cancelArchive() {
  archive?.terminate();
  archive = null;
}

function failArchive(error: unknown) {
  cancelArchive();
  setBusy(null);
  status(error instanceof Error ? error.message : String(error), 'error');
}

function addArchiveFile(path: string, bytes: Uint8Array) {
  if (!archive) throw new Error('A exportação não foi iniciada.');
  const file = new ZipPassThrough(path);
  archive.add(file);
  file.push(bytes, true);
}

function beginArchive(result: ExportStarted) {
  cancelArchive();
  const chunks: Uint8Array[] = [];
  const zip = new Zip((error, data, final) => {
    if (error) {
      failArchive(error);
      return;
    }
    chunks.push(data);
    if (!final) return;
    download(result.fileName, chunks);
    archive = null;
    setBusy(null);
    renderSummary(result.summary);
    renderLint(result.lint);
    status(`Arquivo exportado: ${result.fileName}`, 'success');
  });
  archive = zip;
  addArchiveFile('export.json', strToU8(result.json));
}

function copy(text: string) {
  const area = document.createElement('textarea');
  area.value = text;
  document.body.append(area);
  area.select();
  const ok = document.execCommand('copy');
  area.remove();
  return ok;
}

const notes = () => $<HTMLTextAreaElement>('notes').value;

$('check').onclick = () => send({ type: 'check' });
$('copy').onclick = () => send({ type: 'copy', notes: notes() });
$('export').onclick = () => send({ type: 'export', notes: notes(), images: $<HTMLInputElement>('images').checked });
$<HTMLSelectElement>('force').onchange = (e) => {
  const value = (e.target as HTMLSelectElement).value;
  send({ type: 'kind', kind: value ? (value as Kind) : null });
};

window.onmessage = (event: MessageEvent<{ pluginMessage?: ToUi }>) => {
  const message = event.data.pluginMessage;
  if (!message) return;
  try {
    switch (message.type) {
      case 'plan': {
        $('kind').textContent = KIND_LABEL[message.kind];
        $('page').textContent = `Página: ${message.page}`;
        $<HTMLSelectElement>('force').value = message.forced ?? '';
        const roots = $('roots');
        roots.innerHTML = '';
        for (const root of message.roots) {
          const li = document.createElement('li');
          li.textContent = root;
          li.title = root;
          roots.append(li);
        }
        const warning = $('warning');
        warning.hidden = !message.warning;
        warning.textContent = message.warning ?? '';
        break;
      }
      case 'busy':
        setBusy(message.label);
        break;
      case 'checked':
        setBusy(null);
        renderSummary(message.summary);
        renderLint(message.lint);
        status(
          message.lint.length
            ? `${message.lint.length} ${message.lint.length === 1 ? 'ponto merece' : 'pontos merecem'} atenção.`
            : 'Tudo certo para exportar.',
          message.lint.length ? undefined : 'success',
        );
        break;
      case 'json': {
        setBusy(null);
        renderSummary(message.summary);
        renderLint(message.lint);
        const copied = copy(message.json);
        status(
          copied ? 'JSON copiado para a área de transferência.' : 'Não foi possível copiar o JSON.',
          copied ? 'success' : 'error',
        );
        break;
      }
      case 'export-started':
        beginArchive(message);
        break;
      case 'export-file':
        addArchiveFile(message.path, message.bytes);
        break;
      case 'exported':
        if (!archive) throw new Error('A exportação terminou sem um arquivo ativo.');
        archive.end();
        break;
      case 'error':
        cancelArchive();
        setBusy(null);
        status(message.message, 'error');
        break;
    }
  } catch (error) {
    failArchive(error);
  }
};
