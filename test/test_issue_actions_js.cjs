const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {JSDOM} = require('../tools/runtime/javascript/node_modules/jsdom');

(async function () {
    const root = path.resolve(__dirname, '..');
    const partial = fs.readFileSync(path.join(root, 'tmp/issue-actions.html'), 'utf8');
    const script = fs.readFileSync(path.join(root, 'assets/javascripts/issue_actions.js'), 'utf8');
    const issuePath = partial.match(/data-edit-path="([^"]+)"/)[1];
    const toolbar = '<div class="contextual"><a class="icon icon-edit" href="' + issuePath + '">Edit</a><a href="#watch">Watch</a></div>';
    const dom = new JSDOM(toolbar + partial, {url: 'https://redmine.example.test/', runScripts: 'outside-only'});
    const window = dom.window;
    window.eval(script);
    await new Promise(function (resolve) { window.document.addEventListener('DOMContentLoaded', resolve, {once: true}); });
    const edit = window.document.querySelector('.contextual .icon-edit');
    const action = edit.nextElementSibling;
    assert.equal(action.textContent, 'Edit with AI');
    assert.equal(action.dataset.method, 'post');
    assert.equal(new URL(action.href).searchParams.get('mode'), 'interactive');
    assert.equal(action.nextElementSibling.textContent, 'Code with AI');
    assert.equal(new URL(action.nextElementSibling.href).searchParams.get('mode'), 'code');
    assert.equal(action.nextElementSibling.dataset.method, 'post');
    assert.equal(action.nextElementSibling.nextElementSibling.textContent, 'Watch');
    assert.equal(window.document.querySelector('.ai-enhancement-actions a').textContent, 'Enhance with AI');
    window.eval(script);
    assert.equal(window.document.querySelectorAll('.contextual .ai-edit-with-ai').length, 1);

    const fallback = new JSDOM(partial, {url: 'https://redmine.example.test/', runScripts: 'outside-only'});
    fallback.window.eval(script);
    fallback.window.document.dispatchEvent(new fallback.window.Event('DOMContentLoaded'));
    assert.equal(fallback.window.document.querySelector('.ai-enhancement-actions .ai-edit-with-ai').textContent, 'Edit with AI');

    const subpath = partial.replace(/data-edit-path="/g, 'data-edit-path="/redmine').replace(/href="\//g, 'href="/redmine/');
    const subdom = new JSDOM(toolbar.replace(/href="\//g, 'href="/redmine/') + subpath, {url: 'https://redmine.example.test/redmine/', runScripts: 'outside-only'});
    subdom.window.eval(script);
    subdom.window.document.dispatchEvent(new subdom.window.Event('DOMContentLoaded'));
    assert.equal(subdom.window.document.querySelector('.contextual .icon-edit').nextElementSibling.textContent, 'Edit with AI');

    const hidden = new JSDOM(toolbar, {url: 'https://redmine.example.test/', runScripts: 'outside-only'});
    hidden.window.eval(script);
    hidden.window.document.dispatchEvent(new hidden.window.Event('DOMContentLoaded'));
    assert.equal(hidden.window.document.querySelector('.ai-edit-with-ai'), null);
    [dom, fallback, subdom, hidden].forEach(function (instance) { instance.window.close(); });
    console.log('Issue action placement: 12 assertions passed.');
}()).catch(function (error) { console.error(error); process.exitCode = 1; });
