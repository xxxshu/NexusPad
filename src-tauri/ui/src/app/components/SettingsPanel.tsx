import { useState, useEffect } from "react";
import { motion, AnimatePresence } from "motion/react";
import { Keyboard, Github, ScrollText, Usb, Bluetooth } from "lucide-react";
import { invoke } from "@tauri-apps/api/core";
import { open } from "@tauri-apps/plugin-shell";

function Toggle({ checked, onChange }: { checked: boolean; onChange: (v: boolean) => void }) {
  return (
    <button
      onClick={() => onChange(!checked)}
      style={{
        width: 44,
        height: 24,
        borderRadius: 12,
        background: checked ? "#08A1F5" : "#c5dff0",
        border: "none",
        cursor: "pointer",
        position: "relative",
        transition: "background 0.25s",
        flexShrink: 0,
        padding: 0,
      }}
    >
      <motion.div
        animate={{ x: checked ? 22 : 2 }}
        transition={{ type: "spring", stiffness: 500, damping: 35 }}
        style={{
          position: "absolute",
          top: 3,
          width: 18,
          height: 18,
          borderRadius: "50%",
          background: "#fff",
          boxShadow: "0 1px 3px rgba(0,0,0,0.18)",
        }}
      />
    </button>
  );
}

function SectionCard({ children }: { children: React.ReactNode }) {
  return (
    <div
      style={{
        background: "#EBF6FF",
        border: "1px solid rgba(0,98,171,0.12)",
        borderRadius: 12,
        padding: "18px 20px",
        display: "flex",
        flexDirection: "column",
        gap: 14,
      }}
    >
      {children}
    </div>
  );
}

function SectionLabel({ label }: { label: string }) {
  return (
    <div style={{ fontSize: 11, fontWeight: 600, letterSpacing: "0.12em", textTransform: "uppercase", color: "#5a8fb5" }}>
      {label}
    </div>
  );
}

function Row({ label, children, hint }: { label: string; children: React.ReactNode; hint?: string }) {
  return (
    <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
      <div>
        <div style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>{label}</div>
        {hint && <div style={{ color: "#5a8fb5", fontSize: 12, marginTop: 1 }}>{hint}</div>}
      </div>
      {children}
    </div>
  );
}

function GeneralTab() {
  const [port, setPort] = useState("8765");
  const [portError, setPortError] = useState("");
  const [autoStart, setAutoStart] = useState(false);
  const [minimizeToTray, setMinimizeToTray] = useState(true);
  const [imeKey, setImeKey] = useState("");
  const [imeCustom, setImeCustom] = useState("");
  const [imeStatus, setImeStatus] = useState("");
  const [vigemInstalled, setVigemInstalled] = useState<boolean | null>(null);
  const [usbDriverOk, setUsbDriverOk] = useState<boolean | null>(null);
  const [usbDiag, setUsbDiag] = useState<string | null>(null);

  const inputStyle: React.CSSProperties = {
    background: "#fff",
    border: "1px solid rgba(0,98,171,0.18)",
    borderRadius: 7,
    color: "#003472",
    fontSize: 13,
    padding: "6px 10px",
    outline: "none",
    fontFamily: "system-ui, sans-serif",
    boxSizing: "border-box",
  };

  // Load initial data
  useEffect(() => {
    invoke("get_status").then((s: any) => {
      if (s.port) setPort(String(s.port));
    }).catch(() => {});
    invoke("get_ime_config").then((cfg: any) => {
      const key = cfg.ime_toggle_key || "";
      setImeKey(key);
      const isPreset = ["", "shift", "ctrl+space", "Caps_Lock"].includes(key);
      if (!isPreset && key) setImeCustom(key);
    }).catch(() => {});
    invoke("get_autostart").then((enabled: any) => {
      setAutoStart(!!enabled);
    }).catch(() => {});
    invoke("get_minimize_to_tray").then((enabled: any) => {
      setMinimizeToTray(!!enabled);
    }).catch(() => {});
    invoke("check_vigem_installed").then((installed: any) => {
      setVigemInstalled(!!installed);
    }).catch(() => { setVigemInstalled(false); });
    invoke("check_usb_driver").then((ok: any) => {
      setUsbDriverOk(!!ok);
    }).catch(() => { setUsbDriverOk(false); });
  }, []);

  // Port change handler
  function handlePortChange(val: string) {
    setPort(val);
    setPortError("");
  }

  // Autostart toggle
  async function handleAutostartChange(enable: boolean) {
    try {
      await invoke("set_autostart", { enable });
      setAutoStart(enable);
    } catch (e) {
      console.error("Autostart toggle failed:", e);
    }
  }

  // IME save
  async function saveIme() {
    const customVal = imeCustom.trim();
    const keyToSave = customVal || imeKey || null;
    try {
      await invoke("save_ime_config", { ime_toggle_key: keyToSave || null });
      setImeKey(keyToSave || "");
      if (!customVal) setImeCustom("");
      setImeStatus("✓ 已保存（下次启动服务生效）");
      setTimeout(() => setImeStatus(""), 3000);
    } catch (e) {
      setImeStatus("保存失败: " + e);
    }
  }

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <SectionCard>
        <SectionLabel label="端口设置" />
        <Row label="监听端口" hint="重启服务后生效">
          <div style={{ display: "flex", alignItems: "center", gap: 7 }}>
            <input
              data-port-input
              value={port}
              onChange={(e) => handlePortChange(e.target.value)}
              style={{
                ...inputStyle,
                width: 80,
                textAlign: "center",
                ...(portError ? { borderColor: "#e53e3e", background: "#fff5f5" } : {}),
              }}
            />
            <button
              onClick={() => { setPort("8765"); setPortError(""); }}
              style={{
                background: "#fff",
                border: "1px solid rgba(0,98,171,0.2)",
                borderRadius: 7,
                color: "#0062AB",
                fontSize: 12,
                padding: "5px 10px",
                cursor: "pointer",
              }}
            >
              重置
            </button>
          </div>
        </Row>
        {portError && <div style={{ color: "#e53e3e", fontSize: 12 }}>{portError}</div>}
      </SectionCard>

      <SectionCard>
        <SectionLabel label="自定义快捷键" />
        <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
          <div>
            <div style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>输入法切换快捷键</div>
            <div style={{ color: "#5a8fb5", fontSize: 12, marginTop: 1 }}>当手机端"中/EN"键不起作用时，配置适合你电脑的快捷键</div>
          </div>
          <div style={{ display: "flex", gap: 6, flexWrap: "wrap" }}>
            {[
              { key: "", label: "默认" },
              { key: "shift", label: "Shift" },
              { key: "ctrl+space", label: "Ctrl+Space" },
              { key: "Caps_Lock", label: "CapsLock" },
            ].map((p) => (
              <button
                key={p.key}
                onClick={() => { setImeKey(p.key); setImeCustom(""); }}
                style={{
                  padding: "6px 12px",
                  border: imeKey === p.key && !imeCustom ? "1px solid #08A1F5" : "1px solid rgba(0,98,171,0.15)",
                  borderRadius: 6,
                  background: imeKey === p.key && !imeCustom ? "#08A1F5" : "#fff",
                  color: imeKey === p.key && !imeCustom ? "#fff" : "#5a8fb5",
                  fontSize: 12,
                  fontWeight: 500,
                  cursor: "pointer",
                  transition: "all .15s",
                  fontFamily: "system-ui, sans-serif",
                }}
              >
                {p.label}
              </button>
            ))}
          </div>
          <div style={{ display: "flex", gap: 8, alignItems: "center" }}>
            <input
              value={imeCustom}
              onChange={(e) => setImeCustom(e.target.value)}
              placeholder="自定义，如 ctrl+shift"
              autoComplete="off"
              style={{ ...inputStyle, flex: 1 }}
            />
            <button
              onClick={saveIme}
              style={{
                background: "#08A1F5", border: "none", borderRadius: 6,
                color: "#fff", fontSize: 12, fontWeight: 600,
                padding: "6px 14px", cursor: "pointer",
              }}
            >
              保存
            </button>
          </div>
          {imeStatus && (
            <div style={{
              fontSize: 11,
              color: imeStatus.startsWith("✓") ? "#22c55e" : "#e53e3e",
            }}>
              {imeStatus}
            </div>
          )}
        </div>
      </SectionCard>

      <SectionCard>
        <SectionLabel label="窗口行为" />
        <Row label="开机自启">
          <Toggle checked={autoStart} onChange={handleAutostartChange} />
        </Row>
        <div style={{ height: 1, background: "rgba(0,98,171,0.08)" }} />
        <Row label="关闭时最小化到托盘" hint="关闭按钮不退出程序">
          <Toggle checked={minimizeToTray} onChange={async (v) => {
            try { await invoke("set_minimize_to_tray", { enable: v }); setMinimizeToTray(v); } catch {}
          }} />
        </Row>
      </SectionCard>

      <SectionCard>
        <SectionLabel label="游戏手柄驱动" />
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <div style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>ViGEmBus 驱动</div>
            <div style={{ color: "#5a8fb5", fontSize: 12, marginTop: 1 }}>让 NexusPad 创建虚拟手柄控制器</div>
          </div>
          {vigemInstalled === null ? (
            <div style={{ fontSize: 12, color: "#5a8fb5" }}>检测中...</div>
          ) : vigemInstalled ? (
            <div style={{
              background: "#dcfce7", border: "1px solid #86efac", borderRadius: 6,
              color: "#16a34a", fontSize: 12, padding: "3px 10px", fontWeight: 600,
            }}>
              ✓ 已安装
            </div>
          ) : (
            <div style={{
              background: "#fee2e2", border: "1px solid #fca5a5", borderRadius: 6,
              color: "#dc2626", fontSize: 12, padding: "3px 10px", fontWeight: 600,
            }}>
              ✗ 未安装
            </div>
          )}
        </div>
        {!vigemInstalled && (
          <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 4 }}>
            <button
              onClick={() => open("https://github.com/ViGEm/ViGEmBus/releases/latest")}
              style={{
                background: "#fff", border: "1px solid rgba(0,98,171,0.2)",
                borderRadius: 7, color: "#0062AB", fontSize: 12,
                padding: "6px 12px", cursor: "pointer", alignSelf: "flex-start",
                display: "inline-flex", alignItems: "center", gap: 5,
                fontFamily: "system-ui, sans-serif",
              }}
            >
              下载 ViGEmBus
            </button>
            <div style={{ color: "#5a8fb5", fontSize: 11 }}>
              安装后需要重启电脑才能生效
            </div>
          </div>
        )}
      </SectionCard>

      <SectionCard>
        <SectionLabel label="USB 连接" />
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <div style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>USB 驱动状态</div>
            <div style={{ color: "#5a8fb5", fontSize: 12, marginTop: 1 }}>支持通过 USB 线直接连接手机（AOA 协议）</div>
          </div>
          {usbDriverOk === null ? (
            <div style={{ fontSize: 12, color: "#5a8fb5" }}>检测中...</div>
          ) : usbDriverOk ? (
            <div style={{
              background: "#dcfce7", border: "1px solid #86efac", borderRadius: 6,
              color: "#16a34a", fontSize: 12, padding: "3px 10px", fontWeight: 600,
            }}>
              ✓ 正常
            </div>
          ) : (
            <div style={{
              background: "#fef3c7", border: "1px solid #fcd34d", borderRadius: 6,
              color: "#d97706", fontSize: 12, padding: "3px 10px", fontWeight: 600,
            }}>
              ⚠ 需要检查
            </div>
          )}
        </div>
        <div style={{ display: "flex", flexDirection: "column", gap: 8, marginTop: 4 }}>
          <div style={{ color: "#5a8fb5", fontSize: 12 }}>
            使用 USB 连接：
          </div>
          <ol style={{ color: "#5a8fb5", fontSize: 12, margin: 0, paddingLeft: 18, lineHeight: 1.8 }}>
            <li>用 USB 线连接手机到电脑</li>
            <li>确保手机已开启 USB 调试</li>
            <li>在手机端选择 USB 连接方式</li>
          </ol>
          <div style={{ display: "flex", gap: 8 }}>
            <button
              onClick={() => invoke("check_usb_driver").then((ok: any) => setUsbDriverOk(!!ok)).catch(() => setUsbDriverOk(false))}
              style={{
                background: "#08A1F5", border: "none",
                borderRadius: 7, color: "#fff", fontSize: 12,
                padding: "6px 12px", cursor: "pointer",
                fontFamily: "system-ui, sans-serif", fontWeight: 600,
              }}
            >
              刷新状态
            </button>
            <button
              onClick={() => invoke("diagnose_usb").then((r: any) => setUsbDiag(String(r))).catch((e) => setUsbDiag("诊断失败: " + e))}
              style={{
                background: "#fff", border: "1px solid rgba(0,98,171,0.2)",
                borderRadius: 7, color: "#0062AB", fontSize: 12,
                padding: "6px 12px", cursor: "pointer",
                fontFamily: "system-ui, sans-serif",
              }}
            >
              运行诊断
            </button>
          </div>
          {usbDiag && (
            <pre style={{
              background: "#fff", border: "1px solid rgba(0,98,171,0.15)",
              borderRadius: 7, padding: "10px 12px", fontSize: 11,
              color: "#003472", whiteSpace: "pre-wrap", lineHeight: 1.6,
              fontFamily: "Consolas, monospace", maxHeight: 200, overflow: "auto",
            }}>
              {usbDiag}
            </pre>
          )}
        </div>
      </SectionCard>
    </div>
  );
}

function AboutTab() {
  const [version, setVersion] = useState("0.2.0");
  const [anonymous, setAnonymous] = useState(false);
  const [contact, setContact] = useState("");

  useEffect(() => {
    invoke("app_version").then((v: any) => setVersion(v)).catch(() => {});
  }, []);

  const linkBtn: React.CSSProperties = {
    display: "inline-flex", alignItems: "center", gap: 6,
    background: "#fff", border: "1px solid rgba(0,98,171,0.18)",
    borderRadius: 8, color: "#0062AB", fontSize: 13,
    padding: "7px 14px", cursor: "pointer", textDecoration: "none",
  };

  const inputStyle: React.CSSProperties = {
    background: "#fff", border: "1px solid rgba(0,98,171,0.18)",
    borderRadius: 7, color: "#003472", fontSize: 13,
    padding: "7px 10px", outline: "none",
    fontFamily: "system-ui, sans-serif",
    width: "100%", boxSizing: "border-box",
  };

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 12 }}>
      <SectionCard>
        <SectionLabel label="版本信息" />
        <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between" }}>
          <div>
            <div style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>NexusPad</div>
            <div style={{ color: "#5a8fb5", fontSize: 12, marginTop: 2 }}>版本 {version} · 桌面端</div>
          </div>
          <div
            style={{
              background: "#FFEA7C", border: "none", borderRadius: 6,
              color: "#003472", fontSize: 11, padding: "3px 10px",
              letterSpacing: "0.06em", fontWeight: 600,
            }}
          >
            STABLE
          </div>
        </div>
        <div style={{ height: 1, background: "rgba(0,98,171,0.08)" }} />
        <div style={{ display: "flex", gap: 8 }}>
          <button onClick={() => open("https://github.com/xxxshu/remote-touchpad")} style={linkBtn}>
            <Github size={13} /> Github
          </button>
          <button onClick={() => open("https://github.com/xxxshu/remote-touchpad/releases")} style={linkBtn}>
            <ScrollText size={13} /> 更新日志
          </button>
        </div>
      </SectionCard>

      <SectionCard>
        <SectionLabel label="用户反馈" />
        <Row label="匿名反馈" hint={anonymous ? "不会收集任何个人信息" : "开启后隐藏联系方式"}>
          <Toggle checked={anonymous} onChange={setAnonymous} />
        </Row>
        <AnimatePresence>
          {!anonymous && (
            <motion.div
              initial={{ opacity: 0, height: 0 }}
              animate={{ opacity: 1, height: "auto" }}
              exit={{ opacity: 0, height: 0 }}
              transition={{ duration: 0.22 }}
              style={{ overflow: "hidden" }}
            >
              <div style={{ display: "flex", flexDirection: "column", gap: 6, paddingTop: 2 }}>
                <div style={{ color: "#5a8fb5", fontSize: 12 }}>填写联系方式，便于我们跟进您的反馈（可选）</div>
                <input value={contact} onChange={(e) => setContact(e.target.value)} placeholder="邮箱 / 微信 / 其他联系方式" style={inputStyle} />
              </div>
            </motion.div>
          )}
        </AnimatePresence>
        <div style={{ display: "flex", flexDirection: "column", gap: 7 }}>
          <textarea
            placeholder="描述您遇到的问题或建议..."
            rows={3}
            style={{ ...inputStyle, resize: "none" } as React.CSSProperties}
          />
          <button
            disabled
            title="即将开放"
            style={{
              alignSelf: "flex-end", background: "#08A1F5", border: "none",
              borderRadius: 8, color: "#fff", fontSize: 13, fontWeight: 600,
              padding: "7px 18px", cursor: "not-allowed", letterSpacing: "0.03em",
              opacity: 0.5,
            }}
          >
            提交反馈
          </button>
        </div>
      </SectionCard>
    </div>
  );
}

export function SettingsPanel() {
  const [tab, setTab] = useState<"general" | "about">("general");

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 0 }}>
      {/* tabs */}
      <div style={{ display: "flex", gap: 3, padding: "0 0 14px" }}>
        {(["general", "about"] as const).map((t) => {
          const labels = { general: "通用", about: "关于" };
          const active = tab === t;
          return (
            <button
              key={t}
              onClick={() => setTab(t)}
              style={{
                background: active ? "#08A1F5" : "transparent",
                border: active ? "none" : "1px solid rgba(0,98,171,0.15)",
                borderRadius: 8,
                color: active ? "#fff" : "#5a8fb5",
                fontSize: 13,
                fontWeight: active ? 600 : 400,
                padding: "6px 16px",
                cursor: "pointer",
                transition: "all 0.18s",
              }}
            >
              {labels[t]}
            </button>
          );
        })}
      </div>

      {/* content */}
      <div>
        <AnimatePresence mode="wait">
          <motion.div
            key={tab}
            initial={{ opacity: 0, y: 5 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -5 }}
            transition={{ duration: 0.16 }}
          >
            {tab === "general" ? <GeneralTab /> : <AboutTab />}
          </motion.div>
        </AnimatePresence>
      </div>
    </div>
  );
}
