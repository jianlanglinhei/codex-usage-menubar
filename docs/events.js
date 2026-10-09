(function () {
  var allowed = ['codex-cub.edgewavelabs.ai', 'codex-usage.edgewavelabs.ai', 'codex-usage-3bp.pages.dev', 'localhost', '127.0.0.1'];
  function track(event, position) {
    if (!allowed.includes(location.hostname) || navigator.doNotTrack === '1' || navigator.globalPrivacyControl) return;
    var body = JSON.stringify({ event: event, position: position, language: document.documentElement.dataset.lang === 'zh' ? 'zh' : 'en' });
    try {
      if (navigator.sendBeacon && navigator.sendBeacon('/api/events', new Blob([body], { type: 'application/json' }))) return;
      fetch('/api/events', { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: body, keepalive: true, credentials: 'omit' }).catch(function () {});
    } catch (_) { /* Analytics must not block navigation or copying. */ }
  }
  window.trackUsageEvent = track;
  document.addEventListener('click', function (event) {
    var link = event.target.closest('a[data-event]');
    if (link) track(link.dataset.event, link.dataset.position);
  });
  document.addEventListener('auxclick', function (event) {
    var link = event.target.closest('a[data-event]');
    if (event.button === 1 && link) track(link.dataset.event, link.dataset.position);
  });
})();
