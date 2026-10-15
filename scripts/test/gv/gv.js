// Google Voice web (browser tab signed in as /u/0, CDP :9222) over raw CDP. `send` sends a real SMS.
// node --experimental-websocket gv.js <tabId> send <digits> <text>   -> new message to <digits>
// node --experimental-websocket gv.js <tabId> thread                 -> last 40 text lines of the page (open the thread first)
const fs = require('fs');
const sleep = ms => new Promise(r => setTimeout(r, ms));
(async () => {
  const [tab, cmd, num, text] = process.argv.slice(2);
  const tabs = await (await fetch('http://127.0.0.1:9222/json/list')).json();
  const t = tabs.find(x => x.id === tab); if (!t) throw new Error('no tab');
  const ws = new WebSocket(t.webSocketDebuggerUrl); let n = 0; const pend = {};
  ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pend[d.id]) { pend[d.id](d); delete pend[d.id]; } };
  await new Promise(r => ws.onopen = r);
  const call = (method, params = {}) => new Promise(r => { const id = ++n; pend[id] = r; ws.send(JSON.stringify({ id, method, params })); });
  const ev = async js => (await call('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true })).result?.result?.value;
  const key = async k => { for (const type of ['keyDown', 'keyUp']) await call('Input.dispatchKeyEvent', { type, key: k, code: k, windowsVirtualKeyCode: 13, nativeVirtualKeyCode: 13 }); };
  const focus = async sel => ev(`(()=>{const e=document.querySelector(${JSON.stringify(sel)}); if(!e) return false; e.focus(); e.click(); return true})()`);
  if (cmd === 'send') {
    await ev(`location.href='https://voice.google.com/u/0/messages'`); await sleep(5000);
    await ev(`document.querySelector('[aria-label="Send new message"]').click()`); await sleep(2000);
    if (!await focus('input[placeholder="Type a name or phone number"]')) throw new Error('no recipient input');
    await call('Input.insertText', { text: num }); await sleep(2000);
    if (!await ev(`(()=>{const b=document.querySelector('button.send-to-button'); if(!b) return false; b.click(); return true})()`)) throw new Error('no Send to button');
    await sleep(2500);
    if (!await focus('textarea[placeholder="Type a message"]')) throw new Error('no message box');
    await call('Input.insertText', { text }); await sleep(800);
    const clicked = await ev(`(()=>{const b=document.querySelector('button[aria-label="Send message"]'); if(!b||b.disabled) return false; b.click(); return true})()`);
    await sleep(3000);
    console.log(clicked ? 'SENT' : 'send button missing/disabled');
  } else if (cmd === 'thread') {
    const tail = await ev(`document.body.innerText.split('\\n').filter(s=>s.trim()).slice(-40).join('\\n')`);
    console.log(tail);
  }
  process.exit(0);
})().catch(e => { console.error('ERR ' + e.message); process.exit(1); });
