/* A local-only illustration; it never reads account data or prediction APIs. */
(() => {
  const reducedMotion = window.matchMedia('(prefers-reduced-motion: reduce)');
  let frame = null;
  let previousTime = null;
  let elapsed = 0;
  let currentValue = 81;
  const tr = (zh, en) => document.documentElement.dataset.lang === "en" ? en : zh;

  function render(value) {
    currentValue = value;
    const whole = Math.round(value);
    const surface = 151 - 104 * value / 100;
    document.querySelectorAll('[data-quota]').forEach(node => { node.textContent = String(whole); });
    document.getElementById('cup-title').textContent = tr(`演示：剩余 ${whole}% 的刻度杯`, `Demo: calibrated cup with ${whole}% remaining`);
    const liquid = document.getElementById('cup-liquid');
    liquid.setAttribute('y', String(surface));
    liquid.setAttribute('height', String(178 - surface));
    document.getElementById('cup-surface').setAttribute('cy', String(surface));
    const mini = document.getElementById('mini-liquid');
    mini.setAttribute('y', String(24 - 17 * value / 100));
    mini.setAttribute('height', String(17 * value / 100));
    document.getElementById('quota-mood').textContent = whole <= 35 ? tr('留给重要的事。', 'Save some for what matters.') : tr('余量充足，继续写。', 'Room for another good idea.');
  }

  function tick(time) {
    frame = null;
    if (reducedMotion.matches || document.hidden) return;
    if (previousTime !== null) elapsed += Math.max(0, Math.min(time - previousTime, 100));
    previousTime = time;
    // A gentle 16-second loop between 81% and 25%, with eased turning points.
    render(53 + 28 * Math.cos(elapsed / 16000 * Math.PI * 2));
    frame = window.requestAnimationFrame(tick);
  }

  function sync() {
    if (frame !== null) window.cancelAnimationFrame(frame);
    frame = null;
    previousTime = null;
    if (reducedMotion.matches) { elapsed = 0; render(81); }
    if (!reducedMotion.matches && !document.hidden) frame = window.requestAnimationFrame(tick);
  }

  reducedMotion.addEventListener('change', sync);
  document.addEventListener('visibilitychange', sync);
  document.addEventListener('languagechange', () => { render(currentValue); sync(); });
  render(81);
  sync();
})();
