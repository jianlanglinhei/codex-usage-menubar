import { readFile } from 'node:fs/promises';
import assert from 'node:assert/strict';
const moduleAt = async path => import('data:text/javascript;base64,' + Buffer.from(await readFile(path)).toString('base64'));
const { onRequest } = await moduleAt('functions/api/events.js');
const { onRequest: redirect } = await moduleAt('functions/_middleware.js');
const writes = [];
const env = { ANALYTICS_DB: { prepare: () => ({bind: (...values) => ({ run: async () => writes.push(values) })}) } };
const host = 'https://codex-cub.edgewavelabs.ai';
function request(headers = {}, body = JSON.stringify({event:'install_click',position:'download',language:'zh'}), url = host) {
  return new Request(url + '/api/events', {method:'POST',headers:{'Content-Type':'application/json',Origin:host,...headers},body});
}
assert.equal((await onRequest({request:request(),env})).status,204);
assert.equal(writes.length,1);
assert.deepEqual(writes[0].slice(1),['install_click','download','zh']);
for (const position of ['hero_download','install_download']) {
  assert.equal((await onRequest({request:request({},JSON.stringify({event:'install_click',position,language:'en'})),env})).status,204);
}
for (const origin of ['null','https://evil.example','https://codex-cub.edgewavelabs.ai.evil.example']) {
 assert.equal((await onRequest({request:request({Origin:origin,Referer:host+'/'}),env})).status,403);
}
let referer = request({Referer:host+'/'});referer.headers.delete('Origin');
assert.equal((await onRequest({request:referer,env})).status,204);
let absent = request();absent.headers.delete('Origin');
assert.equal((await onRequest({request:absent,env})).status,403);
assert.equal((await onRequest({request:request({},'{}'),env})).status,400);
assert.equal((await onRequest({request:request({},'x'.repeat(513)),env})).status,413);
assert.equal((await onRequest({request:request({'Content-Type':'text/plain'}),env})).status,415);
assert.equal((await onRequest({request:request(),env:{}})).status,503);
assert.equal((await onRequest({request:request({},undefined,'https://evil.example'),env})).status,403);
for (const path of ['/', '/downloads/test.zip?x=1&y=%2F', '/appcast.xml', '/api/events', '/unknown/path']) {
 const response = await redirect({request:new Request('https://codex-usage.edgewavelabs.ai'+path),next:()=>{throw Error('must redirect')}});
 assert.equal(response.status,301);
 assert.equal(response.headers.get('Location'),host+path);
}
assert.equal(await redirect({request:new Request(host),next:()=>42}),42);
const html = await readFile('docs/index.html','utf8');
for (const [,event,position] of html.matchAll(/data-event="([^"]+)" data-position="([^"]+)"/g)) {
 assert.equal((await onRequest({request:request({},JSON.stringify({event,position,language:'zh'})),env})).status,204);
}
assert(html.includes('rel="canonical" href="'+host+'/"'));
assert(html.includes('property="og:url" content="'+host+'/"'));
assert((await readFile('docs/robots.txt','utf8')).includes(host+'/sitemap.xml'));
assert((await readFile('docs/sitemap.xml','utf8')).includes('<loc>'+host+'/</loc>'));
console.log('PASS: real button payloads, Origin/Referer checks, malformed/oversized requests, failure handling, redirects and canonical metadata');
