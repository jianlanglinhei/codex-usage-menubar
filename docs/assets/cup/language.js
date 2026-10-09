(() => {
  let saved;
  try { saved = localStorage.getItem('lang'); } catch (_) {}
  let lang = ['zh', 'en'].includes(saved) ? saved : ((navigator.languages?.[0] || navigator.language).toLowerCase().startsWith('zh') ? 'zh' : 'en');
  const button = document.getElementById('lang-toggle');
  function apply() {
    document.documentElement.dataset.lang = lang;
    document.documentElement.lang = lang === 'zh' ? 'zh-Hans' : 'en';
    document.title = lang === 'zh' ? 'Codex Cub · 你的 Codex，还剩几口？' : 'Codex Cub · How many sips left?';
    button.textContent = lang === 'zh' ? 'EN' : '中文';
    document.querySelectorAll('[data-label-zh]').forEach(el=>el.setAttribute('aria-label',el.dataset[lang==='zh'?'labelZh':'labelEn']));
 document.querySelectorAll('[data-alt-zh]').forEach(el=>el.alt=el.dataset[lang==='zh'?'altZh':'altEn']);
 document.dispatchEvent(new Event('languagechange'));
  }
  button.addEventListener('click', () => {
    lang = lang === 'zh' ? 'en' : 'zh';
    try { localStorage.setItem('lang', lang); } catch (_) {}
    apply();
  });
  apply();
})();
