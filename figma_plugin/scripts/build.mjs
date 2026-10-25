// Builds the three outputs from the same sources:
//   dist/code.js           plugin main thread
//   dist/ui.html           plugin UI, with its script inlined (Figma loads a single HTML file)
//   dist/mcp-extractor.js  the extractor for the MCP `use_figma` tool (`var F2D`), must fit its 50 000-char limit
import * as esbuild from 'esbuild';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const watch = process.argv.includes('--watch');
const MCP_LIMIT = 50_000;
// Room left for the call appended by the caller: `return await F2D.run({ nodeIds: [...] });`
const MCP_CALL_BUDGET = 2_000;

await mkdir('dist', { recursive: true });

const common = { bundle: true, target: 'es2017', logLevel: 'info' };

const inlineUi = {
  name: 'inline-ui',
  setup(build) {
    build.onEnd(async (result) => {
      if (result.errors.length) return;
      const js = result.outputFiles[0].text.replace(/<\/script/gi, '<\\/script');
      const html = await readFile('src/ui/ui.html', 'utf8');
      await writeFile('dist/ui.html', html.replace('<!-- SCRIPT -->', `<script>${js}</script>`));
    });
  },
};

const checkMcpSize = {
  name: 'check-mcp-size',
  setup(build) {
    build.onEnd(async (result) => {
      if (result.errors.length) return;
      const size = (await readFile('dist/mcp-extractor.js', 'utf8')).length;
      const max = MCP_LIMIT - MCP_CALL_BUDGET;
      const message = `mcp-extractor.js: ${size} chars (máximo ${max})`;
      if (size > max) {
        console.error(`✖ ${message}`);
        if (!watch) process.exitCode = 1;
      } else {
        console.log(`✔ ${message}`);
      }
    });
  },
};

const configs = [
  { ...common, entryPoints: ['src/plugin/main.ts'], outfile: 'dist/code.js', format: 'iife' },
  { ...common, entryPoints: ['src/ui/ui.ts'], write: false, outfile: 'dist/ui.js', format: 'iife', minify: !watch, plugins: [inlineUi] },
  {
    ...common,
    entryPoints: ['src/mcp/entry.ts'],
    outfile: 'dist/mcp-extractor.js',
    format: 'iife',
    // use_figma runs modern JS; es2020 avoids down-level helpers and keeps the bundle small.
    target: 'es2020',
    globalName: 'F2D',
    minify: true,
    legalComments: 'none',
    plugins: [checkMcpSize],
  },
];

if (watch) {
  for (const config of configs) await (await esbuild.context(config)).watch();
} else {
  await Promise.all(configs.map((config) => esbuild.build(config)));
}
