'use strict';
import { detectPlatform } from './platform.mjs';
(() => {
  const menu = document.querySelector('.menu-toggle');
  const nav = document.querySelector('#navigation');
  function closeMenu() { nav?.classList.remove('open'); menu?.setAttribute('aria-expanded', 'false'); menu?.setAttribute('aria-label', 'Navigation öffnen'); }
  menu?.addEventListener('click', () => { const open = nav.classList.toggle('open'); menu.setAttribute('aria-expanded', String(open)); menu.setAttribute('aria-label', open ? 'Navigation schließen' : 'Navigation öffnen'); });
  nav?.addEventListener('click', event => { if (event.target.closest('a')) closeMenu(); });
  addEventListener('keydown', event => { if (event.key === 'Escape' && nav?.classList.contains('open')) { closeMenu(); menu.focus(); } });
  const tabs = [...document.querySelectorAll('[data-platform]')];
  function selectPlatform(id, reason = 'manual') {
    if (!tabs.some(tab => tab.dataset.platform === id)) return;
    for (const tab of tabs) {
      const selected = tab.dataset.platform === id;
      tab.setAttribute('aria-selected', String(selected)); tab.tabIndex = selected ? 0 : -1;
      document.getElementById(tab.dataset.platform).hidden = !selected;
    }
    const notice = document.querySelector('#platform-choice');
    const label = tabs.find(tab => tab.dataset.platform === id).textContent.trim();
    if (notice) notice.textContent = reason === 'detected'
      ? `Für dich vorausgewählt: ${label}. Du kannst jederzeit wechseln.`
      : reason === 'fallback' ? 'Wähle dein System. Du kannst jederzeit zwischen den Plattformen wechseln.'
      : `Ausgewählt: ${label}. Du kannst jederzeit wechseln.`;
  }
  for (const tab of tabs) tab.addEventListener('click', () => selectPlatform(tab.dataset.platform));
  function tabKeys(event, group, select) {
    let index = group.indexOf(event.currentTarget);
    if (event.key === 'ArrowRight') index = (index + 1) % group.length;
    else if (event.key === 'ArrowLeft') index = (index - 1 + group.length) % group.length;
    else if (event.key === 'Home') index = 0;
    else if (event.key === 'End') index = group.length - 1;
    else return;
    event.preventDefault(); select(group[index]); group[index].focus();
  }
  for (const tab of tabs) tab.addEventListener('keydown', event => tabKeys(event, tabs, item => selectPlatform(item.dataset.platform)));
  for (const link of document.querySelectorAll('[data-platform-link]')) link.addEventListener('click', () => selectPlatform(link.dataset.platformLink));
  const fromHash = () => selectPlatform(location.hash.slice(1));
  if (tabs.length) {
    const detected = detectPlatform(navigator);
    selectPlatform(detected || 'windows', detected ? 'detected' : 'fallback');
    // An explicit platform link takes precedence over automatic detection.
    fromHash();
    addEventListener('hashchange', fromHash);
  }
  const previews = {
    overview: {src:'/assets/desktop-light.png', alt:'OpenCommander im hellen Design mit zwei Dateibereichen.', caption:'Hell oder dunkel: dein Arbeitsplatz, deine Darstellung. Abbildung: Linux.'},
    transfer: {src:'/assets/transfers.png', alt:'Die Übertragungsansicht mit Fortschritt und Steuerelementen für Datei-Aufträge.', caption:'Fortschritt, Pause und Fortsetzen bleiben sichtbar. Abbildung: Linux.'},
    compare: {src:'/assets/compare.png', alt:'OpenCommander vergleicht zwei Verzeichnisse und zeigt ihre Unterschiede.', caption:'Unterschiede erkennen, bevor du Dateien organisierst. Abbildung: Linux.'}
  };
  const previewTabs = [...document.querySelectorAll('[data-preview]')];
  function selectPreview(tab) {
    const data = previews[tab.dataset.preview];
    if (!data) return;
    for (const item of previewTabs) { item.setAttribute('aria-selected', String(item === tab)); item.tabIndex = item === tab ? 0 : -1; }
    const image = document.querySelector('#preview-image'); image.src = data.src; image.alt = data.alt;
    document.querySelector('#preview-link').href = data.src;
    document.querySelector('#preview-caption').textContent = data.caption;
    document.querySelector('#preview-panel').setAttribute('aria-labelledby', tab.id);
  }
  for (const tab of previewTabs) { tab.addEventListener('click', () => selectPreview(tab)); tab.addEventListener('keydown', event => tabKeys(event, previewTabs, selectPreview)); }
})();
