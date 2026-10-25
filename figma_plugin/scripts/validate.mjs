// Validates IR exports against schema/ir.v1.schema.json: `npm run validate -- examples/*.json`
import Ajv from 'ajv';
import { readFile } from 'node:fs/promises';

const schema = JSON.parse(await readFile('schema/ir.v1.schema.json', 'utf8'));
const validate = new Ajv({ allErrors: true, strict: false }).compile(schema);
const files = process.argv.slice(2);
if (!files.length) {
  console.error('uso: npm run validate -- <export.json> [...]');
  process.exit(2);
}
for (const file of files) {
  const ok = validate(JSON.parse(await readFile(file, 'utf8')));
  console.log(`${ok ? '✔' : '✖'} ${file}`);
  if (!ok) {
    for (const error of validate.errors.slice(0, 20)) console.log(`  ${error.instancePath || '/'} ${error.message}`);
    process.exitCode = 1;
  }
}
