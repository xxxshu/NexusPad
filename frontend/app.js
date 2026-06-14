// ─── Connection ──────────────────────────────────────
const $ = id => document.getElementById(id);
let ws, reconn, hasControl = false, hasEverControlled = false, isProot = false;
let imeStatus = 'en'; // Server-pushed IME state: 'en' or 'zh'
let imeJustToggled = 0; // Timestamp of last toggle — guard against stale server response
const st = $('status'), statusText = $('status-text');

function setStatus(text, cls) {
  st.className = cls;
  statusText.textContent = text;
}

// ─── Haptic feedback ────────────────────────────────
let hapticAudioCtx = null;
const isIOS = /iPhone|iPad|iPod/.test(navigator.userAgent);

function vibrate(pattern) {
  if ('vibrate' in navigator) navigator.vibrate(pattern);
  if (isIOS) {
    try {
      if (!hapticAudioCtx) hapticAudioCtx = new (window.AudioContext || window.webkitAudioContext)();
      if (hapticAudioCtx.state === 'suspended') hapticAudioCtx.resume();
      const ms = Array.isArray(pattern) ? pattern.reduce((a, b, i) => i % 2 === 0 ? a + b : a, 0) : pattern;
      const dur = ms / 1000;
      const osc = hapticAudioCtx.createOscillator();
      const gain = hapticAudioCtx.createGain();
      osc.type = 'sine'; osc.frequency.setValueAtTime(1, hapticAudioCtx.currentTime);
      gain.gain.setValueAtTime(0.002, hapticAudioCtx.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.0001, hapticAudioCtx.currentTime + dur);
      osc.connect(gain); gain.connect(hapticAudioCtx.destination);
      osc.start(); osc.stop(hapticAudioCtx.currentTime + dur);
    } catch {}
  }
}
const hapticTap = () => vibrate(15);
const hapticDoubleTap = () => vibrate([12, 50, 12]);
const hapticDragStart = () => vibrate(30);
const hapticDragEnd = () => vibrate(18);
const hapticKeyPress = () => vibrate(12);
const hapticBtnPress = () => vibrate(10);

// Scroll tick: distance-based, throttled (guide §3.4)
let scrollTickDist = 0, lastScrollTickT = 0;
const SCROLL_TICK_DIST = 50;   // px per tick
const SCROLL_TICK_MIN_MS = 40; // min interval
function scrollTickStep(dy) {
  scrollTickDist += Math.abs(dy);
  const now = Date.now();
  if (scrollTickDist >= SCROLL_TICK_DIST && now - lastScrollTickT >= SCROLL_TICK_MIN_MS) {
    const intensity = Math.min(1.0, scrollTickDist / 200);
    vibrate(Math.round(8 + intensity * 12));
    scrollTickDist = 0;
    lastScrollTickT = now;
  }
}

document.addEventListener('visibilitychange', () => { if (document.hidden && 'vibrate' in navigator) navigator.vibrate(0); });

function connect() {
  ws = new WebSocket(`ws://${location.host}/ws`);
  ws.onopen = () => { setStatus('已连接', 'ok'); clearTimeout(reconn) };
  ws.onclose = e => {
    hasControl = false;
    $('approval-overlay').classList.remove('show');
    $('auth-overlay').classList.remove('show');
    if (e.code === 4001) { setStatus('已被新设备接管', 'err'); return; }
    if (e.code === 4002) {
      const reason = e.reason || '';
      if (reason === 'rejected') { setStatus('被拒绝', 'err'); }
      else if (reason === 'timeout') { setStatus('等待超时', 'err'); }
      else if (reason === 'busy') { setStatus('已有设备在等待', 'err'); }
      return;
    }
    if (e.code === 1000) { setStatus('服务已停止', 'err'); return; }
    setStatus('已断开', 'err');
    if (hasEverControlled) reconn = setTimeout(connect, 2000);
  };
  ws.onerror = () => ws.close();
  ws.onmessage = e => {
    let d; try { d = JSON.parse(e.data) } catch { return };
    if (d.a === 'ctrl_ok') {
      hasControl = true; hasEverControlled = true;
      isProot = !!d.proot;
      setStatus('控制中', 'ok');
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
      if (d.reason === 'timeout') { setStatus('等待超时', 'err'); }
      else if (d.reason === 'rejected') { setStatus('被拒绝', 'err'); }
      else if (d.reason === 'busy') { setStatus('已有设备在等待', 'err'); }
      else { setStatus('等待同意...', 'ok'); }
    } else if (d.a === 'approval_req') {
      $('approval-info').textContent = d.ip + ' 正在尝试接管';
      $('approval-overlay').classList.add('show');
    } else if (d.a === 'ime_init' || d.a === 'ime_state') {
      // Server pushes IME status (on connect via ime_init, after toggle/refresh via ime_state)
      const newStatus = (d.status || 'EN').toLowerCase();
      console.log('[IME] received', d.a, 'status:', d.status, '→ oskLang:', newStatus, 'was:', oskLang);
      // Guard: ignore server status right after a toggle (server may read from wrong window)
      if (imeJustToggled && Date.now() - imeJustToggled < 500) {
        console.log('[IME] ignoring — just toggled');
        return;
      }
      imeStatus = newStatus;
      oskLang = newStatus;
      const btn = osk.querySelector('.osk-key[data-action="lang"]');
      if (btn) btn.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
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
const pinyinBar = $('pinyin-bar');
const pinyinInput = $('pinyin-input');
const pinyinCandidates = $('pinyin-candidates');
const ta = $('txt'); // hidden textarea (unused in pinyin mode, kept for compatibility)

let oskShift = false;
let oskLayer = 'alpha';
let oskLang = 'en';
// Pinyin state
let pyBuf = '';
let pyCandidates = [];
let pyPage = 0;
const PY_PAGE_SIZE = 8;

// ─── Pinyin engine ─────────────────────────────────
const PY_KEYS = typeof PINYIN_MAP !== 'undefined'
  ? Object.keys(PINYIN_MAP).sort((a, b) => b.length - a.length)
  : [];

function parsePinyin(str) {
  const result = [];
  let s = str.toLowerCase();
  while (s.length > 0) {
    let found = false;
    for (const k of PY_KEYS) {
      if (s.startsWith(k)) {
        result.push(k);
        s = s.slice(k.length);
        found = true;
        break;
      }
    }
    if (!found) { result.push(s); s = ''; }
  }
  return result;
}

function updatePinyinUI() {
  if (!pyBuf || oskLang !== 'zh') {
    pinyinBar.classList.add('hidden');
    pyCandidates = [];
    return;
  }
  pinyinBar.classList.remove('hidden');
  pinyinInput.textContent = pyBuf;

  if (typeof PINYIN_MAP === 'undefined') { pyCandidates = []; renderCandidates(); return; }

  const full = pyBuf.toLowerCase();
  let cands = [];

  // 1. Try full pinyin as word key
  if (PINYIN_MAP[full]) {
    const entry = PINYIN_MAP[full];
    // Extract: multi-char words first, then single chars
    let i = 0;
    while (i < entry.length) {
      const cp = entry.codePointAt(i);
      const ch = String.fromCodePoint(cp);
      // Check if next char is also CJK → this is a multi-char word
      if (i + 1 < entry.length) {
        const nextCp = entry.codePointAt(i + 1);
        if (nextCp >= 0x4E00 && nextCp <= 0x9FFF) {
          // Find the end of this word (consecutive CJK chars)
          let j = i + 1;
          while (j < entry.length) {
            const ncp = entry.codePointAt(j);
            if (ncp < 0x4E00 || ncp > 0x9FFF) break;
            j++;
          }
          cands.push(entry.slice(i, j));
          i = j;
          continue;
        }
      }
      cands.push(ch);
      i += ch.length;
    }
  }

  // 2. Also try partial matches (multi-syllable combinations from the end)
  if (cands.length === 0) {
    const sylls = parsePinyin(full);
    for (let start = sylls.length - 1; start >= 0; start--) {
      const key = sylls.slice(start).join('');
      if (PINYIN_MAP[key]) {
        const entry = PINYIN_MAP[key];
        let i = 0;
        while (i < entry.length) {
          const cp = entry.codePointAt(i);
          const ch = String.fromCodePoint(cp);
          if (i + 1 < entry.length) {
            const nextCp = entry.codePointAt(i + 1);
            if (nextCp >= 0x4E00 && nextCp <= 0x9FFF) {
              let j = i + 1;
              while (j < entry.length) {
                const ncp = entry.codePointAt(j);
                if (ncp < 0x4E00 || ncp > 0x9FFF) break;
                j++;
              }
              cands.push(entry.slice(i, j));
              i = j;
              continue;
            }
          }
          cands.push(ch);
          i += ch.length;
        }
        break;
      }
    }
  }

  pyCandidates = cands;
  pyPage = 0;
  renderCandidates();
}

function renderCandidates() {
  pinyinCandidates.innerHTML = '';
  const start = pyPage * PY_PAGE_SIZE;
  const page = pyCandidates.slice(start, start + PY_PAGE_SIZE);
  for (const ch of page) {
    const btn = document.createElement('span');
    btn.className = 'pinyin-cand';
    btn.textContent = ch;
    btn.addEventListener('click', () => selectCandidate(ch));
    pinyinCandidates.appendChild(btn);
  }
  if (pyCandidates.length > start + PY_PAGE_SIZE) {
    const more = document.createElement('span');
    more.className = 'pinyin-cand';
    more.textContent = '…';
    more.addEventListener('click', () => { pyPage++; renderCandidates(); });
    pinyinCandidates.appendChild(more);
  }
}

function selectCandidate(ch) {
  S({ a: 'type', t: ch });
  flash();
  // For a word like "你好" (2 chars), its pinyin is the full buffer
  // For a single char, remove only the first syllable
  const sylls = parsePinyin(pyBuf);
  if (ch.length > 1) {
    // Multi-char word: matched pinyin = all syllables that map to this word
    // We used the full buffer key, so clear it all
    pyBuf = '';
  } else {
    // Single char: remove first syllable
    pyBuf = pyBuf.slice(sylls[0]?.length || 1);
  }
  if (pyBuf) updatePinyinUI();
  else { pyCandidates = []; pinyinBar.classList.add('hidden'); }
}

function commitPinyin() {
  if (pyCandidates.length > 0) {
    selectCandidate(pyCandidates[0]);
  } else if (pyBuf) {
    S({ a: 'type', t: pyBuf });
    flash();
    pyBuf = '';
    pyCandidates = [];
    pinyinBar.classList.add('hidden');
  }
}

function toggleKb() {
  if (osk.classList.contains('hidden')) {
    osk.classList.remove('hidden');
    kbBtn.classList.add('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-shouqijianpan');
    // Sync IME button UI with latest server state when keyboard opens
    oskLang = imeStatus;
    const btn = osk.querySelector('.osk-key[data-action="lang"]');
    if (btn) btn.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
  } else {
    osk.classList.add('hidden');
    kbBtn.classList.remove('active');
    kbIcon.querySelector('use').setAttribute('xlink:href', '#icon-danchujianpan');
    pyBuf = ''; pyCandidates = []; pinyinBar.classList.add('hidden');
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
    b.textContent = oskShift ? b.dataset.k.toUpperCase() : b.dataset.k;
  });
}

osk.addEventListener('pointerdown', e => {
  const btn = e.target.closest('.osk-key');
  if (!btn) return;
  e.preventDefault();
  e.stopPropagation();
  btn.classList.add('pressed');
  hapticKeyPress();
  if (btn.dataset.action) {
    handleOskAction(btn.dataset.action);
    // Long-press repeat for backspace
    if (btn.dataset.action === 'backspace') {
      clearTimeout(bsRepeatTimer);
      bsRepeatTimer = setTimeout(() => {
        bsRepeatId = setInterval(() => handleOskAction('backspace'), 80);
      }, 400);
    }
    // Long-press detection for lang key (passive override)
    if (btn.dataset.action === 'lang') {
      langLongPressed = false;
      clearTimeout(langPressTimer);
      langPressTimer = setTimeout(() => {
        langLongPressed = true;
        // Long press: flip local UI only, no server message (passive override)
        oskLang = oskLang === 'en' ? 'zh' : 'en';
        const b = osk.querySelector('.osk-key[data-action="lang"]');
        if (b) b.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
        if (isProot) { pyBuf = ''; pyCandidates = []; pinyinBar.classList.add('hidden'); }
        hapticDragStart();
      }, 500);
    }
  }
  else if (btn.dataset.k) handleOskKey(btn.dataset.k);
}, { passive: false });

let bsRepeatTimer, bsRepeatId;
let langPressTimer = null, langLongPressed = false;

osk.addEventListener('pointerup', e => {
  const btn = e.target.closest('.osk-key');
  if (btn) btn.classList.remove('pressed');
  clearTimeout(bsRepeatTimer); clearInterval(bsRepeatId);
  // If lang key was short-pressed (not long-pressed), handle it now
  if (btn && btn.dataset.action === 'lang' && !langLongPressed) {
    clearTimeout(langPressTimer);
    handleLangShortPress();
  }
  clearTimeout(langPressTimer);
});

osk.addEventListener('pointerleave', e => {
  const btn = e.target.closest('.osk-key');
  if (btn) btn.classList.remove('pressed');
  clearTimeout(bsRepeatTimer); clearInterval(bsRepeatId);
}, true);

function handleOskKey(k) {
  if (oskLang === 'zh' && isProot) {
    // proot Chinese mode: frontend pinyin dictionary
    pyBuf += k.toLowerCase();
    if (oskShift) { oskShift = false; updateShiftUI(); }
    updatePinyinUI();
  } else {
    // Normal mode (or English mode): send key event to controlled machine
    if (oskShift) {
      S({ a: 'key', k: 'shift+' + k });
      oskShift = false; updateShiftUI();
    } else {
      S({ a: 'key', k: k });
    }
    flash();
  }
}

function handleOskAction(action) {
  switch (action) {
    case 'shift':
      oskShift = !oskShift; updateShiftUI(); break;
    case 'backspace':
      if (oskLang === 'zh' && isProot && pyBuf.length > 0) {
        pyBuf = pyBuf.slice(0, -1);
        updatePinyinUI();
      } else {
        S({ a: 'bs', n: 1 }); flash();
      }
      break;
    case 'return':
      if (oskLang === 'zh' && isProot && pyBuf) commitPinyin();
      S({ a: 'key', k: 'Return' }); flash();
      break;
    case 'space':
      if (oskLang === 'zh' && isProot && pyBuf) { commitPinyin(); }
      else { S({ a: 'key', k: 'Space' }); flash(); }
      break;
    case 'tab':
      if (oskLang === 'zh' && isProot && pyBuf) commitPinyin();
      S({ a: 'key', k: 'Tab' }); flash();
      break;
    case 'comma':
      if (oskLang === 'zh' && isProot && pyBuf) commitPinyin();
      S({ a: 'key', k: oskShift ? 'shift+,' : ',' });
      if (oskShift) { oskShift = false; updateShiftUI(); }
      flash(); break;
    case 'period':
      if (oskLang === 'zh' && isProot && pyBuf) commitPinyin();
      S({ a: 'key', k: oskShift ? 'shift+.' : '.' });
      if (oskShift) { oskShift = false; updateShiftUI(); }
      flash(); break;
    case 'lang':
      // Lang is now handled via long-press (passive override) in pointerdown/pointerup
      // and short-press (ime_toggle) in handleLangShortPress
      break;
    case 'sym':
      oskSwitchLayer(oskLayer === 'alpha' ? 'sym' : 'alpha'); break;
  }
}

/// Short press on lang key: request physical IME toggle from server.
/// Per 开发计划.md §5: frontend flips UI state in sync with the toggle request.
/// Server only simulates the physical key — we don't rely on server-side IME detection.
function handleLangShortPress() {
  if (isProot) {
    // In proot mode, toggle locally (no system IME available)
    oskLang = oskLang === 'en' ? 'zh' : 'en';
    const b = osk.querySelector('.osk-key[data-action="lang"]');
    if (b) b.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
    pyBuf = ''; pyCandidates = []; pinyinBar.classList.add('hidden');
  } else {
    // Non-proot: flip UI immediately, then request server to simulate physical key
    oskLang = oskLang === 'en' ? 'zh' : 'en';
    const b = osk.querySelector('.osk-key[data-action="lang"]');
    if (b) b.textContent = oskLang === 'en' ? '中/EN' : 'EN/中';
    imeStatus = oskLang; // Keep imeStatus in sync
    imeJustToggled = Date.now();
    S({ a: 'ime_toggle' }); flash();
  }
}

osk.addEventListener('touchstart', e => e.stopPropagation(), { passive: true });
osk.addEventListener('touchmove', e => e.stopPropagation(), { passive: true });
osk.addEventListener('touchend', e => e.stopPropagation(), { passive: true });

// ─── Touchpad (gesture engine) ─────────────────────
const tp = $('touchpad');
const scrollTag = $('scroll-tag');
const scrollIcon = $('scroll-icon');
const scrollText = $('scroll-text');

// ─── Pointer algorithms (research report §1.4, §2.2, §3.1, §3.5) ──
const TH = 8;  // movement detection threshold (px)

// Delta smoothing: EMA on raw deltas (§2.2 — exponential moving average)
const DELTA_SMOOTH = 0.5;  // 0.5 = more smoothing, smaller per-frame deltas for extreme smoothness

// Acceleration: higher base for smooth sub-pixel movement (§3.1)
// At slow speed (1px/frame): 0.75*4 = 3px/frame → smooth continuous
// At fast speed (10px/frame): 0.75*4 = 30px/frame → fast screen traversal
const ACCEL_BASE    = 3.0;  // base sensitivity (server handles sub-pixel precision)
const ACCEL_RAMP    = 1.0;  // additional multiplier at high speed
const ACCEL_SPEED_K = 0.2;  // px/ms — speed where acceleration kicks in
const ACCEL_CAP     = 8.0;  // max total multiplier

// Inertia scrolling (§1.5, §3.4) — exponential decay, time-normalized
const INERTIA_RATE    = 0.975;  // per-frame decay at 60fps
const INERTIA_STOP_TH = 0.15;  // |velocity| below this → stop

// Scroll nonlinear curve (§3.4 libinput-inspired)
const SCROLL_LINEAR_TH = 5;  // px — below this, use linear (no truncation loss)

// Two-finger tap (§5.2, §6.1) — right-click
const TAP_MOVE_TH  = 15;  // max per-finger movement (px)
const TAP_TIME_TH  = 300; // max duration (ms)

// Pinch threshold (§3.3) — distance change ratio to disambiguate from scroll
const PINCH_TH = 0.08;  // 8% distance change → pinch candidate

// ─── Algorithm state ───────────────────────────────
let prevDx = 0, prevDy = 0;  // EMA-smoothed deltas
let lastMoveT = 0;
let smoothedSpeed = 0;  // EMA velocity for acceleration

// Sub-pixel accumulators (§3.5 — float truncation, retain fractional remainder)
let mvAccX = 0, mvAccY = 0;

// Inertia scrolling state
let inertiaVelocity = 0, inertiaActive = false, inertiaRAF = null;

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
let scrFrac = 0, scrFracX = 0, scrFracY = 0;
// Pinch state
let pinchD0 = 0, pinchAcc = 0;
// Scroll batch (separate from movement — movement sends immediately)
let accScrX = 0, accScrY = 0, scrDirty = false, scrRAF = false;
// Two-finger tap tracking
let twoFingerMovedDist = 0;

// Acceleration: smooth adaptive curve (§3.1)
// Slow → ACCEL_BASE (precise), fast → ACCEL_BASE + ACCEL_RAMP (powerful)
function calcAccel(speed) {
  // speed is in px/ms from EMA
  const ramp = speed > ACCEL_SPEED_K
    ? ACCEL_RAMP * (1 - Math.exp(-((speed - ACCEL_SPEED_K) / ACCEL_SPEED_K)))
    : 0;
  return Math.min(ACCEL_BASE + ramp, ACCEL_CAP);
}

// Scroll nonlinear curve (§3.4 libinput-inspired)
// Linear for slow movement (prevents jerky stops), nonlinear boost for fast
const SCROLL_SCALE = 0.5;  // overall scroll sensitivity (0.5 = half speed)
function scrollCurve(delta) {
  const abs = Math.abs(delta);
  const sign = delta < 0 ? -1 : 1;
  if (abs <= SCROLL_LINEAR_TH) return delta * SCROLL_SCALE; // linear at low speed
  const curved = abs * (0.3 + 0.012 * abs);
  return sign * Math.min(curved, abs * 3) * SCROLL_SCALE;
}

// Scroll batch flush (rAF-driven, separate from mouse movement)
function flushScr() {
  scrRAF = false;
  if (scrDirty) {
    if (accScrX || accScrY) { S({ a: 'scr', x: accScrX, y: accScrY }); accScrX = accScrY = 0; }
    scrDirty = false;
  }
}
function scheduleScr() {
  scrDirty = true;
  if (!scrRAF) { scrRAF = true; requestAnimationFrame(flushScr); }
}

// Inertia scrolling (§1.5, §3.4) — exponential decay, time-normalized
function startInertia(velocity) {
  if (Math.abs(velocity) < INERTIA_STOP_TH) return;
  stopInertia();
  inertiaVelocity = velocity;
  inertiaActive = true;
  let lastT = performance.now();
  function tick(now) {
    if (!inertiaActive) return;
    const dt = Math.min((now - lastT) / 1000, 0.05);
    lastT = now;
    inertiaVelocity *= Math.pow(INERTIA_RATE, dt * 60); // time-normalized (§1.5)
    if (Math.abs(inertiaVelocity) < INERTIA_STOP_TH) { stopInertia(); return; }
    const scrDelta = inertiaVelocity * dt * 60;
    scrFrac += scrDelta;
    const toSend = Math.trunc(scrFrac);
    if (toSend !== 0) { accScrY += toSend; scrFrac -= toSend; scheduleScr(); }
    inertiaRAF = requestAnimationFrame(tick);
  }
  inertiaRAF = requestAnimationFrame(tick);
}
function stopInertia() {
  inertiaActive = false; inertiaVelocity = 0;
  if (inertiaRAF) { cancelAnimationFrame(inertiaRAF); inertiaRAF = null; }
}

// Gesture state indicator tags
function showTag(iconId, text) {
  scrollIcon.querySelector('use').setAttribute('xlink:href', '#' + iconId);
  scrollText.textContent = text;
  scrollTag.style.display = 'flex';
}
function hideTag() { scrollTag.style.display = 'none'; }

// ─── Gesture disambiguation ────────────────────────
const DETECT_MS = 250;

function detectGesture() {
  const ids = Object.keys(fingers);
  if (ids.length < 2) return;
  const f0 = fingers[ids[0]], f1 = fingers[ids[1]];
  const dCurrent = Math.hypot(f0.x - f1.x, f0.y - f1.y);
  const dInitial = Math.hypot(f0.sx - f1.sx, f0.sy - f1.sy);
  const distChange = dInitial > 0 ? Math.abs(dCurrent - dInitial) / dInitial : 0;
  // Centroid movement (scroll indicator)
  const centroidDx = (f0.x + f1.x) / 2 - (f0.sx + f1.sx) / 2;
  const centroidDy = (f0.y + f1.y) / 2 - (f0.sy + f1.sy) / 2;
  const centroidDist = Math.hypot(centroidDx, centroidDy);
  // Pinch: distance change is significant AND dominates over centroid movement (§3.3)
  // This prevents scrolling from triggering pinch when fingers naturally change spacing
  const pinchDominant = distChange > PINCH_TH && (centroidDist < 5 || distChange * dInitial > centroidDist * 0.5);
  if (pinchDominant) {
    gesture = 'pinch';
    pinchD0 = dCurrent;
    pinchAcc = 0;
    showTag('icon-a-075_shuangzhigundong', '缩放');
    return;
  }
  // Scroll: both fingers moving same direction (§3.3)
  const dot = (f0.x - f0.sx) * (f1.x - f1.sx) + (f0.y - f0.sy) * (f1.y - f1.sy);
  if (dot > 0 && (Math.abs(centroidDx) > TH || Math.abs(centroidDy) > TH)) {
    gesture = 'scroll';
    scrFrac = 0; scrFracX = 0; scrFracY = 0; scrollTickDist = 0; lastScrollTickT = 0;
    showTag('icon-a-075_shuangzhigundong', '滚动');
    return;
  }
  if (Date.now() - detectStart > DETECT_MS) {
    gesture = 'scroll';
    scrFrac = 0; scrFracX = 0; scrFracY = 0;
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
    lastMoveT = now; smoothedSpeed = 0; prevDx = 0; prevDy = 0;
    mvAccX = 0; mvAccY = 0;
    stopInertia();
    clearTimeout(pressTimer);
    pressTimer = setTimeout(() => {
      if (!moved && gesture === 'none' && touchActive) {
        pressing = true; S({ a: 'md', b: 1 }); hapticDragStart();
        gesture = 'drag';
        showTag('icon-tuodong', '拖动');
      }
    }, 400);
  }

  if (e.touches.length === 2) {
    clearTimeout(pressTimer);
    stopInertia();
    if (gesture === 'none' || gesture === 'drag') {
      if (pressing) { pressing = false; S({ a: 'mu', b: 1 }); }
      gesture = 'detecting';
      detectStart = now;
      twoFingerMovedDist = 0;
      const ids = Object.keys(fingers);
      for (const id of ids) { fingers[id].sx = fingers[id].x; fingers[id].sy = fingers[id].y; }
      showTag('icon-a-075_shuangzhigundong', '检测中...');
    }
  }
}, { passive: false });

tp.addEventListener('touchmove', e => {
  e.preventDefault();
  const now = Date.now();

  // ── Two-finger gestures ──
  if (e.touches.length >= 2) {
    const ids = Object.keys(fingers);
    if (ids.length < 2) { for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } } return; }
    const f0 = fingers[ids[0]], f1 = fingers[ids[1]];

    if (gesture === 'detecting') {
      for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } }
      // Track max per-finger movement for tap detection
      const d0 = Math.hypot(f0.x - f0.sx, f0.y - f0.sy);
      const d1 = Math.hypot(f1.x - f1.sx, f1.y - f1.sy);
      twoFingerMovedDist = Math.max(d0, d1);
      detectGesture();
      return;
    }

    if (gesture === 'pinch') {
      const t0 = e.touches[0], t1 = e.touches[1];
      const d = Math.hypot(t0.clientX - t1.clientX, t0.clientY - t1.clientY);
      if (pinchD0 > 0) {
        pinchAcc += Math.log(d / pinchD0);
        if (Math.abs(pinchAcc) > 0.15) {
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
      const dx = (f0.x + f1.x) / 2 - (f0.sx + f1.sx) / 2;
      const dy = -((f0.y + f1.y) / 2 - (f0.sy + f1.sy) / 2); // negate for natural scroll
      scrollTickStep(Math.hypot(dx, dy));
      const cdx = scrollCurve(dx);
      const cdy = scrollCurve(dy);
      // Track scroll velocity for inertia (§1.5)
      const scrDt = Math.max(now - (f0._lastScrT || now), 1);
      f0._lastScrT = now;
      const instantScrV = cdy / scrDt * 16;
      const VEL_ALPHA = 0.4;
      inertiaVelocity = VEL_ALPHA * instantScrV + (1 - VEL_ALPHA) * (inertiaVelocity || 0);
      // Float accumulation for sub-pixel smooth scroll (prevents truncation dead zone)
      scrFracX += cdx;
      scrFracY += cdy;
      const ix = Math.trunc(scrFracX);
      const iy = Math.trunc(scrFracY);
      if (ix !== 0 || iy !== 0) {
        accScrX += ix; accScrY += iy;
        scrFracX -= ix; scrFracY -= iy; // retain fractional remainder
        scheduleScr();
      }
      // Update start positions for continuous delta
      f0.sx = f0.x; f0.sy = f0.y;
      f1.sx = f1.x; f1.sy = f1.y;
      for (const t of e.changedTouches) { const f = fingers[t.identifier]; if (f) { f.x = t.clientX; f.y = t.clientY; } }
      return;
    }
  }

  // ── Single-finger mouse movement / drag ──
  if (e.touches.length === 1 && (gesture === 'none' || gesture === 'drag')) {
    const t = e.touches[0], f = fingers[t.identifier];
    if (!f) return;
    const rawDx = t.clientX - f.x, rawDy = t.clientY - f.y;
    if (Math.abs(t.clientX - f.sx) > TH || Math.abs(t.clientY - f.sy) > TH) {
      moved = true; if (!pressing && gesture === 'none') clearTimeout(pressTimer);
    }

    // ── Pointer algorithm pipeline ──
    const now2 = Date.now();
    // 1. EMA delta smoothing (§2.2) — smooth noise while preserving intent
    const sdx = DELTA_SMOOTH * rawDx + (1 - DELTA_SMOOTH) * prevDx;
    const sdy = DELTA_SMOOTH * rawDy + (1 - DELTA_SMOOTH) * prevDy;
    prevDx = sdx; prevDy = sdy;

    // 2. EMA velocity for acceleration (§2.2)
    const dt = Math.max(now2 - lastMoveT, 1);
    const instantSpeed = Math.hypot(Math.abs(sdx), Math.abs(sdy)) / dt; // px/ms
    const SPEED_EMA = 0.3;
    smoothedSpeed = SPEED_EMA * instantSpeed + (1 - SPEED_EMA) * smoothedSpeed;
    lastMoveT = now2;

    // 3. Adaptive acceleration (§3.1)
    const multiplier = calcAccel(smoothedSpeed);

    // 4. Sub-pixel accumulation (§3.5) — float accumulator, send integer part
    mvAccX += sdx * multiplier;
    mvAccY += sdy * multiplier;
    const ix = Math.trunc(mvAccX);
    const iy = Math.trunc(mvAccY);
    if (ix !== 0 || iy !== 0) {
      mvAccX -= ix; // retain fractional remainder
      mvAccY -= iy;
      S({ a: 'mv', x: ix, y: iy }); // send immediately (no rAF batching)
    }

    f.x = t.clientX; f.y = t.clientY;
  }
}, { passive: false });

tp.addEventListener('touchend', e => {
  e.preventDefault();
  const now = Date.now();
  for (const t of e.changedTouches) delete fingers[t.identifier];
  clearTimeout(pressTimer);

  // ── All fingers up ──
  if (e.touches.length === 0) {
    touchActive = false;
    if (pressing) {
      pressing = false; S({ a: 'mu', b: 1 }); hapticDragEnd(); hideTag();
      gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    // Two-finger tap → right click (§5.2, §6.1)
    if (gesture === 'detecting' && now - detectStart < TAP_TIME_TH && twoFingerMovedDist < TAP_MOVE_TH) {
      S({ a: 'clk', b: 3 });
      const t = e.changedTouches[0];
      if (t) rip(t.clientX, t.clientY, '#58a6ff');
      hideTag(); gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'scroll') {
      startInertia(inertiaVelocity); // inertia scrolling (§1.5)
      hideTag(); gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'pinch') {
      hideTag(); gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0;
      return;
    }
    if (gesture === 'none' && !moved && now - tStart < 250) {
      const t = e.changedTouches[0];
      if (t) {
        const dt = now - lastTapT, dd = Math.hypot(t.clientX - lastTapX, t.clientY - lastTapY);
        if (dt < 350 && dd < 50) { S({ a: 'dbl' }); hapticDoubleTap(); rip(t.clientX, t.clientY, '#f85149'); lastTapT = 0; }
        else { S({ a: 'clk', b: 1 }); hapticTap(); rip(t.clientX, t.clientY, '#3fb950'); lastTapT = now; lastTapX = t.clientX; lastTapY = t.clientY; }
      }
    }
    gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0; hideTag();
    return;
  }

  // ── Some fingers still down ──
  if (e.touches.length < 2) {
    // If we were in 'detecting' (two-finger), keep the state —
    // the second finger might lift imminently (staggered lift for tap).
    // Only reset if gesture was already resolved (scroll/pinch/drag).
    if (gesture !== 'detecting' && gesture !== 'none' && gesture !== 'drag') {
      if (e.touches.length === 1) {
        const rt = e.touches[0];
        const rf = fingers[rt.identifier];
        if (rf) { rf.x = rt.clientX; rf.y = rt.clientY; }
      }
      hideTag(); gesture = 'none'; scrFrac = 0; scrFracX = 0; scrFracY = 0; pinchD0 = 0; pinchAcc = 0;
    }
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
  const opening = fkPanel.classList.contains('hidden');
  fkPanel.classList.toggle('hidden');
  fkToggle.classList.toggle('active');
  osk.classList.toggle('fk-open', opening);
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
  btn.addEventListener('pointerdown', () => hapticBtnPress());
  btn.addEventListener('click', () => sendKey(btn.dataset.key));
});

document.querySelectorAll('.fk.mod').forEach(btn => {
  btn.addEventListener('pointerdown', () => hapticBtnPress());
  btn.addEventListener('click', () => {
    const mod = btn.dataset.mod;
    modState[mod] = !modState[mod];
    btn.classList.toggle('active', modState[mod]);
  });
});

document.querySelectorAll('.fk.combo').forEach(btn => {
  btn.addEventListener('pointerdown', () => hapticBtnPress());
  btn.addEventListener('click', () => {
    S({ a: 'key', k: btn.dataset.key });
    flash();
  });
});

fkPanel.addEventListener('touchstart', e => e.stopPropagation(), { passive: true });
fkPanel.addEventListener('touchmove', e => e.stopPropagation(), { passive: true });
fkPanel.addEventListener('touchend', e => e.stopPropagation(), { passive: true });

// ─── IME Refresh ──────────────────────────────────────
function refreshIme() {
  if (!hasControl) return;
  S({ a: 'ime_refresh' });
  hapticBtnPress();
}

// ─── Init ────────────────────────────────────────────
connect();
