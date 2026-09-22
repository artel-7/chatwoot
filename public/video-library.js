(function () {
  var NAV_SELECTOR = '[data-testid="video-library-nav"]';
  var ROOT_ID = 'video-library-root';
  var VIDEO_ICON =
    '<span class="flex-shrink-0 inline-flex items-center justify-center" aria-hidden="true" style="width:16px;height:16px">' +
    '<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">' +
    '<path d="m16 13 5.223 3.482a.5.5 0 0 0 .777-.416V7.934a.5.5 0 0 0-.777-.416L16 11"/><rect width="14" height="14" x="2" y="5" rx="2"/></svg></span>';

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

  var accountIdFromPath = function () {
    var match = window.location.pathname.match(/\/app\/accounts\/(\d+)/);
    return match ? match[1] : null;
  };

  var isRussian = function () {
    return /Центр поддержки|Диалоги|Настройки|Входящие/.test(document.body.innerText || '');
  };

  var t = function (key) {
    var ru = isRussian();
    var dict = {
      nav: ru ? 'Видеоматериалы' : 'Videos',
      title: ru ? 'Видеоматериалы' : 'Video library',
      lead: ru
        ? 'Загрузите видео — оно получит публичную ссылку, которой можно делиться без входа в Chatwoot.'
        : 'Upload a video to get a public link that anyone can open without signing in.',
      catalog: ru ? 'Открыть публичный каталог' : 'Open public catalog',
      close: ru ? 'Закрыть' : 'Close',
      upload: ru ? 'Загрузить видео' : 'Upload video',
      titleLabel: ru ? 'Название' : 'Title',
      descriptionLabel: ru ? 'Описание' : 'Description',
      fileLabel: ru ? 'Файл видео' : 'Video file',
      empty: ru ? 'Пока нет загруженных видео.' : 'No videos uploaded yet.',
      copy: ru ? 'Копировать ссылку' : 'Copy link',
      copied: ru ? 'Скопировано' : 'Copied',
      open: ru ? 'Открыть' : 'Open',
      remove: ru ? 'Удалить' : 'Delete',
      confirm: ru ? 'Удалить это видео?' : 'Delete this video?',
      uploading: ru ? 'Загрузка…' : 'Uploading…',
      error: ru ? 'Не удалось выполнить действие' : 'The action failed',
    };
    return dict[key] || key;
  };

  var authHeaders = function () {
    var auth = parseAuthCookie();
    return {
      Accept: 'application/json',
      'access-token': auth['access-token'] || '',
      'token-type': auth['token-type'] || 'Bearer',
      client: auth.client || '',
      expiry: String(auth.expiry || ''),
      uid: auth.uid || '',
    };
  };

  var apiUrl = function () {
    var accountId = accountIdFromPath();
    if (!accountId) {
      return null;
    }
    return '/api/v1/accounts/' + accountId + '/video_materials';
  };

  var formatSize = function (bytes) {
    var size = Number(bytes) || 0;
    if (size < 1024) {
      return size + ' B';
    }
    if (size < 1024 * 1024) {
      return (size / 1024).toFixed(1) + ' KB';
    }
    return (size / (1024 * 1024)).toFixed(1) + ' MB';
  };

  var request = function (method, url, body) {
    var headers = authHeaders();
    var options = { method: method, credentials: 'same-origin', headers: headers };
    if (body && !(body instanceof FormData)) {
      headers['Content-Type'] = 'application/json';
      options.body = JSON.stringify(body);
    } else if (body) {
      options.body = body;
    }
    return fetch(url, options).then(function (response) {
      if (response.status === 204) {
        return { ok: response.ok };
      }
      return response.json().then(function (payload) {
        return { ok: response.ok, body: payload };
      });
    });
  };

  var closePanel = function () {
    var root = document.getElementById(ROOT_ID);
    if (root) {
      root.remove();
    }
    document.querySelectorAll(NAV_SELECTOR).forEach(function (button) {
      button.removeAttribute('aria-current');
    });
  };

  var renderList = function (root, videos) {
    var list = root.querySelector('[data-role="list"]');
    if (!videos.length) {
      list.innerHTML = '<p class="vl-empty">' + t('empty') + '</p>';
      return;
    }
    list.innerHTML = videos
      .map(function (video) {
        return (
          '<article class="vl-card">' +
          '<div class="vl-card__body">' +
          '<h3>' +
          escapeHtml(video.title) +
          '</h3>' +
          (video.description
            ? '<p class="vl-desc">' + escapeHtml(video.description) + '</p>'
            : '') +
          '<p class="vl-url">' +
          escapeHtml(video.url) +
          '</p>' +
          '<p class="vl-meta">' +
          formatSize(video.byte_size) +
          '</p>' +
          '</div>' +
          '<div class="vl-card__actions">' +
          '<button type="button" data-copy="' +
          escapeAttr(video.url) +
          '">' +
          t('copy') +
          '</button>' +
          '<a href="' +
          escapeAttr(video.url) +
          '" target="_blank" rel="noreferrer">' +
          t('open') +
          '</a>' +
          '<button type="button" class="vl-danger" data-delete="' +
          video.id +
          '">' +
          t('remove') +
          '</button>' +
          '</div>' +
          '</article>'
        );
      })
      .join('');
  };

  var escapeHtml = function (value) {
    return String(value || '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;');
  };

  var escapeAttr = function (value) {
    return escapeHtml(value).replace(/'/g, '&#39;');
  };

  var loadVideos = function (root) {
    var url = apiUrl();
    if (!url) {
      return;
    }
    request('GET', url).then(function (result) {
      if (!result.ok) {
        root.querySelector('[data-role="status"]').textContent = t('error');
        return;
      }
      renderList(root, Array.isArray(result.body) ? result.body : []);
    });
  };

  var openPanel = function () {
    closePanel();
    var root = document.createElement('div');
    root.id = ROOT_ID;
    root.style.left = '0';
    root.style.zIndex = '60';
    root.innerHTML =
      '<style>' +
      '#video-library-root{position:fixed;top:0;right:0;bottom:0;z-index:40;overflow:auto;background:#0b0f19;color:#e5e7eb;font-family:inherit}' +
      '.vl-wrap{max-width:920px;margin:0 auto;padding:28px 24px 64px}' +
      '.vl-head{display:flex;justify-content:space-between;align-items:center;gap:16px;margin-bottom:8px}' +
      '.vl-wrap h1{margin:0;font-size:24px}' +
      '.vl-head button{background:#243049 !important}' +
      '.vl-lead{color:#9ca3af;margin:0 0 16px}' +
      '.vl-form{display:flex;flex-wrap:wrap;gap:12px;align-items:end;margin:20px 0;padding:16px;border:1px solid #243049;border-radius:16px;background:#151b2b}' +
      '.vl-field{display:flex;flex-direction:column;gap:6px;min-width:180px}' +
      '.vl-field label{font-size:12px;color:#9ca3af}' +
      '.vl-field input,.vl-field textarea{background:#0b0f19;color:#e5e7eb;border:1px solid #243049;border-radius:10px;padding:8px 10px;font:inherit}' +
      '.vl-field--wide{flex:1 1 100%}' +
      '.vl-field textarea{min-height:72px;resize:vertical}' +
      '.vl-form button,.vl-card__actions button,.vl-card__actions a{border:0;border-radius:10px;padding:8px 12px;background:#1d4ed8;color:#fff;text-decoration:none;font:inherit;cursor:pointer}' +
      '.vl-danger{background:#7f1d1d !important}' +
      '.vl-card{display:flex;justify-content:space-between;gap:16px;padding:16px;border:1px solid #243049;border-radius:16px;background:#151b2b;margin-bottom:12px}' +
      '.vl-card h3{margin:0 0 6px;font-size:16px}' +
      '.vl-url{margin:0;color:#93c5fd;word-break:break-all}' +
      '.vl-desc{margin:0 0 8px;color:#d1d5db;white-space:pre-wrap}' +
      '.vl-meta,.vl-empty,.vl-status{color:#9ca3af}' +
      '.vl-card__actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center}' +
      '</style>' +
      '<div class="vl-wrap">' +
      '<div class="vl-head"><h1>' +
      t('title') +
      '</h1><button type="button" data-role="close">' +
      t('close') +
      '</button></div>' +
      '<p class="vl-lead">' +
      t('lead') +
      ' <a href="/videos" target="_blank" rel="noreferrer">' +
      t('catalog') +
      '</a></p>' +
      '<form class="vl-form" data-role="form">' +
      '<div class="vl-field"><label>' +
      t('titleLabel') +
      '</label><input name="title" type="text"></div>' +
      '<div class="vl-field vl-field--wide"><label>' +
      t('descriptionLabel') +
      '</label><textarea name="description" rows="3"></textarea></div>' +
      '<div class="vl-field"><label>' +
      t('fileLabel') +
      '</label><input name="file" type="file" accept="video/*" required></div>' +
      '<button type="submit">' +
      t('upload') +
      '</button>' +
      '</form>' +
      '<p class="vl-status" data-role="status"></p>' +
      '<div data-role="list"></div>' +
      '</div>';
    document.body.appendChild(root);
    document.querySelectorAll(NAV_SELECTOR).forEach(function (button) {
      button.setAttribute('aria-current', 'page');
    });
    bindPanel(root);
    loadVideos(root);
  };

  var bindPanel = function (root) {
    var form = root.querySelector('[data-role="form"]');
    var status = root.querySelector('[data-role="status"]');
    var closeButton = root.querySelector('[data-role="close"]');
    if (closeButton) {
      closeButton.addEventListener('click', closePanel);
    }
    form.addEventListener('submit', function (event) {
      event.preventDefault();
      var url = apiUrl();
      var fileInput = form.querySelector('input[name="file"]');
      var titleInput = form.querySelector('input[name="title"]');
      var descriptionInput = form.querySelector('textarea[name="description"]');
      if (!url || !fileInput.files[0]) {
        return;
      }
      var data = new FormData();
      data.append('file', fileInput.files[0]);
      if (titleInput.value.trim()) {
        data.append('title', titleInput.value.trim());
      }
      if (descriptionInput && descriptionInput.value.trim()) {
        data.append('description', descriptionInput.value.trim());
      }
      status.textContent = t('uploading');
      request('POST', url, data)
        .then(function (result) {
          if (!result.ok) {
            status.textContent = (result.body && result.body.error) || t('error');
            return;
          }
          form.reset();
          status.textContent = '';
          loadVideos(root);
        })
        .catch(function () {
          status.textContent = t('error');
        });
    });
    root.addEventListener('click', function (event) {
      var copyTarget = event.target.closest('[data-copy]');
      if (copyTarget) {
        navigator.clipboard.writeText(copyTarget.getAttribute('data-copy') || '');
        copyTarget.textContent = t('copied');
        window.setTimeout(function () {
          copyTarget.textContent = t('copy');
        }, 1200);
        return;
      }
      var deleteTarget = event.target.closest('[data-delete]');
      if (deleteTarget) {
        if (!window.confirm(t('confirm'))) {
          return;
        }
        var url = apiUrl();
        request('DELETE', url + '/' + deleteTarget.getAttribute('data-delete')).then(function (result) {
          if (!result.ok) {
            status.textContent = t('error');
            return;
          }
          loadVideos(root);
        });
      }
    });
  };

  var injectNav = function () {
    var existing = document.querySelector(NAV_SELECTOR);
    if (existing) {
      var label = existing.querySelector('span:last-child');
      if (label && !label.querySelector('svg') && label.textContent !== t('nav')) {
        label.textContent = t('nav');
      }
      return;
    }
    if (!accountIdFromPath()) {
      return;
    }
    var helpButton = Array.prototype.find.call(
      document.querySelectorAll('a[role="button"], button'),
      function (el) {
        return /^(Центр поддержки|Help Center)$/.test(
          (el.textContent || '').replace(/\s+/g, ' ').trim()
        );
      }
    );
    if (!helpButton || !helpButton.parentNode) {
      return;
    }
    var group = helpButton.closest('li') || helpButton.parentNode;
    var item = document.createElement(group.tagName || 'li');
    if (group.className) {
      item.className = group.className;
    }
    var button = helpButton.cloneNode(false);
    button.className = helpButton.className;
    button.removeAttribute('href');
    button.setAttribute('role', 'button');
    button.setAttribute('data-testid', 'video-library-nav');
    button.innerHTML = VIDEO_ICON + '<span>' + t('nav') + '</span>';
    button.addEventListener('click', function (event) {
      event.preventDefault();
      event.stopPropagation();
      if (document.getElementById(ROOT_ID)) {
        closePanel();
        return;
      }
      openPanel();
    });
    item.appendChild(button);
    if (group.parentNode) {
      group.parentNode.insertBefore(item, group.nextSibling);
    }
  };

  var observer = new MutationObserver(injectNav);
  observer.observe(document.documentElement, { childList: true, subtree: true });
  injectNav();
})();
