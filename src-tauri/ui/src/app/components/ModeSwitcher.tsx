import { motion } from "motion/react";
import { Wifi, Usb, Bluetooth } from "lucide-react";

export type ConnMode = "wifi" | "usb" | "ble";

interface ModeSwitcherProps {
  value: ConnMode;
  onChange: (mode: ConnMode) => void;
  disabled?: boolean;
}

const MODES: { mode: ConnMode; label: string; Icon: typeof Wifi }[] = [
  { mode: "wifi", label: "局域网", Icon: Wifi },
  { mode: "usb", label: "USB", Icon: Usb },
  { mode: "ble", label: "蓝牙", Icon: Bluetooth },
];

/**
 * 连接模式分段滑块 — 桌面端首页使用。
 * 与手机端连接页的滑块布局保持一致：药丸形轨道 + 滑动的白色高亮块。
 */
export function ModeSwitcher({ value, onChange, disabled = false }: ModeSwitcherProps) {
  const index = MODES.findIndex((m) => m.mode === value);
  const activeIdx = index < 0 ? 0 : index;

  return (
    <div style={{ display: "flex", flexDirection: "column", gap: 8 }}>
      <div
        style={{
          fontSize: 11,
          fontWeight: 600,
          letterSpacing: "0.12em",
          textTransform: "uppercase",
          color: "#5a8fb5",
        }}
      >
        连接模式
      </div>
      <div
        style={{
          position: "relative",
          display: "flex",
          height: 44,
          padding: 3,
          borderRadius: 11,
          background: "#dde8f4",
          opacity: disabled ? 0.55 : 1,
          transition: "opacity 0.2s",
        }}
      >
        {/* 滑动高亮块 */}
        <motion.div
          animate={{ left: `calc(${activeIdx} * (100% - 6px) / 3 + 3px)` }}
          transition={{ type: "spring", stiffness: 420, damping: 34 }}
          style={{
            position: "absolute",
            top: 3,
            width: "calc((100% - 6px) / 3)",
            height: 38,
            borderRadius: 8,
            background: "#fff",
            boxShadow: "0 1px 4px rgba(20,70,160,0.12)",
            zIndex: 1,
          }}
        />
        {MODES.map(({ mode, label, Icon }) => {
          const active = mode === value;
          return (
            <button
              key={mode}
              onClick={() => !disabled && onChange(mode)}
              disabled={disabled}
              style={{
                flex: 1,
                position: "relative",
                zIndex: 2,
                display: "flex",
                alignItems: "center",
                justifyContent: "center",
                gap: 6,
                border: "none",
                background: "transparent",
                cursor: disabled ? "not-allowed" : "pointer",
                color: active ? "#003472" : "#7ba0c4",
                fontSize: 12.5,
                fontWeight: active ? 700 : 500,
                fontFamily: "system-ui, sans-serif",
                transition: "color 0.2s",
                padding: 0,
              }}
            >
              <Icon size={15} color={active ? "#08A1F5" : "#9bb8d6"} />
              <span>{label}</span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
