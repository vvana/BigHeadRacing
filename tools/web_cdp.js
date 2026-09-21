// Драйвер Chrome по CDP для замеров веб-сборки (21.09.2026). Chrome запускать так:
//   chrome --remote-debugging-port=9333 --user-data-dir=<НОВАЯ папка = чистый кэш шейдеров>
//          --disable-backgrounding-occluded-windows --disable-renderer-backgrounding --window-size=1600,900
// node tools/web_cdp.js init nav <url> wait <с> click <x> <y> type <txt> keydown <k> keyup <k>
//                      eval <js> shot <файл> burst <n> <шаг_с> <префикс> front (развернуть окно и вывести вперёд)
//      clickrel <доля_ширины> <доля_высоты> — гараж: имя 0.5 0.498, ГОТОВО 0.5 0.596, СТАРТ 0.461 0.931
// ещё: window.__ft ([t, мс кадра]), window.__links (моменты linkProgram — компиляции шейдеров)
// init вешает: window.__logs (console.log с метками времени), window.__long (кадры > 120 мс).
const fs = require('fs');
const INIT = `window.__logs=[];window.__long=[];(function(){const ol=console.log.bind(console);console.log=function(...a){window.__logs.push([Math.round(performance.now()),a.join(' ').slice(0,200)]);ol(...a);};let last=performance.now();function f(t){const d=t-last;if(d>120)window.__long.push([Math.round(last),Math.round(d)]);last=t;requestAnimationFrame(f);}requestAnimationFrame(f);window.__ft=[];let l2=performance.now();function g(t){window.__ft.push([Math.round(t),Math.round(t-l2)]);l2=t;if(window.__ft.length>30000)window.__ft.shift();requestAnimationFrame(g);}requestAnimationFrame(g);window.__links=[];const P=WebGL2RenderingContext.prototype;window.__src=[];const oss=P.shaderSource;P.shaderSource=function(sh,src){try{if(this.getShaderParameter(sh,this.SHADER_TYPE)===this.FRAGMENT_SHADER){let h=0;for(let i=0;i<src.length;i+=7){h=(h*31+src.charCodeAt(i))|0;}const L=src.split('\\n');const mat=L.filter(l=>/^(highp|uniform|int|bool) .*m_[a-z_0-9]+;/.test(l.trim())).map(l=>l.trim().split(' ').pop().replace(';','').replace('m_','')).filter(x=>!/^(albedo|point_size|roughness|metallic_texture_channel|specular|metallic|uv1_scale|uv1_offset|uv2_scale|uv2_offset|texture_albedo|texture_metallic|texture_roughness)$/.test(x)).join(',');const d=L.filter(l=>l.startsWith('#define ')).map(l=>l.slice(8).split(' ')[0]).filter(k=>/^(MODE_|USE_INSTANCING|DISABLE_FOG|ALPHA|RENDER)/.test(k)).join(',');window.__src.push([Math.round(performance.now()),h,src.length,d,mat]);}}catch(e){}return oss.apply(this,arguments);};const o=P.linkProgram;P.linkProgram=function(){window.__links.push(Math.round(performance.now()));return o.apply(this,arguments);};})();`;
(async () => {
  const list = await (await fetch('http://127.0.0.1:9333/json')).json();
  const ws = new WebSocket(list.find(t => t.type === 'page').webSocketDebuggerUrl);
  await new Promise(r => ws.onopen = r);
  let id = 0; const pend = new Map();
  ws.onmessage = e => { const m = JSON.parse(e.data); if (m.id && pend.has(m.id)) { pend.get(m.id)(m); pend.delete(m.id); } };
  const send = (method, params = {}) => new Promise(r => { const i = ++id; pend.set(i, r); ws.send(JSON.stringify({ id: i, method, params })); });
  const sleep = ms => new Promise(r => setTimeout(r, ms));
  const shot = async f => { const r = await send('Page.captureScreenshot', { format: 'jpeg', quality: 50 }); fs.writeFileSync(f, Buffer.from(r.result.data, 'base64')); };
  const a = process.argv.slice(2);
  for (let i = 0; i < a.length;) {
    const c = a[i++];
    if (c === 'init') { await send('Page.enable'); await send('Page.addScriptToEvaluateOnNewDocument', { source: INIT }); }
    else if (c === 'nav') await send('Page.navigate', { url: a[i++] });
    else if (c === 'wait') await sleep(parseFloat(a[i++]) * 1000);
    else if (c === 'click' || c === 'clickrel') { let x = +a[i++], y = +a[i++];
      if (c === 'clickrel') { const r = await send('Runtime.evaluate', { expression: '[innerWidth,innerHeight]', returnByValue: true }); x *= r.result.result.value[0]; y *= r.result.result.value[1]; }
      await send('Input.dispatchMouseEvent', { type: 'mouseMoved', x, y }); await sleep(40); await send('Input.dispatchMouseEvent', { type: 'mousePressed', x, y, button: 'left', clickCount: 1 }); await sleep(60);
      await send('Input.dispatchMouseEvent', { type: 'mouseReleased', x, y, button: 'left', clickCount: 1 }); }
    else if (c === 'type') { for (const ch of a[i++]) { const vk = ch.toUpperCase().charCodeAt(0);
        await send('Input.dispatchKeyEvent', { type: 'keyDown', key: ch, code: 'Key' + ch.toUpperCase(), text: ch, windowsVirtualKeyCode: vk });
        await send('Input.dispatchKeyEvent', { type: 'keyUp', key: ch, code: 'Key' + ch.toUpperCase(), windowsVirtualKeyCode: vk }); await sleep(50); } }
    else if (c === 'keydown' || c === 'keyup') { const k = a[i++];
        await send('Input.dispatchKeyEvent', { type: c === 'keydown' ? 'keyDown' : 'keyUp', key: k, code: 'Key' + k.toUpperCase(), windowsVirtualKeyCode: k.toUpperCase().charCodeAt(0) }); }
    else if (c === 'eval') { const r = await send('Runtime.evaluate', { expression: a[i++], returnByValue: true, awaitPromise: true }); console.log(r.result?.result?.value); }
    else if (c === 'shot') await shot(a[i++]);
    else if (c === 'front') { const w = await send('Browser.getWindowForTarget'); await send('Browser.setWindowBounds', { windowId: w.result.windowId, bounds: { windowState: 'normal' } }); await send('Page.bringToFront'); }
    else if (c === 'burst') { const n = +a[i++], step = parseFloat(a[i++]) * 1000, pre = a[i++];
        for (let k = 0; k < n; k++) { const t = Date.now(); await shot(pre + String(k).padStart(2, '0') + '.jpg'); await sleep(Math.max(0, step - (Date.now() - t))); } }
  }
  ws.close();
})();

