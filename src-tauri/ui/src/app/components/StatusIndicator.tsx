import { motion, AnimatePresence } from "motion/react";

interface StatusIndicatorProps {
  connected?: boolean;
  deviceName?: string;
}

export function StatusIndicator({ connected = false, deviceName }: StatusIndicatorProps) {
  const displayName = deviceName || "设备";

  return (
    <div
      style={{
        padding: "14px 18px",
        background: "#EBF6FF",
        borderRadius: "12px",
        border: "1px solid rgba(0,98,171,0.12)",
        display: "flex",
        alignItems: "center",
        gap: "10px",
        userSelect: "none",
      }}
    >
      {/* pulsing dot */}
      <div style={{ position: "relative", flexShrink: 0, width: 10, height: 10 }}>
        <div
          style={{
            width: 10,
            height: 10,
            borderRadius: "50%",
            background: connected ? "#22c55e" : "#e53e3e",
            transition: "background 0.4s",
          }}
        />
        {connected && (
          <motion.div
            animate={{ scale: [1, 1.9, 1], opacity: [0.5, 0, 0.5] }}
            transition={{ duration: 2, repeat: Infinity, ease: "easeInOut" }}
            style={{
              position: "absolute",
              inset: 0,
              borderRadius: "50%",
              background: "rgba(34,197,94,0.45)",
            }}
          />
        )}
      </div>

      {/* text */}
      <AnimatePresence mode="wait">
        <motion.div
          key={connected ? "on" : "off"}
          initial={{ opacity: 0, x: 4 }}
          animate={{ opacity: 1, x: 0 }}
          exit={{ opacity: 0, x: -4 }}
          transition={{ duration: 0.2 }}
          style={{ display: "flex", alignItems: "center", gap: 5, fontFamily: "system-ui, sans-serif" }}
        >
          <span style={{ color: "#003472", fontSize: 13, fontWeight: 500 }}>{displayName}</span>
          <span style={{ color: connected ? "#0062AB" : "#e53e3e", fontSize: 13, transition: "color 0.4s" }}>
            {connected ? "连接成功" : "未连接"}
          </span>
        </motion.div>
      </AnimatePresence>

      <div style={{ marginLeft: "auto", color: "#c5dff0", fontSize: 11, letterSpacing: "0.06em", fontFamily: "system-ui" }}>
        {connected ? "ACTIVE" : "IDLE"}
      </div>
    </div>
  );
}
