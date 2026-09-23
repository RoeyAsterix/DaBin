(() => {
  'use strict';
  const $ = id => document.getElementById(id);
  const desktop = $('desktop');
  const widget = $('widget');
  const board = $('board');
  const composer = $('composer');
  const toast = $('toast');
  const bodyButton = $('robot-body');
  const grip = $('widget-grip');
  const datePicker = $('date-picker');
  const positionKey = 'dabin-quiet-widget-v2';
  const params = new URLSearchParams(location.search);
  if (['light', 'dark'].includes(params.get('appearance'))) document.documentElement.dataset.appearance = params.get('appearance');

  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, ch => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[ch]);
  const localDay = date => `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  const dayDate = value => new Date(`${value}T12:00:00`);
  const shiftDay = (value, offset) => { const date = dayDate(value); date.setDate(date.getDate() + offset); return localDay(date); };
  const today = localDay(new Date());
  const yesterday = shiftDay(today, -1);
  const earlier = shiftDay(today, -2);
  const futureReminder = `${shiftDay(today, 2)}T09:30`;
  const longDate = day => dayDate(day).toLocaleDateString('en-US', { weekday: 'long', month: 'long', day: 'numeric' });
  const shortDate = day => dayDate(day).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const displayTime = date => date.toLocaleTimeString('en-US', { hour: 'numeric', minute: '2-digit' });
  const groupFor = entry => entry.kind === 'link' ? 'links' : ['image', 'video'].includes(entry.kind) ? 'media' : ['pdf', 'document', 'ai', 'file', 'unknown'].includes(entry.kind) ? 'files' : 'other';
  const kindName = { link: 'Link', image: 'Image', video: 'Video', pdf: 'PDF', document: 'Document', ai: 'Illustrator file', file: 'File', text: 'Text', unknown: 'Unknown file' };
  const entries = [
    { id: 'link-room', day: today, time: '12:41 PM', sort: 1241, kind: 'link', title: 'A room for thinking', description: 'On the quiet architecture of making room for ideas.', source: 'Stillroom Journal · stillroom.example', original: 'https://stillroom.example/a-room-for-thinking', preview: 'rich', art: 'architecture', comment: '', reminder: '', sample: true },
    { id: 'video-walk', day: today, time: '11:58 AM', sort: 1158, kind: 'video', title: 'Morning walk through.mov', description: 'Video · 1 min 18 sec · preview frame', source: 'Local file', original: '', preview: 'poster', comment: '', reminder: '', sample: true },
    { id: 'image-light', day: today, time: '11:17 AM', sort: 1117, kind: 'image', title: 'Window light study.jpg', description: 'Image · 2.4 MB', source: 'Local file', original: '', preview: 'thumbnail', comment: 'The green feels right against the stone.', reminder: '', sample: true },
    { id: 'pdf-spaces', day: today, time: '10:22 AM', sort: 1022, kind: 'pdf', title: 'Notes on small spaces.pdf', description: 'PDF · 8 pages · preview unavailable', source: 'Local file', original: '', preview: 'fallback', comment: '', reminder: futureReminder, sample: true },
    { id: 'link-fallback', day: today, time: '9:44 AM', sort: 944, kind: 'link', title: 'fieldnotes.example / issue 08', description: 'https://fieldnotes.example/issue-08 · preview unavailable', source: 'fieldnotes.example', original: 'https://fieldnotes.example/issue-08', preview: 'fallback', comment: '', reminder: '', sample: true },
    { id: 'ai-study', day: today, time: '8:36 AM', sort: 836, kind: 'ai', title: 'Mark studies — September.ai', description: 'Illustrator file · no Quick Look preview', source: 'Local file', original: '', preview: 'fallback', comment: '', reminder: '', sample: true },
    { id: 'link-library', day: yesterday, time: '4:06 PM', sort: 1606, kind: 'link', title: 'The everyday library', description: 'A small collection of objects made to be kept.', source: 'Common Place · commonplace.example', original: 'https://commonplace.example/everyday-library', preview: 'rich', art: 'library', comment: '', reminder: '', sample: true },
    { id: 'doc-outline', day: yesterday, time: '2:33 PM', sort: 1433, kind: 'document', title: 'A very long working title for an early concept outline.pages', description: 'Pages document · Quick Look unavailable', source: 'Local file', original: '', preview: 'fallback', comment: '', reminder: '', sample: true },
    { id: 'text-thought', day: yesterday, time: '9:18 AM', sort: 918, kind: 'text', title: 'Ask about the ceramic glaze', description: 'A thought pasted before leaving the studio.', source: 'Pasted text', original: 'Ask about the ceramic glaze on the second shelf.', preview: 'text', comment: '', reminder: '', sample: true },
    { id: 'unknown-archive', day: earlier, time: '3:12 PM', sort: 1512, kind: 'unknown', title: 'reference-pack.bundle', description: 'Readable file · no preview available', source: 'Local file', original: '', preview: 'fallback', comment: '', reminder: '', sample: true }
  ];

  let activeDay = today;
  let filter = 'all';
  let searchQuery = '';
  let searchExpanded = false;
  let view = 'daily';
  let returnView = 'daily';
  let activeId = null;
  let highlightedId = null;
  let clickTimer = null;
  let digestTimer = null;
  let toastTimer = null;
  let dragOrigin = null;
  const findEntry = id => entries.find(entry => entry.id === id);
  const searchText = value => String(value ?? '').normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase();
  const matchesQuery = entry => {
    const words = searchText(searchQuery.trim()).split(/\s+/).filter(Boolean);
    if (!words.length) return false;
    const haystack = searchText([entry.title, entry.description, entry.source, entry.original, entry.comment, kindName[entry.kind]].join(' '));
    return words.every(word => haystack.includes(word));
  };

  function previewMarkup(entry, detail = false) {
    const type = entry.kind;
    if (type === 'image' && entry.objectUrl) return `<span class="preview image actual-image"><img src="${escapeHtml(entry.objectUrl)}" data-preview-id="${escapeHtml(entry.id)}" alt="Preview of ${escapeHtml(entry.title)}"></span>`;
    if (type === 'link' && entry.preview === 'rich') return `<span class="preview rich-link ${entry.art === 'library' ? 'library' : ''}" aria-hidden="true"><i class="art-sun"></i><i class="art-window"></i></span>`;
    if (type === 'link') {
      const host = (() => { try { return new URL(entry.original).hostname; } catch { return entry.source; } })();
      return `<span class="preview link-fallback" aria-hidden="true"><svg><use href="#i-link"/></svg><span class="domain-tile">${escapeHtml(host)}</span></span>`;
    }
    if (type === 'image') return '<span class="preview image" aria-hidden="true"></span>';
    if (type === 'video' && entry.preview === 'fallback') return '<span class="preview video-fallback" aria-hidden="true"><span class="format">VIDEO</span></span>';
    if (type === 'video') return '<span class="preview video" aria-hidden="true"><span class="play-ring">▶</span></span>';
    if (type === 'pdf' || type === 'document') return `<span class="preview file-preview ${type}" aria-hidden="true"><span class="sheet"><b>${type === 'pdf' ? 'PDF' : 'DOC'}</b><i></i><i></i><i></i></span></span>`;
    if (type === 'ai') return '<span class="preview ai" aria-hidden="true"><span class="format">Ai</span></span>';
    if (type === 'text') return '<span class="preview text" aria-hidden="true"><span class="quote-lines"><i></i><i></i><i></i><i></i></span></span>';
    return `<span class="preview unknown" aria-hidden="true"><svg><use href="#i-file"/></svg>${detail ? '<span class="format">FILE</span>' : ''}</span>`;
  }

  function cardMarkup(entry, searchRole = '') {
    const details = entry.preview === 'fallback' ? '<span class="preview-issue">Preview unavailable</span>' : '';
    const roleClass = searchRole ? ` ${searchRole === 'match' ? 'search-match' : 'search-context'}` : '';
    const commentLabel = entry.comment ? 'Comment added' : 'Comment';
    const reminderLabel = entry.reminder ? `Reminder · ${shortDate(entry.reminder.slice(0, 10))}` : 'Reminder';
    return `<article class="capture-card ${highlightedId === entry.id ? 'highlighted' : ''}${roleClass}"><button class="card-main" type="button" data-id="${escapeHtml(entry.id)}" aria-label="${escapeHtml(entry.title)}, ${escapeHtml(kindName[entry.kind])}, captured ${escapeHtml(entry.time)}">${previewMarkup(entry)}<span class="card-body"><span class="card-meta"><span class="kind-label">${escapeHtml(kindName[entry.kind])}</span><span aria-hidden="true">·</span><span class="source-name">${escapeHtml(entry.source)}</span></span><span class="card-title-line"><strong title="${escapeHtml(entry.title)}">${escapeHtml(entry.title)}</strong><time>${escapeHtml(entry.time)}</time></span><span class="card-description">${escapeHtml(entry.description)}</span>${details ? `<span class="card-details">${details}</span>` : ''}</span></button><div class="card-actions"><button class="card-action${entry.comment ? ' has-value' : ''}" type="button" data-action="comment" data-id="${escapeHtml(entry.id)}" aria-label="${escapeHtml(commentLabel)} for ${escapeHtml(entry.title)}"><svg aria-hidden="true"><use href="#i-note"/></svg>${escapeHtml(commentLabel)}</button><button class="card-action${entry.reminder ? ' has-value' : ''}" type="button" data-action="reminder" data-id="${escapeHtml(entry.id)}" aria-label="${escapeHtml(reminderLabel)} for ${escapeHtml(entry.title)}"><svg aria-hidden="true"><use href="#i-clock"/></svg>${escapeHtml(reminderLabel)}</button></div></article>`;
  }

  function updateCounts() {
    const count = entries.filter(entry => entry.reminder).length;
    const toggle = $('reminders-toggle');
    if (toggle) toggle.setAttribute('aria-label', count ? `Show reminders, ${count} set` : 'Show reminders');
  }

  function fitBoard() {
    if (board.hidden) return;
    let height = 410;
    if (view === 'daily' || view === 'reminders') {
      const list = view === 'daily' ? $('capture-list') : $('reminders-list');
      const top = list.getBoundingClientRect().top - board.getBoundingClientRect().top;
      const content = [...list.children].reduce((sum, child) => sum + child.offsetHeight, 0);
      const padding = parseFloat(getComputedStyle(list).paddingBottom) || 0;
      height = Math.max(220, Math.min(410, Math.ceil(top + content + padding + 1)));
    }
    board.style.setProperty('--board-height', `${height}px`);
    placeBoard();
  }

  function renderSearchResults() {
    board.dataset.search = 'true';
    const list = $('capture-list');
    const groups = [...new Set(entries.map(entry => entry.day))].sort((a, b) => b.localeCompare(a)).map(day => {
      const dayEntries = entries.map((entry, index) => ({ entry, index })).filter(item => item.entry.day === day).sort((a, b) => a.entry.sort - b.entry.sort || a.index - b.index);
      const matches = dayEntries.map((item, index) => filter === 'all' || groupFor(item.entry) === filter ? matchesQuery(item.entry) ? index : -1 : -1).filter(index => index >= 0);
      if (!matches.length) return null;
      const included = new Set();
      for (const index of matches) for (const neighbor of [index - 1, index, index + 1]) if (neighbor >= 0 && neighbor < dayEntries.length) included.add(neighbor);
      const matched = new Set(matches);
      return { day, matches: matches.length, items: [...included].sort((a, b) => a - b).map(index => cardMarkup(dayEntries[index].entry, matched.has(index) ? 'match' : 'context')) };
    }).filter(Boolean);
    $('daily-title').textContent = 'Results';
    const total = groups.reduce((sum, group) => sum + group.matches, 0);
    $('day-summary').textContent = groups.length ? `${total} ${total === 1 ? 'match' : 'matches'} across ${groups.length} ${groups.length === 1 ? 'date' : 'dates'}` : 'No matching dates';
    list.innerHTML = groups.length ? groups.map(group => `<section class="search-date-group" id="search-day-${group.day}" aria-label="${escapeHtml(longDate(group.day))}"><div class="search-date-header"><time datetime="${group.day}">${escapeHtml(longDate(group.day))}</time><span>${group.matches} ${group.matches === 1 ? 'match' : 'matches'}</span><button type="button" data-open-day="${group.day}">View day</button></div><div class="search-date-strip">${group.items.join('')}</div></section>`).join('') : '<div class="empty-state"><div><div class="empty-icon"><svg><use href="#i-calendar"/></svg></div><h2>No matching dates</h2><p>Try another word or choose a different type filter.</p></div></div>';
    updateCounts();
    fitBoard();
  }

  function renderDaily() {
    datePicker.value = activeDay;
    document.querySelectorAll('#filter-row button').forEach(button => button.setAttribute('aria-pressed', String(button.dataset.filter === filter)));
    $('search-clear').hidden = !searchQuery;
    if (searchQuery.trim()) { renderSearchResults(); return; }
    board.dataset.search = 'false';
    $('daily-title').textContent = activeDay === today ? 'Today' : activeDay === yesterday ? 'Yesterday' : shortDate(activeDay);
    const visible = entries.filter(entry => entry.day === activeDay && (filter === 'all' || groupFor(entry) === filter)).sort((a, b) => b.sort - a.sort);
    const total = entries.filter(entry => entry.day === activeDay).length;
    $('day-summary').textContent = `${activeDay === today || activeDay === yesterday ? `${shortDate(activeDay)} · ` : ''}${total} ${total === 1 ? 'capture' : 'captures'}`;
    const list = $('capture-list');
    if (visible.length) list.innerHTML = visible.map(entry => cardMarkup(entry)).join('');
    else {
      const name = filter[0].toUpperCase() + filter.slice(1);
      list.innerHTML = `<div class="empty-state"><div><div class="empty-icon"><svg><use href="${filter === 'all' ? '#i-calendar' : '#i-file'}"/></svg></div><h2>${filter === 'all' ? 'Nothing captured on this day' : `No ${name} captured on this day`}</h2><p>${filter === 'all' ? 'A quiet day is part of the story. Drop or paste something when you want to keep it.' : 'Other things may still be here. Choose All to see the whole day.'}</p><button type="button" data-empty-action="${filter === 'all' ? 'capture' : 'all'}">${filter === 'all' ? 'Add a capture' : 'Show all captures'}</button></div></div>`;
    }
    updateCounts();
    fitBoard();
  }

  function renderReminders() {
    const reminders = entries.filter(entry => entry.reminder).sort((a, b) => a.reminder.localeCompare(b.reminder));
    $('reminders-list').innerHTML = reminders.length ? reminders.map(entry => cardMarkup(entry)).join('') : '<div class="empty-state"><div><div class="empty-icon"><svg><use href="#i-bell"/></svg></div><h2>No reminders yet</h2><p>Set a gentle reminder from any captured card. It will still live on its original day.</p><button type="button" data-empty-action="daily">Browse Daily</button></div></div>';
    updateCounts();
    fitBoard();
  }

  function renderDetail() {
    const entry = findEntry(activeId);
    if (!entry) return;
    $('detail-return-label').textContent = returnView === 'reminders' ? 'Reminders' : 'Daily';
    $('detail-hero').innerHTML = previewMarkup(entry, true);
    $('detail-kind').textContent = kindName[entry.kind].toUpperCase();
    $('detail-title').textContent = entry.title;
    $('detail-description').textContent = entry.description;
    $('detail-time').textContent = `${longDate(entry.day)} · ${entry.time}`;
    $('detail-source').textContent = entry.kind === 'link' ? entry.original : entry.kind === 'text' ? 'Pasted text' : entry.title;
    const originalAvailable = !entry.sample && !!entry.original;
    $('detail-original-note').textContent = entry.sample && entry.kind !== 'text' ? 'Fictional sample — original not attached' : entry.kind === 'text' ? 'The full text is kept in this card' : entry.preview === 'fallback' ? 'Preview unavailable; original is still accessible this session' : 'Captured original available this session';
    $('open-original').disabled = !originalAvailable && entry.kind !== 'text';
    $('open-original').innerHTML = `<svg><use href="${entry.kind === 'text' ? '#i-note' : '#i-external'}"/></svg>${entry.kind === 'text' ? 'Copy text' : 'Open original'}`;
    $('comment-input').value = entry.comment;
    $('reminder-input').value = entry.reminder;
    $('detail-save-status').textContent = '';
    fitBoard();
  }

  function setView(next) {
    view = next;
    board.dataset.view = next;
    $('board-search').hidden = next !== 'daily' || !searchExpanded;
    $('daily-view').hidden = next !== 'daily';
    $('detail-view').hidden = next !== 'detail';
    $('reminders-view').hidden = next !== 'reminders';
    $('reminders-toggle').setAttribute('aria-pressed', String(next === 'reminders' || next === 'detail' && returnView === 'reminders'));
    if (next === 'daily') renderDaily();
    else if (next === 'reminders') renderReminders();
    else renderDetail();
  }

  function clampWidget(left, top) {
    const maxX = Math.max(10, desktop.clientWidth - widget.offsetWidth - 10);
    const maxY = Math.max(10, desktop.clientHeight - widget.offsetHeight - 10);
    widget.style.left = `${Math.min(maxX, Math.max(10, left))}px`;
    widget.style.top = `${Math.min(maxY, Math.max(10, top))}px`;
    placeComposer();
    if (!board.hidden && desktop.clientWidth > 700) placeBoard();
  }
  function rememberWidget() {
    try { localStorage.setItem(positionKey, JSON.stringify({ left: widget.offsetLeft, top: widget.offsetTop })); } catch { /* The prototype still works without localStorage. */ }
  }
  function placeBoard() {
    if (board.hidden) return;
    if (desktop.clientWidth <= 700) {
      board.style.left = '12px'; board.style.top = '12px';
      clampWidget(desktop.clientWidth - widget.offsetWidth - 17, desktop.clientHeight - widget.offsetHeight - 12);
    } else {
      const right = widget.offsetLeft + widget.offsetWidth + 18;
      const left = widget.offsetLeft - board.offsetWidth - 18;
      const x = right + board.offsetWidth + 12 <= desktop.clientWidth ? right : left >= 12 ? left : Math.max(12, desktop.clientWidth - board.offsetWidth - 12);
      const y = Math.min(Math.max(12, widget.offsetTop - 84), Math.max(12, desktop.clientHeight - board.offsetHeight - 12));
      board.style.left = `${x}px`;
      board.style.top = `${y}px`;
    }
  }
  function placeComposer() {
    if (composer.hidden) return;
    const width = composer.offsetWidth, height = composer.offsetHeight;
    const right = widget.offsetLeft + widget.offsetWidth + 12;
    const left = widget.offsetLeft - width - 12;
    const x = right + width + 12 < desktop.clientWidth ? right : left >= 12 ? left : Math.max(12, desktop.clientWidth - width - 12);
    const y = Math.max(12, Math.min(widget.offsetTop + 6, desktop.clientHeight - height - 12));
    composer.style.left = `${x}px`; composer.style.top = `${y}px`;
  }
  function openBoard(next = 'daily') {
    clearTimeout(clickTimer);
    composer.hidden = true;
    board.hidden = false;
    setView(next);
    placeBoard();
  }
  function closeBoard() { board.hidden = true; bodyButton.focus(); }
  function openComposer() {
    board.hidden = true;
    composer.hidden = false; placeComposer(); $('paste-input').focus();
  }
  function closeComposer() { composer.hidden = true; bodyButton.focus(); }

  function showToast(message, itemId = null, success = true) {
    clearTimeout(toastTimer);
    toast.innerHTML = `${success ? '<svg aria-hidden="true"><use href="#i-check"/></svg>' : ''}<span>${escapeHtml(message)}</span>${itemId ? '<button type="button" data-view-item="true">View</button>' : ''}`;
    toast.hidden = false;
    if (itemId) toast.querySelector('[data-view-item]').addEventListener('click', () => {
      const entry = findEntry(itemId);
      if (!entry) return;
      activeDay = entry.day; filter = 'all'; highlightedId = entry.id; searchQuery = ''; searchExpanded = false; $('search-input').value = ''; $('search-toggle').setAttribute('aria-expanded', 'false'); $('search-toggle').setAttribute('aria-pressed', 'false');
      openBoard('daily'); toast.hidden = true;
      const row = $('capture-list').querySelector(`[data-id="${CSS.escape(entry.id)}"]`);
      if (row) row.focus({ preventScroll: true });
    });
    toastTimer = setTimeout(() => { if (!toast.matches(':hover, :focus-within')) toast.hidden = true; }, 4800);
  }
  toast.addEventListener('mouseleave', () => { if (!toast.hidden) toastTimer = setTimeout(() => { toast.hidden = true; }, 1200); });

  function digest(count) {
    clearTimeout(digestTimer);
    widget.classList.remove('drag-over', 'digesting');
    $('robot-bubble').textContent = count === 1 ? 'Saved to today' : `${count} saved to today`;
    void widget.offsetWidth;
    widget.classList.add('digesting');
    digestTimer = setTimeout(() => { widget.classList.remove('digesting'); $('robot-bubble').textContent = 'Release to capture'; }, 850);
  }
  function saveBatch(items, invalid = 0) {
    if (!items.length) { showToast('This item did not include readable data. Try paste instead.', null, false); return; }
    for (const item of items) {
      const now = new Date();
      entries.push({ id: `capture-${now.getTime()}-${Math.random().toString(36).slice(2, 7)}`, day: localDay(now), time: displayTime(now), sort: now.getHours() * 100 + now.getMinutes() + now.getSeconds() / 100, comment: '', reminder: '', sample: false, ...item });
    }
    composer.hidden = true;
    renderDaily();
    digest(items.length);
    showToast(`${items.length} ${items.length === 1 ? 'item' : 'items'} added to today${invalid ? ` · ${invalid} unreadable` : ''}`, entries.at(-1).id);
  }
  function textItems(value) {
    const text = String(value || '').trim();
    if (!text) return [];
    if (/^https?:\/\/\S+$/i.test(text)) {
      try {
        const url = new URL(text);
        return [{ kind: 'link', title: `${url.hostname}${url.pathname === '/' ? '' : ` ${decodeURIComponent(url.pathname).slice(0, 38)}`}`, description: text, source: url.hostname, original: text, preview: 'fallback' }];
      } catch { /* Readable text remains a text capture. */ }
    }
    return [{ kind: 'text', title: text.split('\n')[0].slice(0, 70), description: text.length > 125 ? `${text.slice(0, 125)}…` : text, source: 'Pasted text', original: text, preview: 'text' }];
  }
  function fileItems(files) {
    return Array.from(files || []).map(file => {
      const extension = file.name.split('.').pop().toLowerCase();
      const kind = file.type.startsWith('image/') || ['png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'].includes(extension) ? 'image' : file.type.startsWith('video/') || ['mov', 'mp4', 'm4v', 'webm'].includes(extension) ? 'video' : extension === 'pdf' ? 'pdf' : extension === 'ai' ? 'ai' : ['doc', 'docx', 'pages', 'ppt', 'pptx', 'key', 'rtf', 'txt', 'md'].includes(extension) ? 'document' : 'file';
      const objectUrl = URL.createObjectURL(file);
      const size = file.size < 1048576 ? `${Math.max(1, Math.round(file.size / 1024))} KB` : `${(file.size / 1048576).toFixed(1)} MB`;
      return { kind, title: file.name, description: `${kindName[kind]} · ${size}${kind === 'image' ? ' · local thumbnail' : ' · type preview'}`, source: 'Dropped file', original: objectUrl, objectUrl: kind === 'image' ? objectUrl : '', preview: kind === 'image' ? 'thumbnail' : 'fallback' };
    });
  }

  grip.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    event.preventDefault(); grip.setPointerCapture(event.pointerId);
    dragOrigin = { x: event.clientX, y: event.clientY, left: widget.offsetLeft, top: widget.offsetTop };
  });
  grip.addEventListener('pointermove', event => { if (dragOrigin) clampWidget(dragOrigin.left + event.clientX - dragOrigin.x, dragOrigin.top + event.clientY - dragOrigin.y); });
  grip.addEventListener('pointerup', () => { if (dragOrigin) rememberWidget(); dragOrigin = null; });
  grip.addEventListener('pointercancel', () => { dragOrigin = null; });
  grip.addEventListener('keydown', event => {
    const step = event.shiftKey ? 30 : 10;
    const moves = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] };
    if (!moves[event.key]) return;
    event.preventDefault(); clampWidget(widget.offsetLeft + moves[event.key][0], widget.offsetTop + moves[event.key][1]); rememberWidget();
  });
  bodyButton.addEventListener('click', event => {
    clearTimeout(clickTimer);
    if (event.detail >= 2) return;
    if (event.detail === 0) { openComposer(); return; }
    clickTimer = setTimeout(openComposer, 550);
  });
  bodyButton.addEventListener('dblclick', event => { event.preventDefault(); clearTimeout(clickTimer); openBoard('daily'); });
  $('composer-close').addEventListener('click', closeComposer);
  $('board-close').addEventListener('click', closeBoard);
  $('save-paste').addEventListener('click', () => {
    const items = textItems($('paste-input').value);
    if (!items.length) { showToast('Paste something first.', null, false); $('paste-input').focus(); return; }
    saveBatch(items); $('paste-input').value = '';
  });
  $('paste-input').addEventListener('keydown', event => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); $('save-paste').click(); } });
  $('file-picker').addEventListener('change', event => { const items = fileItems(event.target.files); if (items.length) saveBatch(items); event.target.value = ''; });

  function clearSearch(close = false) {
    searchQuery = ''; $('search-input').value = ''; $('search-clear').hidden = true;
    if (close) { searchExpanded = false; $('board-search').hidden = true; $('search-toggle').setAttribute('aria-expanded', 'false'); $('search-toggle').setAttribute('aria-pressed', 'false'); }
  }
  $('previous-day').addEventListener('click', () => { clearSearch(true); activeDay = shiftDay(activeDay, -1); highlightedId = null; renderDaily(); });
  $('next-day').addEventListener('click', () => { clearSearch(true); activeDay = shiftDay(activeDay, 1); highlightedId = null; renderDaily(); });
  datePicker.addEventListener('change', () => { if (datePicker.value) { clearSearch(true); activeDay = datePicker.value; highlightedId = null; renderDaily(); } });
  $('filter-row').addEventListener('click', event => { const button = event.target.closest('[data-filter]'); if (!button) return; filter = button.dataset.filter; highlightedId = null; $('capture-list').scrollTop = 0; renderDaily(); });
  $('reminders-toggle').addEventListener('click', () => setView(view === 'reminders' || view === 'detail' && returnView === 'reminders' ? 'daily' : 'reminders'));
  $('search-toggle').addEventListener('click', () => {
    const opening = view !== 'daily' || !searchExpanded;
    if (view !== 'daily') setView('daily');
    searchExpanded = opening;
    $('search-toggle').setAttribute('aria-expanded', String(searchExpanded));
    $('search-toggle').setAttribute('aria-pressed', String(searchExpanded));
    $('board-search').hidden = !searchExpanded;
    if (searchExpanded) $('search-input').focus();
    else { clearSearch(); renderDaily(); $('search-toggle').focus(); }
    fitBoard();
  });
  $('search-input').addEventListener('input', event => { searchQuery = event.target.value; highlightedId = null; $('capture-list').scrollTop = 0; setView('daily'); });
  $('search-clear').addEventListener('click', () => { clearSearch(); setView('daily'); $('search-input').focus(); });
  function openDetail(id, from, focusField = '') {
    activeId = id; returnView = from; activeDay = findEntry(id)?.day || activeDay; setView('detail');
    if (focusField === 'comment') $('comment-input').focus();
    else if (focusField === 'reminder') $('reminder-input').focus();
  }
  $('capture-list').addEventListener('click', event => {
    const dayButton = event.target.closest('[data-open-day]');
    if (dayButton) { clearSearch(true); activeDay = dayButton.dataset.openDay; filter = 'all'; highlightedId = null; renderDaily(); return; }
    const action = event.target.closest('[data-action][data-id]');
    if (action) { openDetail(action.dataset.id, 'daily', action.dataset.action); return; }
    const item = event.target.closest('.card-main[data-id]');
    if (item) { openDetail(item.dataset.id, 'daily'); return; }
    const emptyAction = event.target.closest('[data-empty-action]');
    if (emptyAction?.dataset.emptyAction === 'all') { filter = 'all'; renderDaily(); }
    else if (emptyAction?.dataset.emptyAction === 'capture') openComposer();
  });
  $('reminders-list').addEventListener('click', event => {
    const action = event.target.closest('[data-action][data-id]');
    if (action) { openDetail(action.dataset.id, 'reminders', action.dataset.action); return; }
    const item = event.target.closest('.card-main[data-id]'); if (item) { openDetail(item.dataset.id, 'reminders'); return; }
    if (event.target.closest('[data-empty-action="daily"]')) setView('daily');
  });
  $('detail-back').addEventListener('click', () => setView(returnView));
  $('clear-reminder').addEventListener('click', () => { $('reminder-input').value = ''; $('reminder-input').focus(); });
  $('save-detail').addEventListener('click', () => {
    const entry = findEntry(activeId); if (!entry) return;
    entry.comment = $('comment-input').value.trim(); entry.reminder = $('reminder-input').value;
    $('detail-save-status').textContent = 'Saved on its original day';
    updateCounts();
    showToast('Card details saved');
  });
  $('open-original').addEventListener('click', async () => {
    const entry = findEntry(activeId); if (!entry) return;
    if (entry.kind === 'text') {
      try { await navigator.clipboard.writeText(entry.original); showToast('Text copied'); }
      catch { showToast('Copy unavailable here. The original text remains on the card.', null, false); }
    } else if (!entry.sample && entry.original) window.open(entry.original, '_blank', 'noopener,noreferrer');
  });
  document.addEventListener('error', event => {
    if (!(event.target instanceof HTMLImageElement) || !event.target.matches('[data-preview-id]')) return;
    const entry = findEntry(event.target.dataset.previewId);
    if (!entry || !entry.objectUrl) return;
    entry.objectUrl = '';
    entry.preview = 'fallback';
    entry.description = `${kindName[entry.kind]} · preview unavailable; original still opens this session`;
    if (view === 'detail' && activeId === entry.id) renderDetail();
    else if (view === 'daily') renderDaily();
    else if (view === 'reminders') renderReminders();
  }, true);
  widget.addEventListener('dragover', event => { event.preventDefault(); widget.classList.add('drag-over'); $('robot-bubble').textContent = 'Release to capture'; });
  widget.addEventListener('dragleave', event => { if (!widget.contains(event.relatedTarget)) widget.classList.remove('drag-over'); });
  widget.addEventListener('drop', event => {
    event.preventDefault(); widget.classList.remove('drag-over');
    if (event.dataTransfer.files?.length) { saveBatch(fileItems(event.dataTransfer.files)); return; }
    const uri = event.dataTransfer.getData('text/uri-list').split('\n').map(s => s.trim()).filter(s => s && !s.startsWith('#'));
    const items = uri.length ? uri.flatMap(textItems) : textItems(event.dataTransfer.getData('text/plain'));
    saveBatch(items);
  });
  document.addEventListener('paste', event => {
    const withinRobot = widget.contains(document.activeElement);
    const withinComposer = composer.contains(document.activeElement);
    if (!withinRobot && !withinComposer) return;
    const files = Array.from(event.clipboardData?.files || []);
    if (files.length) { event.preventDefault(); saveBatch(fileItems(files)); return; }
    if (document.activeElement === $('paste-input')) return;
    const text = event.clipboardData?.getData('text/plain');
    if (text) { event.preventDefault(); saveBatch(textItems(text)); }
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (!composer.hidden) closeComposer();
      else if (!board.hidden && view === 'detail') setView(returnView);
      else if (!board.hidden) closeBoard();
    }
    if (event.metaKey && event.altKey && event.key.toLowerCase() === 'd') { event.preventDefault(); bodyButton.focus(); }
    if (event.metaKey && event.key.toLowerCase() === 'o' && widget.contains(document.activeElement)) { event.preventDefault(); openBoard('daily'); }
    if (event.metaKey && event.key.toLowerCase() === 'f' && !board.hidden) {
      event.preventDefault(); if (view !== 'daily') setView('daily');
      searchExpanded = true; $('search-toggle').setAttribute('aria-expanded', 'true'); $('search-toggle').setAttribute('aria-pressed', 'true'); $('board-search').hidden = false;
      fitBoard(); $('search-input').focus();
    }
  });
  window.addEventListener('resize', () => { clampWidget(widget.offsetLeft, widget.offsetTop); placeBoard(); placeComposer(); });

  let saved = null;
  try { saved = JSON.parse(localStorage.getItem(positionKey) || 'null'); } catch { /* Local-file preview may deny storage. */ }
  clampWidget(saved?.left ?? desktop.clientWidth - widget.offsetWidth - 18, saved?.top ?? desktop.clientHeight - widget.offsetHeight - 18);
  renderDaily();
  if (params.get('view') === 'daily') openBoard('daily');
})();
