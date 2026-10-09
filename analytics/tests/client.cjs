const { readFileSync } = require('node:fs');
const vm = require('node:vm');
const assert = require('node:assert/strict');
const src = readFileSync('docs/events.js', 'utf8');
function load(extra = {}, host = 'localhost') {
 const sent = [], listeners = {};
 const c = { Blob, location: {hostname: host}, navigator: {sendBeacon: (url, body) => {sent.push({url, body});return true;}, ...extra}, document: {documentElement:{dataset:{lang:'zh'}}, addEventListener:(k,v)=>listeners[k]=v}, window:{}, fetch:()=>Promise.reject(new Error('offline')) };
 vm.runInNewContext(src,c);return {sent,listeners,track:c.window.trackUsageEvent};
}
(async()=>{
 const c=load();
 c.listeners.click({target:{closest:()=>({dataset:{event:'install_click',position:'hero'}})}});
 assert.equal(c.sent.length,1);assert.deepEqual(JSON.parse(await c.sent[0].body.text()),{event:'install_click',position:'hero',language:'zh'});
 c.track('install_copy','install');assert.equal(c.sent.length,2);
 for(const flags of [{doNotTrack:'1'},{globalPrivacyControl:true}]){const c=load(flags);c.track('source_click','hero');assert.equal(c.sent.length,0);}
 const preview=load({},'preview.codex-usage-3bp.pages.dev');preview.track('install_click','hero');assert.equal(preview.sent.length,0);
 const failed=load({sendBeacon:()=>{throw Error('blocked')}});assert.doesNotThrow(()=>failed.track('source_click','hero'));
 const fresh=load({},'codex-cub.edgewavelabs.ai');fresh.track('install_click','download');assert.equal(fresh.sent.length,1);
 const old=load({},'codex-usage.edgewavelabs.ai');old.track('install_click','download');assert.equal(old.sent.length,1);
 console.log('PASS: click payload, new/old domains, DNT/GPC, preview exclusion, analytics failure isolation');
})();
