// ─── Connection ──────────────────────────────────────
const $ = id => document.getElementById(id);
let ws, reconn, hasControl = false, hasEverControlled = false;
const st = $('status');

function connect() {
  ws = new WebSocket(`ws://${location.host}/ws`);
  ws.onopen = () => { st.textContent = '已连接'; st.className = 'ok'; clearTimeout(reconn) };
  ws.onclose = e => {
    hasControl = false;
    $('approval-overlay').classList.remove('show');
    $('auth-overlay').classList.remove('show');
    if (e.code === 4001) { st.textContent = '已被新设备接管'; st.className = 'err'; return; }
    if (e.code === 4002) {
      const reason = e.reason || '';
      if (reason === 'rejected') { st.textContent = '被拒绝'; st.className = 'err'; }
      else if (reason === 'timeout') { st.textContent = '等待超时'; st.className = 'err'; }
      else if (reason === 'busy') { st.textContent = '已有设备在等待'; st.className = 'err'; }
      return;
    }
    if (e.code === 1000) { st.textContent = '服务已停止'; st.className = 'err'; return; }
    st.textContent = '已断开'; st.className = 'err';
    if (hasEverControlled) reconn = setTimeout(connect, 2000);
  };
  ws.onerror = () => ws.close();
  ws.onmessage = e => {
    let d; try { d = JSON.parse(e.data) } catch { return };
    if (d.a === 'ctrl_ok') {
      hasControl = true; hasEverControlled = true;
      st.textContent = '控制中'; st.className = 'ok';
      $('auth-overlay').classList.remove('show');
    } else if (d.a === 'auth_required') {
      $('auth-overlay').classList.add('show');
      $('auth-pin').value = '';
      $('auth-error').textContent = '';
      setTimeout(() => $('auth-pin').focus(), 100);
    } else if (d.a === 'auth_fail') {
      $('auth-error').textContent = '配对码错误，请重试';
      $('auth-pin').value = '';
      $('auth-pin').focus();
    } else if (d.a === 'wait') {
      hasControl = false;
      if ($('auth-overlay').classList.contains('show')) {
        const modal = $('auth-modal');
        if (d.reason === 'rejected') {
          modal.innerHTML = '<h3>连接被拒绝</h3><p>当前设备拒绝了你的控制请求</p>' +
            '<button onclick="location.reload()" class="auth-result-btn dismiss">返回</button>';
        } else if (d.reason === 'timeout') {
          modal.innerHTML = '<h3>等待超时</h3><p>当前设备未响应</p>' +
            '<button onclick="location.reload()" class="auth-result-btn dismiss">返回</button>';
        } else if (d.reason === 'busy') {
          modal.innerHTML = '<h3>已有设备在等待</h3><p>请稍后再试</p>' +
            '<button onclick="location.reload()" class="auth-result-btn dismiss">返回</button>';
        }
        return;
      }
      if (d.reason === 'timeout') { st.textContent = '等待超时'; st.className = 'err'; }
      else if (d.reason === 'rejected') { st.textContent = '被拒绝'; st.className = 'err'; }
      else if (d.reason === 'busy') { st.textContent = '已有设备在等待'; st.className = 'err'; }
      else { st.textContent = '等待同意...'; st.className = 'ok'; }
    } else if (d.a === 'approval_req') {
      $('approval-info').textContent = d.ip + ' 正在尝试接管';
      $('approval-overlay').classList.add('show');
    }
  };
}

function S(d) {
  if (!hasControl && d.a !== 'approval_resp' && d.a !== 'auth') return;
  if (ws && ws.readyState === 1) ws.send(JSON.stringify(d));
}

function approvalResp(r) {
  S({ a: 'approval_resp', r });
  $('approval-overlay').classList.remove('show');
}

function submitAuth() {
  const pin = $('auth-pin').value.trim();
  if (pin.length < 4) { $('auth-error').textContent = '请输入配对码'; return; }
  if (ws && ws.readyState === 1) ws.send(JSON.stringify({ a: 'auth', pin }));
}

$('auth-pin').addEventListener('keydown', e => {
  if (e.key === 'Enter') { e.preventDefault(); submitAuth(); }
});

// ─── Sent indicator ──────────────────────────────────
let sentTimer;
function flash() {
  const el = $('sent'); el.classList.add('show');
  clearTimeout(sentTimer); sentTimer = setTimeout(() => el.classList.remove('show'), 400);
}

// ─── Keyboard toggle ─────────────────────────────────
const txt = $('txt');
const kbBtn = $('kb-btn');
const kbIcon = $('kb-icon');
let userDismiss = false;
let skipNextInput = false;

kbBtn.addEventListener('touchstart', () => {
  userDismiss = true;
  setTimeout(() => { userDismiss = false; }, 300);
}, { passive: true });

function toggleKb() {
  if (kbBtn.classList.contains('active')) {
    kbBtn.classList.remove('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-danchujianpan');
    txt.blur();
  } else {
    kbBtn.classList.add('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-shouqijianpan');
    txt.value = '';
    lastVal = '';
    txt.focus({ preventScroll: true });
  }
}

txt.addEventListener('blur', () => {
  clearTimeout(debounce);
  flushPendingText();
  if (!userDismiss) {
    kbBtn.classList.remove('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-danchujianpan');
  }
});

function flushPendingText() {
  if (compositionActive) { compositionActive = false; return; }
  const v = txt.value;
  if (v.length > lastVal.length && v.startsWith(lastVal)) {
    S({ a: 'type', t: v.slice(lastVal.length) }); flash();
  } else if (v.length < lastVal.length && lastVal.startsWith(v)) {
    S({ a: 'bs', n: lastVal.length - v.length }); flash();
  } else if (v !== lastVal) {
    S({ a: 'bs', n: lastVal.length });
    if (v.length) { S({ a: 'type', t: v }); }
    flash();
  }
  txt.value = '';
  lastVal = '';
}

// ─── Real-time input ─────────────────────────────────
let lastVal = '', debounce, compositionActive = false;

txt.addEventListener('compositionstart', () => { compositionActive = true });
txt.addEventListener('compositionend', () => {
  compositionActive = false;
  const v = txt.value;
  if (v.length > lastVal.length && v.startsWith(lastVal)) {
    S({ a: 'type', t: v.slice(lastVal.length) }); flash();
  } else if (v !== lastVal) {
    S({ a: 'bs', n: lastVal.length });
    if (v.length) { S({ a: 'type', t: v }); }
    flash();
  }
  txt.value = '';
  lastVal = '';
});

txt.addEventListener('keydown', e => {
  if (compositionActive) return;
  if (e.key === 'Backspace') {
    S({ a: 'bs', n: 1 }); flash();
  } else if (e.key === 'Delete') {
    e.preventDefault(); S({ a: 'key', k: 'Delete' }); flash();
  } else if (e.key === 'Enter') {
    e.preventDefault(); S({ a: 'key', k: 'Return' }); flash();
  }
});

txt.addEventListener('input', e => {
  if (e.isComposing || compositionActive || skipNextInput) return;
  clearTimeout(debounce);
  debounce = setTimeout(() => {
    const v = txt.value;
    if (v.length > lastVal.length && v.startsWith(lastVal)) {
      S({ a: 'type', t: v.slice(lastVal.length) }); flash();
    } else if (v.length < lastVal.length && lastVal.startsWith(v)) {
      S({ a: 'bs', n: lastVal.length - v.length }); flash();
    } else if (v !== lastVal) {
      S({ a: 'bs', n: lastVal.length });
      if (v.length) { S({ a: 'type', t: v }); }
      flash();
    }
    lastVal = '';
    skipNextInput = true;
    txt.value = '';
    skipNextInput = false;
  }, 10);
});

// ─── Touchpad ────────────────────────────────────────
const tp = $('touchpad');
const scrollTag = $('scroll-tag');
const scrollIcon = $('scroll-icon');
const scrollText = $('scroll-text');
let pts = {}, moved = false, scrolling = false, lastY = 0, tStart = 0;
let lastTapT = 0, lastTapX = 0, lastTapY = 0;
let pressing = false, pressTimer = null;
let twoFingerT = 0, twoFingerMoved = false;
const TH = 8, SENS = 5;
let scrollAcc = 0; // fractional scroll accumulator

// Apply nonlinear acceleration curve (like laptop touchpad)
function scrollCurve(delta) {
  const abs = Math.abs(delta);
  const sign = delta < 0 ? -1 : 1;
  if (abs < 2) return sign * abs * 0.5;
  if (abs < 8) return sign * (1 + (abs - 2) * 0.4);
  return sign * (3.4 + (abs - 8) * 0.8);
}

let accDx = 0, accDy = 0, accScr = 0, mvDirty = false, mvScheduled = false;
function flushMv() {
  mvScheduled = false;
  if (mvDirty) {
    if (accDx || accDy) { S({ a: 'mv', x: accDx, y: accDy }); accDx = accDy = 0; }
    if (accScr) { S({ a: 'scr', y: accScr }); accScr = 0; }
    mvDirty = false;
  }
}
function scheduleMv() {
  mvDirty = true;
  if (!mvScheduled) { mvScheduled = true; requestAnimationFrame(flushMv); }
}

function showTag(iconId, text) {
  scrollIcon.querySelector('use').setAttribute('xlink:href', '#' + iconId);
  scrollText.textContent = text;
  scrollTag.style.display = 'flex';
}
function hideTag() { scrollTag.style.display = 'none'; }

tp.addEventListener('touchstart', e => {
  e.preventDefault();
  const now = Date.now();
  for (const t of e.changedTouches)
    pts[t.identifier] = { x: t.clientX, y: t.clientY, sx: t.clientX, sy: t.clientY };
  if (e.touches.length === 1) {
    moved = false; scrolling = false; tStart = now; pressing = false;
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      if (!moved && !scrolling) {
        pressing = true; S({ a: 'md', b: 1 });
        showTag('icon-tuodong', '拖动');
      }
    }, 400);
  }
  if (e.touches.length === 2) {
    scrolling = false; clearTimeout(pressTimer);
    twoFingerT = now; twoFingerMoved = false;
    showTag('icon-a-075_shuangzhigundong', '滚动');
    lastY = (e.touches[0].clientY + e.touches[1].clientY) / 2;
  }
}, { passive: false });

tp.addEventListener('touchmove', e => {
  e.preventDefault();
  if (e.touches.length === 1 && !scrolling) {
    const t = e.touches[0], p = pts[t.identifier]; if (!p) return;
    const dx = t.clientX - p.x, dy = t.clientY - p.y;
    if (Math.abs(t.clientX - p.sx) > TH || Math.abs(t.clientY - p.sy) > TH) {
      moved = true; if (!pressing) clearTimeout(pressTimer);
    }
    accDx += dx * SENS; accDy += dy * SENS; scheduleMv();
    p.x = t.clientX; p.y = t.clientY;
  }
  if (e.touches.length >= 2) {
    scrolling = true; twoFingerMoved = true;
    const ay = (e.touches[0].clientY + e.touches[1].clientY) / 2;
    const rawDelta = lastY - ay;
    if (rawDelta !== 0) {
      // Apply acceleration curve
      const curved = scrollCurve(rawDelta);
      scrollAcc += curved;
      // Send integer part, keep fractional remainder
      const toSend = Math.trunc(scrollAcc);
      if (toSend !== 0) {
        accScr += toSend;
        scrollAcc -= toSend;
        scheduleMv();
      }
      lastY = ay;
    }
  }
}, { passive: false });

tp.addEventListener('touchend', e => {
  e.preventDefault(); const now = Date.now();
  clearTimeout(pressTimer);

  if (pressing) {
    pressing = false; S({ a: 'mu', b: 1 });
    hideTag();
    for (const t of e.changedTouches) delete pts[t.identifier];
    if (e.touches.length === 0) { scrolling = false; twoFingerT = 0; }
    return;
  }

  if (e.touches.length === 0 && twoFingerT && !twoFingerMoved && now - twoFingerT < 200) {
    S({ a: 'clk', b: 3 });
    const t = e.changedTouches[0];
    if (t) rip(t.clientX, t.clientY, '#58a6ff');
    twoFingerT = 0; scrolling = false;
    hideTag();
    for (const ct of e.changedTouches) delete pts[ct.identifier];
    return;
  }

  for (const t of e.changedTouches) {
    const p = pts[t.identifier]; if (!p) continue;
    if (!moved && !scrolling && e.touches.length === 0 && now - tStart < 250) {
      const dt = now - lastTapT, dd = Math.hypot(t.clientX - lastTapX, t.clientY - lastTapY);
      if (dt < 350 && dd < 50) { S({ a: 'dbl' }); rip(t.clientX, t.clientY, '#f85149'); lastTapT = 0; }
      else { S({ a: 'clk', b: 1 }); rip(t.clientX, t.clientY, '#3fb950'); lastTapT = now; lastTapX = t.clientX; lastTapY = t.clientY; }
    }
    delete pts[t.identifier];
  }
  if (e.touches.length === 0) { scrolling = false; twoFingerT = 0; scrollAcc = 0; hideTag(); }
}, { passive: false });

function rip(x, y, c) {
  const r = document.createElement('div'); r.className = 'ripple';
  const b = tp.getBoundingClientRect();
  r.style.left = (x - b.left) + 'px'; r.style.top = (y - b.top) + 'px';
  const m = /^#(..)(..)(..)$/.exec(c);
  r.style.background = `rgba(${parseInt(m[1],16)},${parseInt(m[2],16)},${parseInt(m[3],16)},.3)`;
  tp.appendChild(r); setTimeout(() => r.remove(), 400);
}

document.body.addEventListener('touchmove', e => e.preventDefault(), { passive: false });

// ─── Function Keys ───────────────────────────────────
const fkToggle = $('fk-toggle');
const fkPanel = $('fk-panel');

function toggleFk() {
  fkPanel.classList.toggle('hidden');
  fkToggle.classList.toggle('active');
}

const modState = { ctrl: false, shift: false, alt: false };

function getModPrefix() {
  let p = '';
  if (modState.ctrl) p += 'ctrl+';
  if (modState.shift) p += 'shift+';
  if (modState.alt) p += 'alt+';
  return p;
}

function sendKey(key) {
  S({ a: 'key', k: getModPrefix() + key });
  flash();
}

document.querySelectorAll('.fk[data-key]:not(.combo)').forEach(btn => {
  btn.addEventListener('click', () => sendKey(btn.dataset.key));
});

document.querySelectorAll('.fk.mod').forEach(btn => {
  btn.addEventListener('click', () => {
    const mod = btn.dataset.mod;
    modState[mod] = !modState[mod];
    btn.classList.toggle('active', modState[mod]);
  });
});

document.querySelectorAll('.fk.combo').forEach(btn => {
  btn.addEventListener('click', () => {
    S({ a: 'key', k: btn.dataset.key });
    flash();
  });
});

fkPanel.addEventListener('touchstart', e => e.stopPropagation(), { passive: true });
fkPanel.addEventListener('touchmove', e => e.stopPropagation(), { passive: true });
fkPanel.addEventListener('touchend', e => e.stopPropagation(), { passive: true });

// ─── Init ────────────────────────────────────────────
connect();
