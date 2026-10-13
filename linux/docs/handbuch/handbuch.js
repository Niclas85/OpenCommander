'use strict';
(() => {
  const root = document.documentElement;
  const themeButton = document.querySelector('#theme-toggle');
  const updateTheme = theme => {
    root.dataset.theme = theme;
    themeButton.setAttribute('aria-label', theme === 'dark' ? 'Helle Darstellung einschalten' : 'Dunkle Darstellung einschalten');
    themeButton.setAttribute('aria-pressed', String(theme === 'dark'));
  };
  let preference;
  try { preference = localStorage.getItem('opencommander-handbook-theme'); } catch (_) { /* file:// storage may be disabled */ }
  updateTheme(preference === 'dark' ? 'dark' : 'light');
  themeButton.addEventListener('click', () => {
    const theme = root.dataset.theme === 'dark' ? 'light' : 'dark';
    updateTheme(theme);
    try { localStorage.setItem('opencommander-handbook-theme', theme); } catch (_) { /* Optional persistence. */ }
  });
  const sidebar = document.querySelector('#sidebar');
  const menu = document.querySelector('#menu-toggle');
  function syncMenu() { sidebar.inert = innerWidth <= 850 && !sidebar.classList.contains('open'); }
  function closeMenu() { sidebar.classList.remove('open'); menu.setAttribute('aria-expanded', 'false'); syncMenu(); }
  menu.addEventListener('click', () => { menu.setAttribute('aria-expanded', String(sidebar.classList.toggle('open'))); syncMenu(); });
  addEventListener('resize', syncMenu); syncMenu();
  document.querySelector('main').addEventListener('click', closeMenu);
  sidebar.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
  const chapters = [...document.querySelectorAll('.chapter')];
  const nav = sidebar.querySelector('nav');
  const links = [...nav.querySelectorAll('a')];
  const normalize = value => value.normalize('NFD').replace(/[\u0300-\u036f]/g, '').toLocaleLowerCase('de');
  const index = chapters.map(chapter => ({id: chapter.id, title: chapter.querySelector('h2').textContent, text: [...chapter.querySelectorAll('h2,h3,p,li,td,summary,dd,dt,figcaption')].map(node => node.textContent).join(' ').replace(/\s+/g, ' ').trim()}));
  const search = document.querySelector('#search');
  const results = document.querySelector('#search-results');
  const status = document.querySelector('#search-status');
  function runSearch() {
    const query = normalize(search.value.trim());
    results.replaceChildren();
    results.hidden = !query;
    nav.hidden = !!query;
    if (!query) { status.textContent = ''; return; }
    const terms = query.split(/\s+/);
    const matches = index.filter(chapter => terms.every(term => normalize(chapter.text).includes(term)));
    status.textContent = matches.length ? `${matches.length} passende Kapitel` : 'Kein Treffer. Probiere z. B. „Pause“, „Cloud“ oder „Papierkorb“.';
    for (const chapter of matches) {
      const link = document.createElement('a');
      link.href = '#' + chapter.id;
      link.textContent = chapter.title;
      const excerpt = document.createElement('small');
      const match = normalize(chapter.text).indexOf(terms[0]);
      const begin = Math.max(0, match - 55);
      excerpt.textContent = (begin ? '… ' : '') + chapter.text.slice(begin, begin + 180) + ' …';
      link.append(excerpt);
      link.addEventListener('click', () => { search.value = ''; runSearch(); });
      results.append(link);
    }
  }
  search.addEventListener('input', runSearch);
  const lightbox = document.querySelector('#lightbox');
  const largeImage = document.querySelector('#lightbox-image');
  const caption = document.querySelector('#lightbox-caption');
  let imageTrigger;
  const zoom = document.querySelector('#zoom-lightbox');
  zoom.addEventListener('click', () => { const original = lightbox.classList.toggle('actual-size'); zoom.setAttribute('aria-pressed', String(original)); zoom.textContent = original ? 'Einpassen' : 'Originalgröße'; });
  document.querySelectorAll('.screenshot').forEach(button => button.addEventListener('click', () => {
    const image = button.querySelector('img');
    imageTrigger = button;
    lightbox.classList.remove('actual-size'); zoom.setAttribute('aria-pressed', 'false'); zoom.textContent = 'Originalgröße';
    largeImage.src = image.currentSrc || image.src;
    largeImage.alt = image.alt;
    caption.textContent = button.closest('figure').querySelector('figcaption').textContent;
    lightbox.showModal();
    document.body.classList.add('no-scroll');
  }));
  document.querySelector('#close-lightbox').addEventListener('click', () => lightbox.close());
  lightbox.addEventListener('click', event => { if (event.target === lightbox) { const r = lightbox.getBoundingClientRect(); if (event.clientX < r.left || event.clientX > r.right || event.clientY < r.top || event.clientY > r.bottom) lightbox.close(); } });
  lightbox.addEventListener('close', () => { document.body.classList.remove('no-scroll'); imageTrigger?.focus({preventScroll:true}); });
  document.addEventListener('keydown', event => {
    const editing = /INPUT|TEXTAREA|SELECT/.test(document.activeElement.tagName) || document.activeElement.isContentEditable;
    if (event.key === '/' && !editing && !lightbox.open) {
      event.preventDefault(); sidebar.classList.add('open'); menu.setAttribute('aria-expanded', 'true'); syncMenu(); search.focus();
    }
    if (event.key === 'Escape' && !lightbox.open) { closeMenu(); if (search.value) { search.value = ''; runSearch(); } }
  });
  let scheduled = false;
  function updatePosition() {
    scheduled = false;
    const denominator = document.documentElement.scrollHeight - innerHeight;
    document.querySelector('.reading-progress').style.width = (denominator > 0 ? 100 * scrollY / denominator : 0) + '%';
    let active;
    for (const chapter of chapters) { if (chapter.getBoundingClientRect().top <= 160) active = chapter.id; else break; }
    for (const link of links) {
      if (link.hash === '#' + active) link.setAttribute('aria-current', 'true');
      else link.removeAttribute('aria-current');
    }
  }
  addEventListener('scroll', () => { if (!scheduled) { scheduled = true; requestAnimationFrame(updatePosition); } }, {passive:true});
  addEventListener('resize', updatePosition);
  updatePosition();
  let originalDetails = [];
  addEventListener('beforeprint', () => { originalDetails = [...document.querySelectorAll('details')].map(item => [item, item.open]); for (const [item] of originalDetails) item.open = true; });
  addEventListener('afterprint', () => { for (const [item, open] of originalDetails) item.open = open; });
  document.querySelector('#print-button').addEventListener('click', () => window.print());
})();
