import { useState, useEffect, useCallback, useRef } from "react";
import { Settings, ArrowLeft, Minus, Square, X } from "lucide-react";
import { motion, AnimatePresence } from "motion/react";
import { invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWindow, LogicalSize } from "@tauri-apps/api/window";
import { PinButtonModule, PinModuleHandle } from "./components/PinButtonModule";
import { StatusIndicator } from "./components/StatusIndicator";
import { SettingsPanel } from "./components/SettingsPanel";

function WindowControls() {
  const btnStyle: React.CSSProperties = {
    display: "flex", alignItems: "center", justifyContent: "center",
    width: 32, height: 26, border: "none", background: "transparent",
    cursor: "pointer", borderRadius: 4, color: "#5a8fb5", padding: 0,
    transition: "all 0.15s",
  };
  const win = getCurrentWindow();
  return (
    <div style={{ display: "flex", gap: 2, marginLeft: 8 }}>
      <button style={btnStyle} onClick={() => win.minimize().catch(() => {})}
        onMouseEnter={e => { e.currentTarget.style.background = "rgba(0,98,171,0.08)"; e.currentTarget.style.color = "#003472"; }}
        onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "#5a8fb5"; }}
        title="最小化"><Minus size={14} /></button>
      <button style={btnStyle} onClick={() => win.toggleMaximize().catch(() => {})}
        onMouseEnter={e => { e.currentTarget.style.background = "rgba(0,98,171,0.08)"; e.currentTarget.style.color = "#003472"; }}
        onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "#5a8fb5"; }}
        title="最大化"><Square size={12} /></button>
      <button style={{ ...btnStyle }} onClick={() => win.close().catch(() => {})}
        onMouseEnter={e => { e.currentTarget.style.background = "#e53e3e"; e.currentTarget.style.color = "#fff"; }}
        onMouseLeave={e => { e.currentTarget.style.background = "transparent"; e.currentTarget.style.color = "#5a8fb5"; }}
        title="关闭"><X size={14} /></button>
    </div>
  );
}

function NexusPadLogo() {
  return (
    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
      <svg width="56" height="56" viewBox="-20 -10 236 216" fill="none" xmlns="http://www.w3.org/2000/svg">
        {/* Block B — medium navy, upper-right, +14° */}
        <g transform="rotate(14, 150, 50)">
          <path d="M 114,28 C 137,19 171,21 190,33 C 193,48 191,70 186,78 C 162,85 132,83 115,73 C 112,59 112,45 114,28 Z" fill="#003472" />
        </g>
        {/* Block C — yellow accent, lower-right, -22° */}
        <g transform="rotate(-22, 150, 156)">
          <path d="M 121,138 C 141,128 169,130 179,142 C 181,155 179,171 174,179 C 154,187 126,185 119,174 C 117,162 118,150 121,138 Z" fill="#FFEA7C" />
        </g>
        {/* Block A — dominant dark pad, -9°, contains eye */}
        <g transform="rotate(-9, 73, 94)">
          <path d="M 9,50 C 48,39 97,37 141,50 C 144,74 143,107 139,134 C 97,141 46,140 9,131 C 6,109 7,81 9,50 Z" fill="#0d1117" />
          <path d="M 24,92 C 48,60 100,54 126,79 C 106,115 48,118 24,92 Z" fill="white" />
          <path d="M 68,84 C 84,60 112,57 126,79 C 114,105 86,109 68,84 Z" fill="#0d1117" />
          <ellipse cx="90" cy="69" rx="12" ry="11" fill="white" />
          <path d="M 24,92 C 50,62 100,55 126,79 C 100,68 50,66 24,92 Z" fill="#0d1117" />
        </g>
      </svg>
      <div>
        <div style={{ fontSize: 17, fontWeight: 700, letterSpacing: "0.03em", color: "#003472", fontFamily: "system-ui, sans-serif", lineHeight: 1.1 }}>NexusPad</div>
        <div style={{ fontSize: 9.5, color: "#5a8fb5", letterSpacing: "0.18em", textTransform: "uppercase", marginTop: 2, fontFamily: "system-ui, sans-serif", fontWeight: 500 }}>Wireless Input</div>
      </div>
    </div>
  );
}

export default function App() {
  const [view, setView] = useState<"main" | "settings">("main");
  const [connected, setConnected] = useState(false);
  const [deviceName, setDeviceName] = useState<string | undefined>();
  const pinRef = useRef<PinModuleHandle>(null);
  const containerRef = useRef<HTMLDivElement>(null);
  const mainRef = useRef<HTMLDivElement>(null);
  const settingsRef = useRef<HTMLDivElement>(null);

  // Animated window height — smoothly transitions between views
  const winRef = useRef(getCurrentWindow());
  const animRef = useRef<number | null>(null);
  const targetLogicalHRef = useRef(0);
  const currentLogicalHRef = useRef(386); // initial from tauri.conf.json

  const animateToLogicalHeight = useCallback((targetLogicalH: number) => {
    targetLogicalHRef.current = targetLogicalH;
    if (animRef.current != null) return; // already animating

    const step = () => {
      const current = currentLogicalHRef.current;
      const target = targetLogicalHRef.current;
      const diff = target - current;

      if (Math.abs(diff) <= 2) {
        currentLogicalHRef.current = target;
        winRef.current.setSize(new LogicalSize(420, target)).catch(() => {});
        animRef.current = null;
        return;
      }

      const next = Math.round(current + diff * 0.35);
      currentLogicalHRef.current = next;
      winRef.current.setSize(new LogicalSize(420, next)).catch(() => {});
      animRef.current = requestAnimationFrame(step);
    };

    animRef.current = requestAnimationFrame(step);
  }, []);

  useEffect(() => {
    return () => { if (animRef.current != null) cancelAnimationFrame(animRef.current); };
  }, []);

  // ResizeObserver: sync window height to match container content
  useEffect(() => {
    const el = containerRef.current;
    if (!el) return;
    const ro = new ResizeObserver((entries) => {
      for (const entry of entries) {
        const h = Math.ceil(entry.contentRect.height);
        if (h > 200) animateToLogicalHeight(h);
      }
    });
    ro.observe(el);
    return () => ro.disconnect();
  }, [animateToLogicalHeight]);

  const switchView = useCallback((newView: "main" | "settings") => {
    setView(newView);
  }, []);

  // Poll for status
  const pollStatus = useCallback(async () => {
    try {
      const status: any = await invoke("get_status");
      if (status.running) {
        if (status.device_name) {
          setConnected(true);
          setDeviceName(status.device_name);
        }
        if (status.pin) pinRef.current?.updatePin(status.pin);
      }
    } catch {}
  }, []);

  // Listen to Tauri server events
  useEffect(() => {
    const unlistenFns: (() => void)[] = [];

    listen("device-connecting", () => {
      pinRef.current?.showPIN();
      invoke("get_status").then((s: any) => {
        if (s.pin) pinRef.current?.updatePin(s.pin);
      }).catch(() => {});
    }).then(fn => unlistenFns.push(fn));

    listen("device-authenticated", (event: any) => {
      const name = event.payload?.device_name || "设备";
      setConnected(true);
      setDeviceName(name);
      pinRef.current?.showStop();
    }).then(fn => unlistenFns.push(fn));

    listen("device-disconnected", () => {
      setConnected(false);
      setDeviceName(undefined);
      setTimeout(() => {
        invoke("stop_server_cmd").then(() => {
          pinRef.current?.showIdle();
        }).catch(() => {
          pinRef.current?.showIdle();
        });
      }, 500);
    }).then(fn => unlistenFns.push(fn));

    listen("device-connecting-cancelled", () => {
      setTimeout(() => {
        invoke("stop_server_cmd").then(() => {
          pinRef.current?.resetToIdle();
        }).catch(() => {
          pinRef.current?.resetToIdle();
        });
      }, 300);
    }).then(fn => unlistenFns.push(fn));

    pollStatus();
    const interval = setInterval(pollStatus, 3000);

    return () => {
      unlistenFns.forEach(fn => fn());
      clearInterval(interval);
    };
  }, [pollStatus]);

  const isSettings = view === "settings";

  return (
    <div
      ref={containerRef}
      style={{
        background: "#ffffff",
        display: "flex",
        flexDirection: "column",
        fontFamily: "system-ui, -apple-system, sans-serif",
      }}
    >
      {/* header */}
      <div
        data-tauri-drag-region
        style={{
          display: "flex",
          alignItems: "center",
          justifyContent: "space-between",
          padding: "18px 20px 16px",
          borderBottom: "1px solid rgba(0,98,171,0.08)",
          flexShrink: 0,
        }}
      >
        <AnimatePresence mode="wait">
          {!isSettings ? (
            <motion.div key="logo" initial={{ opacity: 0 }} animate={{ opacity: 1 }} exit={{ opacity: 0 }} transition={{ duration: 0.15 }}>
              <NexusPadLogo />
            </motion.div>
          ) : (
            <motion.button
              key="back"
              initial={{ opacity: 0, x: -6 }}
              animate={{ opacity: 1, x: 0 }}
              exit={{ opacity: 0, x: -6 }}
              transition={{ duration: 0.18 }}
              onClick={() => switchView("main")}
              style={{
                display: "flex", alignItems: "center", gap: 6,
                background: "transparent", border: "none",
                color: "#0062AB", fontSize: 14, cursor: "pointer",
                padding: "4px 0", fontWeight: 500,
              }}
            >
              <ArrowLeft size={16} />
              返回
            </motion.button>
          )}
        </AnimatePresence>

        <div style={{ display: "flex", alignItems: "center" }}>
          <AnimatePresence mode="wait">
            {!isSettings ? (
              <motion.button
                key="settings-btn"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.15 }}
                onClick={() => switchView("settings")}
                style={{
                  display: "flex", alignItems: "center", justifyContent: "center",
                  width: 34, height: 34, borderRadius: 9,
                  background: "#EBF6FF", border: "1px solid rgba(0,98,171,0.13)",
                  cursor: "pointer", color: "#5a8fb5", marginRight: 8,
                }}
                onMouseEnter={(e) => {
                  e.currentTarget.style.background = "#dff0fb";
                  e.currentTarget.style.color = "#003472";
                }}
                onMouseLeave={(e) => {
                  e.currentTarget.style.background = "#EBF6FF";
                  e.currentTarget.style.color = "#5a8fb5";
                }}
                title="设置"
              >
                <Settings size={15} />
              </motion.button>
            ) : (
              <motion.div
                key="settings-title"
                initial={{ opacity: 0 }}
                animate={{ opacity: 1 }}
                exit={{ opacity: 0 }}
                transition={{ duration: 0.15 }}
                style={{ color: "#003472", fontSize: 15, fontWeight: 600, letterSpacing: "0.01em", marginRight: 8 }}
              >
                设置
              </motion.div>
            )}
          </AnimatePresence>
          <WindowControls />
        </div>
      </div>

      {/* content */}
      <div ref={containerRef} style={{ position: "relative", flex: 1 }}>
        {/* main view — in flow when active */}
        <div
          ref={mainRef}
          style={{
            padding: "22px 20px 24px",
            display: "flex",
            flexDirection: "column",
            gap: 12,
            transition: "opacity 0.2s ease",
            opacity: isSettings ? 0 : 1,
            position: isSettings ? "absolute" : "relative",
            top: 0, left: 0, right: 0,
            pointerEvents: isSettings ? "none" : "auto",
          }}
        >
          <PinButtonModule ref={pinRef} />
          <StatusIndicator connected={connected} deviceName={deviceName} />
        </div>

        {/* settings view — in flow when active */}
        <div
          ref={settingsRef}
          style={{
            padding: "20px 20px 24px",
            transition: "opacity 0.2s ease",
            opacity: isSettings ? 1 : 0,
            position: isSettings ? "relative" : "absolute",
            top: 0, left: 0, right: 0,
            pointerEvents: isSettings ? "auto" : "none",
          }}
        >
          <SettingsPanel />
        </div>
      </div>

      {/* footer */}
      <div
        style={{
          padding: "10px 20px 14px",
          borderTop: "1px solid rgba(0,98,171,0.06)",
          display: "flex",
          justifyContent: "center",
          flexShrink: 0,
        }}
      >
        <span style={{ color: "#c5dff0", fontSize: 11, letterSpacing: "0.08em", textTransform: "uppercase" }}>
          NexusPad v0.2.0
        </span>
      </div>
    </div>
  );
}
