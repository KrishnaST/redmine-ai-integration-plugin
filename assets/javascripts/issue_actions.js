(function () {
    'use strict';

    function positionEditWithAi() {
        document.querySelectorAll('.ai-enhancement-actions').forEach(function (actions) {
            const action = actions.querySelector('[data-ai-edit-action]');
            if (!action) { return; }
            const edit = Array.from(document.querySelectorAll('.contextual a.icon-edit')).find(function (link) {
                return new URL(link.href, document.baseURI).pathname === actions.dataset.editPath;
            });
            const codeAction = actions.querySelector('[data-ai-code-action]');
            if (edit) {
                edit.after(action);
                if (codeAction) { action.after(codeAction); }
            }
        });
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', positionEditWithAi, {once: true});
    } else {
        positionEditWithAi();
    }
}());
