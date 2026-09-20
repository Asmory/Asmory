(() => {
  const qs = (s) => document.querySelector(s);
  const qsa = (s) => [...document.querySelectorAll(s)];

  qsa('[data-copy]').forEach((button) => {
    button.addEventListener('click', async () => {
      const value = button.getAttribute('data-copy');
      try {
        await navigator.clipboard.writeText(value);
        const old = button.textContent;
        button.textContent = 'copied';
        setTimeout(() => button.textContent = old, 1100);
      } catch (_) {
        button.textContent = 'copy failed';
      }
    });
  });

  const list = qs('#package-results');
  if (!list) return;

  const search = qs('#search');
  const arch = qs('#arch');
  const isa = qs('#isa');
  const sort = qs('#sort');
  const count = qs('#result-count');
  let packages = [];

  const chip = (v, hot = false) => `<span class="chip${hot ? ' hot' : ''}">${v}</span>`;
  const render = () => {
    const needle = search.value.trim().toLowerCase();
    let rows = packages.filter((p) => {
      const haystack = `${p.name} ${p.description} ${p.arch} ${p.abi} ${p.isa.join(' ')}`.toLowerCase();
      return (!needle || haystack.includes(needle)) &&
             (!arch.value || p.arch === arch.value) &&
             (!isa.value || p.isa.includes(isa.value));
    });
    if (sort.value === 'downloads') rows.sort((a,b) => b.downloads - a.downloads);
    else if (sort.value === 'recent') rows.sort((a,b) => b.updated.localeCompare(a.updated));
    else rows.sort((a,b) => a.name.localeCompare(b.name));

    count.textContent = `${rows.length} package${rows.length === 1 ? '' : 's'}`;
    list.innerHTML = rows.length ? rows.map((p) => `
      <a class="result" href="${p.href || '#'}">
        <div>
          <div class="result-name">${p.name}</div>
          <div class="result-desc">${p.description}</div>
          <div class="result-meta">${p.version} · ${p.arch} · ${p.object} · ${p.abi} · ${p.license}</div>
        </div>
        <div class="result-right">
          <div class="chips">${p.isa.map((x,i) => chip(x, i === 0)).join('')}</div>
          <div class="result-meta">${p.downloads.toLocaleString()} pulls</div>
        </div>
      </a>`).join('') : '<div class="empty">No compatible symbols found. Try a broader ISA or architecture filter.</div>';
  };

  fetch('/api/v1/packages')
    .then((r) => r.json())
    .then((data) => {
      packages = data.packages || [];
      [search, arch, isa, sort].forEach((el) => el.addEventListener(el === search ? 'input' : 'change', render));
      render();
    })
    .catch(() => {
      list.innerHTML = '<div class="empty">Registry API unavailable.</div>';
    });
})();
