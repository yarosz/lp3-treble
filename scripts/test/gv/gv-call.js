// Place a Google Voice web call (browser tab signed in as /u/0, CDP :9222) to <digits>, keep it up to <secs>, then
// hang up. Places a real call: gv-call-lp3.sh passes the LP3's own number. Grants the GV origin microphone access
// through CDP.
// node --experimental-websocket gv-call.js <tabId> <digits> <secs>
const sleep = ms => new Promise(r => setTimeout(r, ms));
const connect = async url => {
  const ws = new WebSocket(url); let n = 0; const pend = {};
  ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pend[d.id]) { pend[d.id](d); delete pend[d.id]; } };
  await new Promise(r => ws.onopen = r);
  return (method, params = {}) => new Promise(r => { const id = ++n; pend[id] = r; ws.send(JSON.stringify({ id, method, params })); });
};
(async () => {
  const [tab, num, secs] = process.argv.slice(2);
  if (!/^\d{10,11}$/.test(num || '')) throw new Error('digits must be a 10-11 digit number');
  const ver = await (await fetch('http://127.0.0.1:9222/json/version')).json();
  const browser = await connect(ver.webSocketDebuggerUrl);
  const g = await browser('Browser.grantPermissions', { origin: 'https://voice.google.com', permissions: ['audioCapture'] });
  if (g.error) console.log('grantPermissions: ' + g.error.message);
  const tabs = await (await fetch('http://127.0.0.1:9222/json/list')).json();
  const t = tabs.find(x => x.id === tab); if (!t) throw new Error('no tab');
  const call = await connect(t.webSocketDebuggerUrl);
  const ev = async js => (await call('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true })).result?.result?.value;
  const endBtn = `[...document.querySelectorAll('button')].find(b=>b.offsetParent&&/end call|hang up/i.test(b.getAttribute('aria-label')||''))`;
  const hangup = async () => ev(`(()=>{const b=${endBtn}; if(!b) return false; b.click(); return true})()`);
  await ev(`location.href='https://voice.google.com/u/0/calls'`); await sleep(6000);
  if (!await ev(`(()=>{const e=document.querySelector('input[placeholder="Enter a name or number"]'); if(!e) return false; e.focus(); e.click(); e.select(); return true})()`)) throw new Error("no dial input");
  await call('Input.insertText', { text: num }); await sleep(1500);
  // GV picks the number only on Enter (or a click on the suggestion row).
  for (const type of ['keyDown', 'keyUp']) await call('Input.dispatchKeyEvent', { type, key: 'Enter', code: 'Enter', windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 });
  // Enter on a parsed number places the call; fall back to the call button once it reads "Call ...".
  let up = false;
  for (let i = 0; i < 15 && !up; i++) {
    await sleep(1000);
    up = !!await ev(`!!(${endBtn})`);
    if (!up) await ev(`(()=>{const b=document.querySelector('button.call-button'); if(b&&/^Call /.test(b.getAttribute('aria-label')||'')) b.click()})()`);
  }
  if (!up) { console.log('no end-call button seen; the phone side ends any call'); process.exit(2); }
  console.log(new Date().toTimeString().slice(0, 8) + ' calling');
  const until = Date.now() + Number(secs || 60) * 1000;
  while (Date.now() < until && await ev(`!!(${endBtn})`)) await sleep(1000);
  const still = await hangup();
  console.log(new Date().toTimeString().slice(0, 8) + (still ? ' hung up from GV' : ' call already ended'));
  process.exit(0);
})().catch(e => { console.error('ERR ' + e.message); process.exit(1); });
