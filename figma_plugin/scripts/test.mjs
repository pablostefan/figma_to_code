import Ajv from 'ajv';
import * as esbuild from 'esbuild';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { pathToFileURL } from 'node:url';

const directory = await mkdtemp(join(tmpdir(), 'figma2dart-tests-'));
try {
  const output = join(directory, 'run.mjs');
  await esbuild.build({
    entryPoints: ['tests/run.ts'],
    bundle: true,
    format: 'esm',
    platform: 'node',
    target: 'node22',
    outfile: output,
    logLevel: 'silent',
  });
  await import(pathToFileURL(output).href);
} finally {
  await rm(directory, { recursive: true, force: true });
}

const schema = JSON.parse(await readFile('schema/ir.v1.schema.json', 'utf8'));
const fixture = JSON.parse(await readFile('examples/component-transaction-item.ir.json', 'utf8'));
const validate = new Ajv({ strict: false }).compile(schema);
if (!validate(fixture)) throw new Error('O schema deixou de aceitar o IR 1.0 existente.');
fixture.irVersion = 'banana';
if (validate(fixture)) throw new Error('O schema aceitou uma versão de IR desconhecida.');

console.log('✔ invariantes do extrator, paginação e compatibilidade do schema');
