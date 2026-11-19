const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../tools/runtime/javascript/node_modules/jsdom');

(async function () {
    const root = path.resolve(__dirname, '..');
    const dom = new JSDOM(fs.readFileSync(path.join(root, 'tmp/settings-form.html'), 'utf8'), {
        url: 'https://redmine.example.test/admin/ai_enhancement', runScripts: 'outside-only'
    });
    const window = dom.window;
    window.eval(fs.readFileSync(path.join(root, 'assets/javascripts/settings.js'), 'utf8'));
    await new Promise(function (resolve) {
        window.document.addEventListener('DOMContentLoaded', resolve, {once: true});
    });
    const document = window.document;
    const rows = document.getElementById('ai-source-rows');
    const existing = rows.firstElementChild;
    assert.equal(existing.querySelector('.ai-folder-fields').hidden, true);
    assert.equal(existing.querySelector('.ai-database-fields').hidden, false);
    assert.equal(existing.querySelector('.ai-sample-fields').hidden, false);
    existing.querySelector('.ai-add-sample').click();
    assert.equal(existing.querySelectorAll('.ai-sample-rows > .ai-sample-row').length, 2);
    existing.querySelector('.ai-remove-sample').click();
    existing.querySelector('.ai-add-sample').click();
    const indices = Array.from(existing.querySelectorAll('.ai-sample-rows > .ai-sample-row')).map(function (row) { return row.dataset.tableIndex; });
    assert.deepEqual(indices, ['1', '2']);

    document.getElementById('ai-add-source').click();
    const added = rows.lastElementChild;
    assert.equal(added.dataset.sourceIndex, '1');
    const sourceType = added.querySelector('.ai-source-type');
    sourceType.value = 'database';
    sourceType.dispatchEvent(new window.Event('change', {bubbles: true}));
    assert.equal(added.querySelector('.ai-db-port').value, '5432');
    const databaseType = added.querySelector('.ai-db-type');
    databaseType.value = 'oracle';
    databaseType.dispatchEvent(new window.Event('change', {bubbles: true}));
    assert.equal(added.querySelector('.ai-db-port').value, '1521');
    const samples = added.querySelector('.ai-sample-enabled');
    samples.checked = true;
    samples.dispatchEvent(new window.Event('change', {bubbles: true}));
    added.querySelector('.ai-add-sample').click();
    const input = added.querySelector('.ai-sample-rows input');
    assert.equal(input.name, 'sources[1][sample_tables][0][table]');
    assert.equal(added.querySelector('.ai-sample-fields').hidden, false);
    sourceType.value = 'documents_folder';
    sourceType.dispatchEvent(new window.Event('change', {bubbles: true}));
    assert.equal(added.querySelector('.ai-folder-fields').hidden, false);
    assert.equal(added.querySelector('.ai-database-fields').hidden, true);
    existing.querySelector('.ai-remove-source').click();
    document.getElementById('ai-add-source').click();
    assert.equal(rows.lastElementChild.dataset.sourceIndex, '2');
    console.log('Dynamic settings form: 13 assertions passed.');
    window.close();
}()).catch(function (error) {
    console.error(error);
    process.exitCode = 1;
});
