const fs = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
(async () => {
  const items = await (await fetch('http://localhost:8083/api/items')).json();
  const nodes = {'#status': {}, '#reload': {}, '#items': {replaceChildren(...rows) {this.rows = rows;}}};
  const document = {querySelector: key => nodes[key], createElement: () => ({textContent: ''})};
  const context = vm.createContext({document, fetch: () => Promise.resolve({ok: true, json: async () => items})});
  vm.runInContext(fs.readFileSync('frontend/app.js', 'utf8'), context);
  await vm.runInContext('load()', context);
  assert.deepEqual(Array.from(nodes['#items'].rows, x => x.textContent), items.map(x => `${x.id}: ${x.name}`));
  assert.equal(nodes['#status'].textContent, `Получено записей: ${items.length}`);
  fs.writeFileSync('verification/frontend-test.json', JSON.stringify({passed: true, displayed: nodes['#items'].rows.map(x => x.textContent), method: 'Frontend script executed with a test DOM'}, null, 2));
  console.log('PASS: frontend renders every API record and record count');
})().catch(error => {console.error(error); process.exit(1);});
