// Send an image + caption in the Google Voice thread that is OPEN in the given browser tab (open it first: click
// the LP3's conversation in /u/0/messages). Uses CDP DOM.setFileInputFiles on GV's hidden image input. Sends a real
// MMS. Set SKIP_ATTACH=1 to send only the caption when the image is already attached.
// node --no-warnings --experimental-websocket gv-mms.js <tabId> <abs image path> <caption>
const sleep = ms => new Promise(r => setTimeout(r, ms));
const open = ws => new Promise((r, j) => {
  const t = setTimeout(() => j(new Error('CDP WebSocket did not open in 10 s')), 10000);
  ws.onopen = () => { clearTimeout(t); r(); };
  ws.onerror = () => { clearTimeout(t); j(new Error('CDP WebSocket error')); };
});
(async () => {
  const [tabId, file, caption] = process.argv.slice(2);
  const tabs = await (await fetch('http://127.0.0.1:9222/json/list')).json();
  const t = tabs.find(x => x.id === tabId);
  if (!t) throw new Error('no tab ' + tabId);
  const ws = new WebSocket(t.webSocketDebuggerUrl); let n = 0; const pend = {};
  ws.onmessage = m => { const d = JSON.parse(m.data); if (d.id && pend[d.id]) { pend[d.id](d); delete pend[d.id]; } };
  await open(ws);
  const call = (method, params = {}) => new Promise(r => { const id = ++n; pend[id] = r; ws.send(JSON.stringify({ id, method, params })); });
  const ev = async js => (await call('Runtime.evaluate', { expression: js, awaitPromise: true, returnByValue: true })).result?.result?.value;
  const doc = await call('DOM.getDocument', { depth: -1, pierce: true });
  const q = await call('DOM.querySelector', { nodeId: doc.result.root.nodeId, selector: 'input[type=file][accept*="image/png"]' });
  if (!q.result?.nodeId) throw new Error('no image file input (is the thread open?)');
  if (!process.env.SKIP_ATTACH) await call('DOM.setFileInputFiles', { nodeId: q.result.nodeId, files: [file] });
  await sleep(3000);
  if (!await ev(`(()=>{const t=document.querySelector('textarea[placeholder="Add a caption"]'); if(!t) return false; t.focus(); return true})()`)) throw new Error('no message box');
  await call('Input.insertText', { text: caption });
  await sleep(1000);
  const sent = await ev(`(()=>{const b=document.querySelector('button[aria-label="Send message with an attachment"]'); if(!b||b.disabled) return false; b.click(); return true})()`);
  console.log(sent ? 'SENT' : 'send button missing/disabled');
  process.exit(sent ? 0 : 1);
})().catch(e => { console.error('ERR ' + e.message); process.exit(1); });
