(() => {
  const root = document.documentElement;
  const key = 'asmory-theme';
  const stored = localStorage.getItem(key);
  const system = () => matchMedia('(prefers-color-scheme: light)').matches ? 'light' : 'dark';

  if (stored === 'light' || stored === 'dark') root.dataset.theme = stored;

  const button = document.querySelector('[data-theme-toggle]');
  const refresh = () => {
    const theme = root.dataset.theme || stored || system();
    button?.setAttribute('aria-label', `Switch to ${theme === 'light' ? 'dark' : 'light'} theme`);
    const meta = document.querySelector('meta[name="theme-color"]');
    if (meta) meta.content = theme === 'light' ? '#f5f2ea' : '#080a0d';
  };

  button?.addEventListener('click', () => {
    const current = root.dataset.theme || localStorage.getItem(key) || system();
    const next = current === 'light' ? 'dark' : 'light';
    root.dataset.theme = next;
    localStorage.setItem(key, next);
    refresh();
  });

  refresh();
})();
