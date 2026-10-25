import type { Kind, LintIssue } from '../extractor/ir';

export interface Summary {
  kind: Kind;
  components: number;
  screens: number;
  states: number;
  edges: number;
  tokens: number;
  componentRefs: number;
}

/** UI → plugin */
export type ToPlugin =
  | { type: 'kind'; kind: Kind | null }
  | { type: 'check' }
  | { type: 'export'; notes: string; images: boolean }
  | { type: 'copy'; notes: string }
  | { type: 'select'; nodeId: string };

/** Plugin → UI */
export type ToUi =
  | { type: 'plan'; kind: Kind; forced: Kind | null; roots: string[]; page: string; warning?: string }
  | { type: 'busy'; label: string }
  | { type: 'checked'; summary: Summary; lint: LintIssue[] }
  | { type: 'export-started'; summary: Summary; lint: LintIssue[]; json: string; fileName: string }
  | { type: 'export-file'; path: string; bytes: Uint8Array }
  | { type: 'exported' }
  | { type: 'json'; summary: Summary; lint: LintIssue[]; json: string }
  | { type: 'error'; message: string };
