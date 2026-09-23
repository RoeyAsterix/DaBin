(() => {
  const desktop = document.getElementById('desktop');
  const widget = document.getElementById('widget');
  const grip = document.getElementById('widget-grip');
  const captureButton = document.getElementById('widget-capture');
  const pasteButton = document.getElementById('widget-paste');
  const todayButton = document.getElementById('widget-today');
  const robotStatus = document.getElementById('robot-status');
  const composer = document.getElementById('composer');
  const board = document.getElementById('board');
  const toast = document.getElementById('toast');
  const dayInput = document.getElementById('date-picker');
  const todayDate = new Date();
  const demoToday = `${todayDate.getFullYear()}-${String(todayDate.getMonth() + 1).padStart(2, '0')}-${String(todayDate.getDate()).padStart(2, '0')}`;
  const previousDate = new Date(`${demoToday}T12:00:00`);
  previousDate.setDate(previousDate.getDate() - 1);
  const demoYesterday = `${previousDate.getFullYear()}-${String(previousDate.getMonth() + 1).padStart(2, '0')}-${String(previousDate.getDate()).padStart(2, '0')}`;
  const reminderDate = new Date(`${demoToday}T12:00:00`);
  reminderDate.setDate(reminderDate.getDate() + 2);
  const demoReminder = `${reminderDate.getFullYear()}-${String(reminderDate.getMonth() + 1).padStart(2, '0')}-${String(reminderDate.getDate()).padStart(2, '0')}T09:00`;
  const entries = [
    { id: 'v1', day: demoToday, time: '12:04', kind: 'video', title: 'Studio walkthrough.mov', description: 'A quick visual record of the morning review · 1:18', source: 'Local file', comment: '', reminder: '', original: '' },
    { id: 'l1', day: demoToday, time: '11:36', kind: 'link', title: 'Making space for creative work', description: 'A short read about protecting time for ideas.', source: 'journal.example', comment: 'Come back to this idea on Friday.', reminder: '', original: 'https://journal.example/creative-work' },
    { id: 'i1', day: demoToday, time: '10:14', kind: 'image', title: 'Color study.png', description: 'Image · 2.4 MB', source: 'Local file', comment: '', reminder: '', original: '' },
    { id: 'p1', day: demoToday, time: '09:42', kind: 'pdf', title: 'Proposal v3.pdf', description: 'PDF document · 8 pages', source: 'Local file', comment: 'Review the final page.', reminder: demoReminder, original: '' },
    { id: 'a1', day: demoToday, time: '08:55', kind: 'ai', title: 'Poster-final.ai', description: 'Adobe Illustrator file · 18 MB', source: 'Local file', comment: '', reminder: '', original: '' },
    { id: 't1', day: demoYesterday, time: '15:22', kind: 'text', title: 'Look up pottery classes', description: 'A thought pasted before leaving work.', source: 'Pasted text', comment: '', reminder: '', original: '' }
  ];

  let activeDate = demoToday;
  let activeFilter = 'all';
  let currentView = 'daily';
  let returnView = 'daily';
  let activeItemId = null;
  let highlightedId = null;
  let toastTimer = null;
  let digestTimer = null;
  let captureClickTimer = null;
  let dragState = null;

  const escapeHtml = value => String(value ?? '').replace(/[&<>"']/g, char => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' })[char]);
  const niceDate = value => new Date(`${value}T12:00:00`).toLocaleDateString('en-US', { weekday: 'long', day: 'numeric', month: 'long' });
  const shortDate = value => new Date(`${value}T12:00:00`).toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
  const currentTime = () => new Date().toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit' });
  const findItem = id => entries.find(item => item.id === id);
  const groupFor = item => item.kind === 'link' ? 'links' : ['image', 'video'].includes(item.kind) ? 'media' : ['pdf', 'document', 'ai', 'file'].includes(item.kind) ? 'files' : 'other';
  const extensionFor = name => (name.split('.').pop() || '').toLowerCase();

  function clampWidget(left, top) {
    const minTop = 42;
    const maxLeft = Math.max(12, desktop.clientWidth - widget.offsetWidth - 12);
    const maxTop = Math.max(minTop, desktop.clientHeight - widget.offsetHeight - 16);
    widget.style.left = `${Math.min(Math.max(12, left), maxLeft)}px`;
    widget.style.top = `${Math.min(Math.max(minTop, top), maxTop)}px`;
    positionPanels();
  }

  function placePanel(panel) {
    if (panel.hidden) return;
    const narrow = desktop.clientWidth < 680;
    const width = panel.offsetWidth;
    const height = panel.offsetHeight;
    let left;
    let top;
    if (narrow) {
      left = Math.max(14, (desktop.clientWidth - width) / 2);
      if (panel === board && widget.offsetTop + widget.offsetHeight + height + 32 > desktop.clientHeight) {
        widget.style.top = '48px';
        widget.style.left = `${Math.max(12, Math.round((desktop.clientWidth - widget.offsetWidth) / 2))}px`;
      }
      const below = widget.offsetTop + widget.offsetHeight + 12;
      const above = widget.offsetTop - height - 12;
      top = below + height + 20 <= desktop.clientHeight ? below : above >= 43 ? above : Math.max(43, (desktop.clientHeight - height) / 2);
    } else {
      const right = widget.offsetLeft + widget.offsetWidth + 12;
      const leftSide = widget.offsetLeft - width - 12;
      left = right + width + 14 <= desktop.clientWidth ? right : leftSide >= 14 ? leftSide : Math.max(14, desktop.clientWidth - width - 14);
      top = panel === composer ? widget.offsetTop : widget.offsetTop - 110;
    }
    panel.style.left = `${Math.min(Math.max(14, left), Math.max(14, desktop.clientWidth - width - 14))}px`;
    panel.style.top = `${Math.min(Math.max(43, top), Math.max(43, desktop.clientHeight - height - 18))}px`;
  }

  function positionPanels() {
    placePanel(composer);
    placePanel(board);
  }

  function initializePosition() {
    let saved = null;
    try { saved = JSON.parse(localStorage.getItem('dabin-widget-position') || 'null'); } catch { /* Local files may not support storage. */ }
    if (saved?.compact) widget.classList.add('compact');
    const left = saved?.left ?? Math.max(20, Math.round(desktop.clientWidth * 0.18));
    const top = saved?.top ?? 215;
    clampWidget(left, top);
  }

  function rememberPosition() {
    try { localStorage.setItem('dabin-widget-position', JSON.stringify({ left: widget.offsetLeft, top: widget.offsetTop, compact: widget.classList.contains('compact') })); } catch { /* Prototype remains usable without storage. */ }
  }

  function showToast(message, itemId = null) {
    clearTimeout(toastTimer);
    toast.innerHTML = `<span>${escapeHtml(message)}</span>${itemId ? '<button type="button" id="toast-view">View</button>' : ''}`;
    toast.hidden = false;
    if (itemId) {
      toast.querySelector('#toast-view').addEventListener('click', () => {
        const item = findItem(itemId);
        if (!item) return;
        activeDate = item.day;
        activeFilter = 'all';
        highlightedId = item.id;
        setBoardView('daily');
        openBoard();
        toast.hidden = true;
      });
    }
    toastTimer = setTimeout(() => { toast.hidden = true; }, 3500);
  }

  function digestCapture() {
    clearTimeout(digestTimer);
    widget.classList.remove('drag-over', 'digesting');
    robotStatus.textContent = 'Saved to today';
    void widget.offsetWidth;
    widget.classList.add('digesting');
    digestTimer = setTimeout(() => {
      widget.classList.remove('digesting');
      robotStatus.textContent = 'Drop anything';
    }, 900);
  }

  function previewMarkup(item, large = false) {
    const kind = ['link', 'image', 'video', 'pdf', 'ai', 'text'].includes(item.kind) ? item.kind : 'file';
    const label = kind === 'link' ? escapeHtml(item.source.replace(/^www\./, '').split('.')[0].toUpperCase()) : '';
    return `<span class="${large ? 'detail-art' : 'card-thumb'} ${kind}" aria-hidden="true">${label}</span>`;
  }

  function cardMarkup(item) {
    const indicators = [item.comment ? '<span class="card-chip">Comment</span>' : '', item.reminder ? `<span class="card-chip">Remind ${escapeHtml(shortDate(item.reminder.slice(0, 10)))}</span>` : ''].join('');
    return `<button type="button" class="capture-card${highlightedId === item.id ? ' selected' : ''}" data-item-id="${escapeHtml(item.id)}" aria-label="${escapeHtml(item.title)}, ${escapeHtml(item.kind)}, captured at ${escapeHtml(item.time)}">${previewMarkup(item)}<span class="card-copy"><span class="card-topline"><strong>${escapeHtml(item.title)}</strong><time>${escapeHtml(item.time)}</time></span><span class="card-description">${escapeHtml(item.description)}</span><span class="card-footer">${indicators}</span></span></button>`;
  }

  function renderDaily() {
    dayInput.value = activeDate;
    document.getElementById('date-label').textContent = niceDate(activeDate);
    document.querySelectorAll('.filter-button').forEach(button => button.setAttribute('aria-pressed', button.dataset.filter === activeFilter ? 'true' : 'false'));
    const items = entries.filter(item => item.day === activeDate && (activeFilter === 'all' || groupFor(item) === activeFilter)).sort((a, b) => b.time.localeCompare(a.time));
    const list = document.getElementById('card-list');
    if (items.length) list.innerHTML = items.map(cardMarkup).join('');
    else {
      const label = activeFilter === 'all' ? 'Nothing captured on this day' : `No ${activeFilter[0].toUpperCase() + activeFilter.slice(1)} captured on this day`;
      list.innerHTML = `<div class="empty-state"><div><strong>${label}</strong><span>${activeFilter === 'all' ? 'Drop or paste something into DaBin to start.' : 'Choose All to see every item from this day.'}</span></div></div>`;
    }
    document.getElementById('today-count').textContent = String(entries.filter(item => item.day === demoToday).length).padStart(2, '0');
  }

  function renderReminders() {
    const list = document.getElementById('reminders-list');
    const items = entries.filter(item => item.reminder).sort((a, b) => a.reminder.localeCompare(b.reminder));
    list.innerHTML = items.length ? items.map(item => `<div class="reminder-date">${escapeHtml(niceDate(item.reminder.slice(0, 10)))}</div>${cardMarkup(item)}`).join('') : '<div class="empty-state"><div><strong>No reminders set</strong><span>Add one from any card when you want to revisit it.</span></div></div>';
  }

  function renderDetail() {
    const item = findItem(activeItemId);
    if (!item) return;
    document.getElementById('detail-preview').innerHTML = previewMarkup(item, true);
    document.getElementById('detail-kind').textContent = item.kind === 'ai' ? 'Illustrator file' : item.kind[0].toUpperCase() + item.kind.slice(1);
    document.getElementById('detail-captured').textContent = `${niceDate(item.day)} · ${item.time}`;
    document.getElementById('detail-title').textContent = item.title;
    document.getElementById('detail-description').textContent = item.description;
    document.getElementById('comment-input').value = item.comment;
    document.getElementById('reminder-input').value = item.reminder;
  }

  function setBoardView(view) {
    currentView = view;
    document.getElementById('daily-view').hidden = view !== 'daily';
    document.getElementById('detail-view').hidden = view !== 'detail';
    document.getElementById('reminders-view').hidden = view !== 'reminders';
    document.getElementById('board-title').textContent = view === 'reminders' ? 'Reminders' : view === 'detail' ? 'Captured item' : 'Daily board';
    document.getElementById('reminders-toggle').setAttribute('aria-label', view === 'reminders' ? 'Show Daily board' : 'Show reminders');
    if (view === 'daily') renderDaily();
    if (view === 'reminders') renderReminders();
    if (view === 'detail') renderDetail();
    positionPanels();
  }

  function openBoard() {
    composer.hidden = true;
    board.hidden = false;
    todayButton.setAttribute('aria-expanded', 'true');
    setBoardView(currentView);
    positionPanels();
  }

  function closeBoard() {
    board.hidden = true;
    todayButton.setAttribute('aria-expanded', 'false');
    todayButton.focus();
  }

  function openComposer() {
    if (widget.classList.contains('compact')) {
      widget.classList.remove('compact');
      rememberPosition();
    }
    board.hidden = true;
    todayButton.setAttribute('aria-expanded', 'false');
    composer.hidden = false;
    positionPanels();
    document.getElementById('paste-input').focus();
  }

  function closeComposer() {
    composer.hidden = true;
    captureButton.focus();
  }

  function addItem(data) {
    const item = {
      id: `new-${Date.now()}-${Math.random().toString(36).slice(2, 7)}`,
      day: demoToday,
      time: currentTime(),
      kind: data.kind,
      title: data.title,
      description: data.description,
      source: data.source,
      comment: '',
      reminder: '',
      original: data.original || ''
    };
    entries.push(item);
    activeDate = demoToday;
    composer.hidden = true;
    renderDaily();
    digestCapture();
    showToast('Added to today', item.id);
    return item;
  }

  function addText(value) {
    const text = String(value || '').trim();
    if (!text) return false;
    if (/^https?:\/\//i.test(text)) {
      let host = text;
      try { host = new URL(text).hostname; } catch { /* Keep readable original. */ }
      addItem({ kind: 'link', title: host, description: 'Link saved. Preview appears here when available.', source: host, original: text });
    } else {
      addItem({ kind: 'text', title: text.slice(0, 56), description: text, source: 'Pasted text', original: text });
    }
    return true;
  }

  function addFiles(files) {
    const array = Array.from(files || []);
    let last = null;
    array.forEach(file => {
      const extension = extensionFor(file.name);
      const kind = file.type.startsWith('image/') ? 'image' : file.type.startsWith('video/') || ['mov', 'mp4', 'm4v', 'webm'].includes(extension) ? 'video' : extension === 'pdf' ? 'pdf' : extension === 'ai' ? 'ai' : ['doc', 'docx', 'pages', 'ppt', 'pptx', 'key'].includes(extension) ? 'document' : 'file';
      last = addItem({ kind, title: file.name, description: `${kind === 'ai' ? 'Illustrator' : kind[0].toUpperCase() + kind.slice(1)} file · ${(file.size / 1048576).toFixed(1)} MB`, source: 'Local file' });
    });
    if (array.length > 1) showToast(`${array.length} items added to today`, last?.id);
    return !!array.length;
  }

  grip.addEventListener('pointerdown', event => {
    if (event.button !== 0) return;
    event.preventDefault();
    grip.setPointerCapture(event.pointerId);
    dragState = { x: event.clientX, y: event.clientY, left: widget.offsetLeft, top: widget.offsetTop };
  });
  grip.addEventListener('pointermove', event => {
    if (!dragState) return;
    clampWidget(dragState.left + event.clientX - dragState.x, dragState.top + event.clientY - dragState.y);
  });
  grip.addEventListener('pointerup', () => { if (dragState) rememberPosition(); dragState = null; });
  grip.addEventListener('pointercancel', () => { dragState = null; });
  grip.addEventListener('keydown', event => {
    const step = event.shiftKey ? 30 : 10;
    const move = { ArrowLeft: [-step, 0], ArrowRight: [step, 0], ArrowUp: [0, -step], ArrowDown: [0, step] }[event.key];
    if (!move) return;
    event.preventDefault();
    clampWidget(widget.offsetLeft + move[0], widget.offsetTop + move[1]);
    rememberPosition();
  });

  captureButton.addEventListener('click', event => {
    clearTimeout(captureClickTimer);
    if (event.detail >= 2) return;
    if (event.detail === 0) { openComposer(); return; }
    captureClickTimer = setTimeout(openComposer, 400);
  });
  captureButton.addEventListener('dblclick', event => {
    event.preventDefault();
    clearTimeout(captureClickTimer);
    setBoardView('daily');
    openBoard();
  });
  pasteButton.addEventListener('click', openComposer);
  todayButton.addEventListener('click', () => { if (board.hidden) { setBoardView('daily'); openBoard(); } else closeBoard(); });
  document.getElementById('composer-close').addEventListener('click', closeComposer);
  document.getElementById('board-close').addEventListener('click', closeBoard);
  document.getElementById('save-paste').addEventListener('click', () => { if (addText(document.getElementById('paste-input').value)) document.getElementById('paste-input').value = ''; else showToast('Paste something first'); });
  document.getElementById('paste-input').addEventListener('keydown', event => { if (event.key === 'Enter' && !event.shiftKey) { event.preventDefault(); document.getElementById('save-paste').click(); } });

  document.getElementById('previous-day').addEventListener('click', () => shiftDate(-1));
  document.getElementById('next-day').addEventListener('click', () => shiftDate(1));
  dayInput.addEventListener('change', () => { activeDate = dayInput.value || demoToday; highlightedId = null; renderDaily(); });
  function shiftDate(delta) {
    const day = new Date(`${activeDate}T12:00:00`);
    day.setDate(day.getDate() + delta);
    activeDate = `${day.getFullYear()}-${String(day.getMonth() + 1).padStart(2, '0')}-${String(day.getDate()).padStart(2, '0')}`;
    highlightedId = null;
    renderDaily();
  }

  document.getElementById('filter-row').addEventListener('click', event => {
    const button = event.target.closest('[data-filter]');
    if (!button) return;
    activeFilter = button.dataset.filter;
    highlightedId = null;
    renderDaily();
  });

  function handleCardClick(event) {
    const button = event.target.closest('[data-item-id]');
    if (!button) return;
    activeItemId = button.dataset.itemId;
    returnView = currentView;
    setBoardView('detail');
  }
  document.getElementById('card-list').addEventListener('click', handleCardClick);
  document.getElementById('reminders-list').addEventListener('click', handleCardClick);
  document.getElementById('detail-back').addEventListener('click', () => setBoardView(returnView));
  document.getElementById('reminders-toggle').addEventListener('click', () => setBoardView(currentView === 'reminders' ? 'daily' : 'reminders'));
  document.getElementById('compact-toggle').addEventListener('click', () => {
    widget.classList.toggle('compact');
    const compact = widget.classList.contains('compact');
    document.getElementById('compact-toggle').setAttribute('aria-label', compact ? 'Expand widget' : 'Switch to compact widget');
    document.getElementById('compact-toggle').title = compact ? 'Expand widget' : 'Compact widget';
    clampWidget(widget.offsetLeft, widget.offsetTop);
    rememberPosition();
  });
  document.getElementById('clear-reminder').addEventListener('click', () => { document.getElementById('reminder-input').value = ''; });
  document.getElementById('save-detail').addEventListener('click', () => {
    const item = findItem(activeItemId);
    if (!item) return;
    item.comment = document.getElementById('comment-input').value.trim();
    item.reminder = document.getElementById('reminder-input').value;
    setBoardView(returnView);
    showToast('Card updated');
  });
  document.getElementById('open-original').addEventListener('click', () => showToast('Original opens here in the finished app'));

  widget.addEventListener('dragover', event => { event.preventDefault(); widget.classList.add('drag-over'); robotStatus.textContent = 'Release to feed me'; });
  widget.addEventListener('dragleave', event => { if (!widget.contains(event.relatedTarget)) { widget.classList.remove('drag-over'); robotStatus.textContent = 'Drop anything'; } });
  widget.addEventListener('drop', event => {
    event.preventDefault();
    widget.classList.remove('drag-over');
    robotStatus.textContent = 'Drop anything';
    if (event.dataTransfer.files.length) addFiles(event.dataTransfer.files);
    else if (!addText(event.dataTransfer.getData('text/uri-list') || event.dataTransfer.getData('text/plain'))) showToast('This item did not include readable data');
  });
  document.addEventListener('paste', event => {
    const withinDaBin = widget.contains(document.activeElement) || composer.contains(document.activeElement);
    if (!withinDaBin) return;
    const files = Array.from(event.clipboardData?.files || []);
    if (files.length) { event.preventDefault(); addFiles(files); return; }
    if (document.activeElement === document.getElementById('paste-input')) return;
    const value = event.clipboardData?.getData('text/plain');
    if (value) { event.preventDefault(); addText(value); }
  });
  document.addEventListener('keydown', event => {
    if (event.key === 'Escape') {
      if (!composer.hidden) closeComposer();
      else if (!board.hidden && currentView === 'detail') setBoardView(returnView);
      else if (!board.hidden) closeBoard();
    }
    if (event.metaKey && event.altKey && event.key.toLowerCase() === 'd') { event.preventDefault(); captureButton.focus(); }
    if (event.metaKey && event.key.toLowerCase() === 'o' && widget.contains(document.activeElement)) { event.preventDefault(); setBoardView('daily'); openBoard(); }
  });
  window.addEventListener('resize', () => clampWidget(widget.offsetLeft, widget.offsetTop));

  initializePosition();
  renderDaily();
  document.querySelector('.menu-bar span:last-child').textContent = niceDate(demoToday);
})();
