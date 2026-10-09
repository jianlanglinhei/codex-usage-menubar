export function onRequest(context) {
  const url = new URL(context.request.url);
  if (url.hostname === 'codex-usage.edgewavelabs.ai') {
    url.protocol = 'https:';
    url.hostname = 'codex-cub.edgewavelabs.ai';
    url.port = '';
    // Change only the origin so downloads, update feeds and query strings survive.
    return new Response(null, { status: 301, headers: {
      Location: url.href, 'Cache-Control': 'public, max-age=300',
    } });
  }
  return context.next();
}
