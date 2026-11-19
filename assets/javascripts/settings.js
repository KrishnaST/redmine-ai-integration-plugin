(function () {
    'use strict';

    function replaceAttributes(root, marker, value) {
        root.querySelectorAll('[name], [id], [for], [data-source-index], [data-table-index]').forEach(function (element) {
            Array.from(element.attributes).forEach(function (attribute) {
                element.setAttribute(attribute.name, attribute.value.replaceAll(marker, value));
            });
        });
        root.querySelectorAll('template').forEach(function (nested) {
            replaceAttributes(nested.content, marker, value);
        });
    }

    function updateSource(source) {
        const type = source.querySelector('.ai-source-type').value;
        source.querySelector('.ai-folder-fields').hidden = !['code_folder', 'documents_folder'].includes(type);
        source.querySelector('.ai-database-fields').hidden = type !== 'database';
        source.querySelector('.ai-legacy-fields').hidden = !['files', 'postgres_schema'].includes(type);
        source.querySelector('.ai-sample-fields').hidden = !source.querySelector('.ai-sample-enabled').checked;
        const port = source.querySelector('.ai-db-port');
        if (!source.dataset.nextTable) {
            let nextTable = 0;
            source.querySelectorAll('.ai-sample-rows > .ai-sample-row').forEach(function (row) {
                nextTable = Math.max(nextTable, Number(row.dataset.tableIndex) + 1);
            });
            source.dataset.nextTable = String(nextTable);
        }
        if (!port.value) {
            port.value = {postgresql: '5432', oracle: '1521', sqlserver: '1433', mysql: '3306'}[source.querySelector('.ai-db-type').value];
        }
    }

    document.addEventListener('DOMContentLoaded', function () {
        const rows = document.getElementById('ai-source-rows');
        if (!rows) return;
        let sourceIndex = 0;
        rows.querySelectorAll('.ai-source').forEach(function (source) {
            sourceIndex = Math.max(sourceIndex, Number(source.dataset.sourceIndex) + 1);
            updateSource(source);
        });
        document.getElementById('ai-add-source').addEventListener('click', function () {
            const fragment = document.getElementById('ai-source-template').content.cloneNode(true);
            replaceAttributes(fragment, '__SOURCE__', String(sourceIndex++));
            rows.appendChild(fragment);
            updateSource(rows.lastElementChild);
        });
        rows.addEventListener('change', function (event) {
            const source = event.target.closest('.ai-source');
            if (!source) return;
            if (event.target.classList.contains('ai-db-type')) source.querySelector('.ai-db-port').value = '';
            updateSource(source);
        });
        rows.addEventListener('click', function (event) {
            const source = event.target.closest('.ai-source');
            if (!source) return;
            if (event.target.classList.contains('ai-remove-source')) source.remove();
            if (event.target.classList.contains('ai-remove-sample')) event.target.closest('.ai-sample-row').remove();
            if (event.target.classList.contains('ai-add-sample')) {
                const target = source.querySelector('.ai-sample-rows');
                const index = Number(source.dataset.nextTable);
                source.dataset.nextTable = String(index + 1);
                const fragment = source.querySelector('.ai-sample-template').content.cloneNode(true);
                replaceAttributes(fragment, '__TABLE__', String(index));
                target.appendChild(fragment);
            }
        });
    });
}());
