'use strict';
(() => {
  const query = new URLSearchParams(location.search).get('q');
  if (!query) return;
  const input = document.querySelector('#search');
  if (!input) return;
  input.value = query.slice(0, 200);
  input.dispatchEvent(new Event('input', {bubbles:true}));
  const sidebar = document.querySelector('#sidebar');
  sidebar.classList.add('open'); sidebar.inert = false;
  document.querySelector('#menu-toggle').setAttribute('aria-expanded', 'true');
  input.focus();
})();
