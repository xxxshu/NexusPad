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

// ─── On-Screen Keyboard ────────────────────────────
const kbBtn = $('kb-btn');
const kbIcon = $('kb-icon');
const osk = $('osk');
const oskLayers = {};
osk.querySelectorAll('.osk-layer').forEach(el => { oskLayers[el.dataset.layer] = el; });
const ta = $('txt'); // hidden textarea for IME composition

let oskShift = false;    // sticky shift
let oskLayer = 'alpha';  // 'alpha' | 'sym'
let oskLang = 'en';      // 'en' | 'zh'
let composing = false;   // IME composition active

// IME composition events (for Chinese pinyin on controller)
ta.addEventListener('compositionstart', () => { composing = true });
ta.addEventListener('compositionend', () => {
  composing = false;
  const text = ta.value;
  if (text.length > 0) {
    // Commit composed text to controlled device
    S({ a: 'type', t: text });
    flash();
  }
  ta.value = '';
});
ta.addEventListener('input', () => {
  if (composing) return; // wait for compositionend
  // Non-composed input (e.g. English letters if IME not active)
  const text = ta.value;
  if (text.length > 0) {
    S({ a: 'type', t: text });
    flash();
  }
  ta.value = '';
});

function toggleKb() {
  if (osk.classList.contains('hidden')) {
    osk.classList.remove('hidden');
    kbBtn.classList.add('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-shouqijianpan');
  } else {
    osk.classList.add('hidden');
    kbBtn.classList.remove('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-danchujianpan');
    ta.blur();
  }
}

function oskSwitchLayer(layer) {
  oskLayer = layer;
  for (const [name, el] of Object.entries(oskLayers)) {
    el.style.display = name === layer ? '' : 'none';
  }
  if (layer === 'sym') { oskShift = false; updateShiftUI(); }
  if (layer === 'alpha') updateAlphaLabels();
}

function updateShiftUI() {
  osk.querySelectorAll('.osk-key[data-action="shift"]').forEach(b => {
    b.classList.toggle('active', oskShift);
  });
  updateAlphaLabels();
}

function updateAlphaLabels() {
  if (oskLayer !== 'alpha') return;
  oskLayers.alpha.querySelectorAll('.osk-key[data-k]').forEach(b => {
    const k = b.dataset.k;
    b.textContent = oskShift ? k.toUpperCase() : k;
  });
}

osk.addEventListener('pointerdown', e => {
  const btn = e.target.closest('.osk-key');
  if (!btn) return;
  e.preventDefault();
  e.stopPropagation();
  btn.classList.add('pressed');

  const k = btn.dataset.k;
  const action = btn.dataset.action;

  if (action) {
    handleOskAction(action);
  } else if (k) {
    handleOskKey(k);
  }
}, { passive: false });

osk.addEventListener('pointerup', e => {
  const btn = e.target.closest('.osk-key');
  if (btn) btn.classList.remove('pressed');
});

osk.addEventListener('pointerleave', e => {
  const btn = e.target.closest('.osk-key');
  if (btn) btn.classList.remove('pressed');
}, true);

function handleOskKey(k) {
  if (oskLang === 'zh') {
    // Chinese mode: type into textarea, let browser IME compose pinyin
    if (!document.activeElement || document.activeElement !== ta) {
      ta.focus({ preventScroll: true });
    }
    // Type the character into textarea for IME composition
    const ch = oskShift ? k.toUpperCase() : k;
    if (oskShift) { oskShift = false; updateShiftUI(); }
    // Use insertText to trigger proper composition events
    ta.setRangeText(ch, ta.selectionStart, ta.selectionEnd, 'end');
    ta.dispatchEvent(new Event('input', { bubbles: true }));
  } else {
    // English mode: send key events directly to controlled device
    if (oskShift) {
      S({ a: 'key', k: 'shift+' + k });
      oskShift = false;
      updateShiftUI();
    } else {
      S({ a: 'key', k: k });
    }
    flash();
  }
}

function handleOskAction(action) {
  switch (action) {
    case 'shift':
      oskShift = !oskShift;
      updateShiftUI();
      break;
    case 'backspace':
      if (oskLang === 'zh' && ta.value.length > 0 && composing) {
        // During composition: let IME handle backspace
        ta.setRangeText('', ta.selectionStart - 1, ta.selectionEnd, 'end');
        ta.dispatchEvent(new Event('input', { bubbles: true }));
      } else {
        S({ a: 'bs', n: 1 });
        flash();
      }
      break;
    case 'return':
      S({ a: 'key', k: 'Return' });
      flash();
      break;
    case 'space':
      if (oskLang === 'zh') {
        // Space confirms IME candidate on controlled device
        // First commit any local composition
        if (composing) {
          composing = false;
          const text = ta.value;
          if (text.length > 0) { S({ a: 'type', t: text }); }
          ta.value = '';
        }
        S({ a: 'key', k: 'Space' });
      } else {
        S({ a: 'key', k: 'Space' });
      }
      flash();
      break;
    case 'tab':
      S({ a: 'key', k: 'Tab' });
      flash();
      break;
    case 'comma':
      S({ a: 'key', k: oskShift ? 'shift+,' : ',' });
      if (oskShift) { oskShift = false; updateShiftUI(); }
      flash();
      break;
    case 'period':
      S({ a: 'key', k: oskShift ? 'shift+.' : '.' });
      if (oskShift) { oskShift = false; updateShiftUI(); }
      flash();
      break;
    case 'lang':
      oskLang = oskLang === 'en' ? 'zh' : 'en';
      const langBtn = osk.querySelector('.osk-key[data-action="lang"]');
      if (langBtn) langBtn.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
      if (oskLang === 'zh') {
        // Focus textarea to activate IME
        ta.value = '';
        ta.focus({ preventScroll: true });
      } else {
        ta.blur();
        ta.value = '';
      }
      break;
    case 'sym':
      oskSwitchLayer(oskLayer === 'alpha' ? 'sym' : 'alpha');
      break;
  }
}

// Prevent touch events from reaching the touchpad
osk.addEventListener('touchstart', e => e.stopPropagation(), { passive: true });
osk.addEventListener('touchmove', e => e.stopPropagation(), { passive: true });
osk.addEventListener('touchend', e => e.stopPropagation(), { passive: true });

// ─── Touchpad (gesture engine) ─────────────────────
const tp = $('touchpad');
const scrollTag = $('scroll-tag');
const scrollIcon = $('scroll-icon');
const scrollText = $('scroll-text');
const TH = 8, SENS = 5;

// Finger tracking: identifier → { x, y, sx, sy }
let fingers = {};
// Gesture state machine
let gesture = 'none'; // 'none' | 'detecting' | 'scroll' | 'pinch' | 'drag'
// Single-finger tap / long-press
let moved = false, tStart = 0;
let lastTapT = 0, lastTapX = 0, lastTapY = 0;
let pressing = false, pressTimer = null, touchActive = false;
// Two-finger detection
let detectStart = 0;
// Scroll accumulators
let scrFrac = 0;
// Pinch state
let pinchD0 = 0, pinchAcc = 0;
// Batch movement
let accDx = 0, accDy = 0, accScrX = 0, accScrY = 0, mvDirty = false, mvScheduled = false;

// Nonlinear scroll curve (libinput-inspired)
function scrollCurve(delta) {
  const abs = Math.abs(delta);
  const sign = delta < 0 ? -1 : 1;
  const curved = abs * (0.3 + 0.012 * abs);
  return sign * Math.min(curved, abs * 3);
}

// Batch flush (requestAnimationFrame)
function flushMv() {
  mvScheduled = false;
  if (mvDirty) {
    if (accDx || accDy) { S({ a: 'mv', x: accDx, y: accDy }); accDx = accDy = 0; }
    if (accScrX || accScrY) { S({ a: 'scr', x: accScrX, y: accScrY }); accScrX = accScrY = 0; }
    mvDirty = false;
  }
}
function scheduleMv() {
  mvDirty = true;
  if (!mvScheduled) { mvScheduled = true; requestAnimationFrame(flushMv); }
}

// Gesture state indicator tags
function showTag(iconId, text) {
  scrollIcon.querySelector('use').setAttribute('xlink:href', '#' + iconId);
  scrollText.textContent = text;
  scrollTag.style.display = 'flex';
}
function hideTag() { scrollTag.style.display = 'none'; }

// ─── Gesture disambiguation ────────────────────────
const DETECT_MS = 250;   // detection window (ms)
const PINCH_TH  = 0.08;  // 8% distance change → pinch

function detectGesture() {
  const ids = Object.keys(fingers);
  if (ids.length < 2) return;
  const f0 = fingers[ids[0]], f1 = fingers[ids[1]];
  const dCurrent = Math.hypot(f0.x - f1.x, f0.y - f1.y);
  const dInitial = Math.hypot(f0.sx - f1.sx, f0.sy - f1.sy);
  if (dInitial > 0 && Math.abs(dCurrent - dInitial) / dInitial > PINCH_TH) {
    gesture = 'pinch';
    pinchD0 = dCurrent;
    pinchAcc = 0;
    showTag('icon-a-075_shuangzhigundong', '缩放');
    return;
  }
  const dot = (f0.x - f0.sx) * (f1.x - f1.sx) + (f0.y - f0.sy) * (f1.y - f1.sy);
  const centroidDx = (f0.x + f1.x) / 2 - (f0.sx + f1.sx) / 2;
  const centroidDy = (f0.y + f1.y) / 2 - (f0.sy + f1.sy) / 2;
  if (dot > 0 && (Math.abs(centroidDx) > TH || Math.abs(centroidDy) > TH)) {
    gesture = 'scroll';
    scrFrac = 0;
    showTag('icon-a-075_shuangzhigundong', '滚动');
    return;
  }
  if (Date.now() - detectStart > DETECT_MS) {
    gesture = 'scroll';
    scrFrac = 0;
    showTag('icon-a-075_shuangzhigundong', '滚动');
  }
}

// ─── Touch events ──────────────────────────────────
tp.addEventListener('touchstart', e => {
  e.preventDefault();
  const now = Date.now();
  for (const t of e.changedTouches)
    fingers[t.identifier] = { x: t.clientX, y: t.clientY, sx: t.clientX, sy: t.clientY };

  if (e.touches.length === 1 && gesture === 'none') {
    moved = false; tStart = now; pressing = false; touchActive = true;
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      if (!moved && gesture === 'none' && touchActive) {
        pressing = true; S({ a: 'md', b: 1 });
        gesture = 'drag';
        showTag('icon-tuodong', '拖动');
      }
    }, 400);
  }

  if (e.touches.length === 2) {
    clearTimeout(pressTimer);
    if (gesture === 'none' || gesture === 'drag') {
      if (pressing) { pressing = false; S({ a: 'mu', b: 1 }); }
      gesture = 'detecting';
      detectStart = now;
      // Reset start positions for detection baseline
      const ids = Object.keys(fingers);
      for (const id of ids) { fingers[id].sx = fingers[id].x; fingers[id].sy = fingers[id].y; }
      showTag('icon-a-075_shuangzhigundong', '检测中...');
    }
  }
}, { passive: false });

tp.addEventListener('touchmove', e => {
  e.preventDefault();

  // ── Two-finger gestures ──
  if (e.touches.length >= 2) {
    const ids = Object.keys(fingers);
    if (ids.length < 2) { for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } } return; }
    const f0 = fingers[ids[0]], f1 = fingers[ids[1]];

    if (gesture === 'detecting') {
      // Update positions BEFORE detection
      for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } }
      detectGesture();
      return;
    }

    if (gesture === 'pinch') {
      // Use current touch positions directly (don't rely on stored positions for pinch)
      const t0 = e.touches[0], t1 = e.touches[1];
      const d = Math.hypot(t0.clientX - t1.clientX, t0.clientY - t1.clientY);
      if (pinchD0 > 0) {
        pinchAcc += Math.log(d / pinchD0);
        if (Math.abs(pinchAcc) > 0.05) {
          S({ a: 'pz', m: pinchAcc });
          flash();
          pinchD0 = d;
          pinchAcc = 0;
        }
      }
      for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } }
      return;
    }

    if (gesture === 'scroll') {
      // Calculate delta BEFORE updating positions
      const dx = (f0.x + f1.x) / 2 - (f0.sx + f1.sx) / 2;
      const dy = -((f0.y + f1.y) / 2 - (f0.sy + f1.sy) / 2); // negate for natural scroll
      const cdx = scrollCurve(dx);
      const cdy = scrollCurve(dy);
      if (Math.abs(cdx) > Math.abs(cdy)) {
        scrFrac += cdx;
        const toSend = Math.trunc(scrFrac);
        if (toSend !== 0) { accScrX += toSend; scrFrac -= toSend; scheduleMv(); }
      } else {
        scrFrac += cdy;
        const toSend = Math.trunc(scrFrac);
        if (toSend !== 0) { accScrY += toSend; scrFrac -= toSend; scheduleMv(); }
      }
      // Update start positions for continuous delta
      f0.sx = f0.x; f0.sy = f0.y;
      f1.sx = f1.x; f1.sy = f1.y;
      // Update current positions
      for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } }
      return;
    }
  }

  // ── Single-finger mouse movement ──
  if (e.touches.length === 1 && gesture === 'none') {
    const t = e.touches[0], f = fingers[t.identifier];
    if (!f) return;
    // Calculate delta BEFORE updating position
    const dx = t.clientX - f.x, dy = t.clientY - f.y;
    if (Math.abs(t.clientX - f.sx) > TH || Math.abs(t.clientY - f.sy) > TH) {
      moved = true; if (!pressing) clearTimeout(pressTimer);
    }
    accDx += dx * SENS; accDy += dy * SENS; scheduleMv();
    f.x = t.clientX; f.y = t.clientY;
  }
}, { passive: false });

tp.addEventListener('touchend', e => {
  e.preventDefault();
  const now = Date.now();
  // Remove ended fingers, clear timer
  for (const t of e.changedTouches) delete fingers[t.identifier];
  clearTimeout(pressTimer);

  // ── All fingers up ──
  if (e.touches.length === 0) {
    touchActive = false;
    if (pressing) {
      pressing = false; S({ a: 'mu', b: 1 }); hideTag();
      gesture = 'none'; scrFrac = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'detecting' && now - detectStart < 250) {
      S({ a: 'clk', b: 3 });
      const t = e.changedTouches[0];
      if (t) rip(t.clientX, t.clientY, '#58a6ff');
      hideTag(); gesture = 'none'; scrFrac = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'scroll' || gesture === 'pinch') {
      hideTag(); gesture = 'none'; scrFrac = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'none' && !moved && now - tStart < 250) {
      const t = e.changedTouches[0];
      if (t) {
        const dt = now - lastTapT, dd = Math.hypot(t.clientX - lastTapX, t.clientY - lastTapY);
        if (dt < 350 && dd < 50) { S({ a: 'dbl' }); rip(t.clientX, t.clientY, '#f85149'); lastTapT = 0; }
        else { S({ a: 'clk', b: 1 }); rip(t.clientX, t.clientY, '#3fb950'); lastTapT = now; lastTapX = t.clientX; lastTapY = t.clientY; }
      }
    }
    gesture = 'none'; scrFrac = 0; pinchD0 = 0; pinchAcc = 0; hideTag();
    return;
  }

  // ── Some fingers still down ──
  if (e.touches.length < 2 && gesture !== 'none' && gesture !== 'drag') {
    // Update remaining finger position so next touchmove delta is correct
    if (e.touches.length === 1) {
      const rt = e.touches[0];
      const rf = fingers[rt.identifier];
      if (rf) { rf.x = rt.clientX; rf.y = rt.clientY; }
    }
    hideTag(); gesture = 'none'; scrFrac = 0; pinchD0 = 0; pinchAcc = 0;
  }
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
