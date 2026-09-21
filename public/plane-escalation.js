(function () {
  var ITEM_SELECTOR = '[data-testid="escalate-to-plane"]';
  var ICON_HTML =
    '<span data-plane-icon class="flex-shrink-0 inline-flex items-center justify-center" aria-hidden="true" style="width:16px;height:16px">' +
    '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="M7 7h10v10"/><path d="M7 17 17 7"/></svg></span>';

  var parseAuthCookie = function () {
    var match = document.cookie.match(/(?:^|; )cw_d_session_info=([^;]*)/);
    if (!match) {
      return {};
    }
    try {
      return JSON.parse(decodeURIComponent(match[1]));
    } catch (error) {
      return {};
    }
  };

  var conversationFromPath = function () {
    var match = window.location.pathname.match(
      /\/app\/accounts\/(\d+)\/conversations\/(\d+)/
    );
    if (!match) {
      return null;
    }
    return { accountId: match[1], conversationId: match[2] };
  };

  var localeLabel = function (menu) {
    var sample = ((menu && menu.textContent) || '') + document.body.innerText.slice(0, 400);
    if (/Отлож|Ожидающ|Завершить|Диалоги/.test(sample)) {
      return 'Эскалация';
    }
    var locale = (window.chatwootConfig && window.chatwootConfig.selectedLocale) || 'en';
    return String(locale).indexOf('ru') === 0 ? 'Эскалация' : 'Escalate';
  };

  var authHeaders = function () {
    var auth = parseAuthCookie();
    return {
      Accept: 'application/json',
      'Content-Type': 'application/json',
      'access-token': auth['access-token'] || '',
      'token-type': auth['token-type'] || 'Bearer',
      client: auth.client || '',
      expiry: String(auth.expiry || ''),
      uid: auth.uid || '',
    };
  };

  var escalate = function () {
    var ids = conversationFromPath();
    if (!ids) {
      return;
    }
    fetch(
      '/api/v1/accounts/' + ids.accountId + '/conversations/' + ids.conversationId + '/escalation',
      { method: 'POST', credentials: 'same-origin', headers: authHeaders() }
    )
      .then(function (response) {
        return response.json().then(function (body) {
          return { ok: response.ok, body: body };
        });
      })
      .then(function (result) {
        if (result.ok) {
          var identifier = result.body.identifier || result.body.issue_id || '';
          window.alert('Plane: ' + identifier);
          window.location.reload();
          return;
        }
        window.alert((result.body && result.body.error) || 'Plane escalation failed');
      })
      .catch(function () {
        window.alert('Plane escalation failed');
      });
  };

  var applyIcon = function (button) {
    var existingIcon = button.querySelector('span[class*="i-lucide"], span[aria-hidden="true"] svg, svg');
    if (existingIcon) {
      var host = existingIcon.closest('span') || existingIcon;
      host.outerHTML = ICON_HTML;
      return;
    }
    button.insertAdjacentHTML('afterbegin', ICON_HTML);
  };

  var applyLabel = function (button, label) {
    var labelEl = button.querySelector('span.min-w-0, span.truncate');
    if (labelEl) {
      labelEl.textContent = label;
      return;
    }
    Array.prototype.slice.call(button.childNodes).forEach(function (node) {
      if (node.nodeType === Node.TEXT_NODE) {
        node.textContent = '';
      }
    });
    var span = document.createElement('span');
    span.className = 'min-w-0 truncate';
    span.textContent = label;
    button.appendChild(span);
  };

  var bindEscalate = function (button) {
    if (button.dataset.planeBound === '1') {
      return;
    }
    button.dataset.planeBound = '1';
    button.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      escalate();
    });
  };

  var injectButton = function (menu) {
    if (!menu) {
      return;
    }
    var existing = menu.querySelector(ITEM_SELECTOR);
    if (existing) {
      if (!existing.querySelector('[data-plane-icon]')) {
        applyIcon(existing);
        applyLabel(existing, localeLabel(menu));
      }
      bindEscalate(existing);
      return;
    }
    var templateLi = Array.prototype.find.call(menu.querySelectorAll('li'), function (li) {
      return !li.querySelector(ITEM_SELECTOR);
    });
    var item = templateLi ? templateLi.cloneNode(true) : document.createElement('li');
    var button = item.querySelector('button');
    if (!button) {
      button = document.createElement('button');
      button.type = 'button';
      button.style.cssText =
        'display:flex;width:100%;align-items:center;gap:8px;padding:6px 8px;border:0;background:transparent;color:inherit;font:inherit;cursor:pointer;text-align:left';
      item.appendChild(button);
    }
    button.setAttribute('data-testid', 'escalate-to-plane');
    applyIcon(button);
    applyLabel(button, localeLabel(menu));
    bindEscalate(button);
    menu.insertBefore(item, menu.firstChild);
  };

  var scan = function () {
    document.querySelectorAll('.resolve-actions ul').forEach(injectButton);
  };

  var observer = new MutationObserver(scan);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  scan();
})();
