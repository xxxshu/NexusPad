import { useEffect, useRef, forwardRef, useImperativeHandle } from "react";
import { gsap } from "gsap";
import { invoke } from "@tauri-apps/api/core";

export interface PinModuleHandle {
  showPIN: () => void;
  showStop: () => void;
  showIdle: () => void;
  resetToIdle: () => void;
  updatePin: (pin: string) => void;
}

export type ConnMode = "wifi" | "usb" | "ble";

interface PinModuleProps {
  onStateChange?: (state: "idle" | "qr" | "pin" | "wait" | "done") => void;
  onStopped?: () => void;
  /** 当前连接模式 — wifi 走二维码/PIN 流程，usb/ble 走等待连接流程 */
  connectionMode?: ConnMode;
}

export const PinButtonModule = forwardRef<PinModuleHandle, PinModuleProps>(function PinButtonModule({ onStateChange, onStopped, connectionMode = "wifi" }, ref) {
  const boxRef = useRef<HTMLDivElement>(null);
  const hintRef = useRef<HTMLDivElement>(null);
  const stateRef = useRef<"idle" | "toQR" | "qr" | "toPIN" | "pin" | "toWait" | "wait" | "toDone" | "done">("idle");
  const busyRef = useRef(false);
  const breathTweensRef = useRef<gsap.core.Tween[]>([]);
  const currentPinRef = useRef("------");
  const qrSvgRef = useRef("");
  // 连接模式（用 ref 以便在只初始化一次的事件处理器中读取最新值）
  const modeRef = useRef<ConnMode>(connectionMode);

  // 保持 modeRef 与 prop 同步
  useEffect(() => {
    modeRef.current = connectionMode;
  }, [connectionMode]);

  useEffect(() => {
    const box = boxRef.current!;
    const hint = hintRef.current!;

    const RW = 240, RH = 72, SQ = 200;
    const CORNER_W = 28, CORNER_H = 28;
    const BR = 12;
    const BTN_BLUE = "#3283FF";
    const BTN_RED = "#e53e3e";

    function notifyState(state: "idle" | "qr" | "pin" | "wait" | "done") {
      if (onStateChange) onStateChange(state);
    }

    let waitPulseTween: gsap.core.Tween | null = null;

    function setBoxInstant(w: number, h: number, bg: string, ov?: string) {
      box.style.transition = "none";
      box.style.width = w + "px";
      box.style.height = h + "px";
      box.style.borderRadius = BR + "px";
      box.style.background = bg;
      box.style.display = "flex";
      box.style.alignItems = "center";
      box.style.justifyContent = "center";
      box.style.position = "relative";
      box.style.overflow = ov || "hidden";
      box.style.cursor = "pointer";
    }

    function renderIdle() {
      setBoxInstant(RW, RH, BTN_BLUE);
      box.innerHTML =
        '<span id="label" style="color:#fff;font-size:22px;font-weight:600;letter-spacing:3px;text-transform:uppercase;opacity:0;">Start</span>';
      gsap.to("#label", { opacity: 1, duration: 0.35 });
    }

    function makeCorner(pos: string) {
      const bw = "3px", br = BR + "px", bc = BTN_BLUE;
      let base =
        "position:absolute;width:" + CORNER_W + "px;height:" + CORNER_H + "px;" +
        "border-color:" + bc + ";border-style:solid;border-width:0;";
      if (pos === "tl")
        base += "top:3px;left:3px;border-top-width:" + bw + ";border-left-width:" + bw + ";border-radius:" + br + " 0 0 0;";
      else if (pos === "tr")
        base += "top:3px;right:3px;border-top-width:" + bw + ";border-right-width:" + bw + ";border-radius:0 " + br + " 0 0;";
      else if (pos === "bl")
        base += "bottom:3px;left:3px;border-bottom-width:" + bw + ";border-left-width:" + bw + ";border-radius:0 0 0 " + br + ";";
      else
        base += "bottom:3px;right:3px;border-bottom-width:" + bw + ";border-right-width:" + bw + ";border-radius:0 0 " + br + " 0;";
      return '<div id="fc' + pos.toUpperCase() + '" class="fc" style="' + base + '"></div>';
    }

    function renderQR() {
      setBoxInstant(RW, RH, BTN_BLUE, "visible");
      const qrContent = qrSvgRef.current
        ? '<div class="qr-wrap" style="width:120px;height:120px;display:flex;align-items:center;justify-content:center;overflow:hidden">' +
        qrSvgRef.current + '</div>'
        : '<div style="color:#fff;font-size:14px">Loading QR...</div>';

      box.innerHTML =
        '<div id="fill" style="position:absolute;top:0;left:0;right:0;bottom:0;background:' + BTN_BLUE + ';border-radius:inherit;z-index:1;"></div>' +
        '<div id="qrLayer" style="position:absolute;top:0;left:0;right:0;bottom:0;display:flex;align-items:center;justify-content:center;z-index:5;opacity:0;">' +
        qrContent +
        '</div>' +
        '<div id="sf" style="position:absolute;top:0;left:0;right:0;bottom:0;z-index:10;pointer-events:none;opacity:0;transform:scale(0.4);">' +
        makeCorner("tl") + makeCorner("tr") + makeCorner("bl") + makeCorner("br") +
        '</div>';

      // Force SVG to fit container
      requestAnimationFrame(() => {
        const svg = box.querySelector('.qr-wrap svg') as SVGElement | null;
        if (svg) {
          svg.setAttribute('width', '120');
          svg.setAttribute('height', '120');
          svg.style.width = '120px';
          svg.style.height = '120px';
          svg.style.display = 'block';
        }
      });
    }

    function renderPIN() {
      setBoxInstant(RW, RH, BTN_BLUE);
      const digits = currentPinRef.current.split("");
      let spans = "";
      for (let i = 0; i < 6; i++)
        spans += '<span class="pd" style="display:inline-block;width:28px;text-align:center;opacity:0;transform:translateY(4px);">' + (digits[i] || "-") + "</span>";
      box.innerHTML =
        '<div style="display:flex;align-items:center;font-size:28px;font-weight:700;color:#fff;letter-spacing:6px;font-variant-numeric:tabular-nums;position:relative;height:40px;">' +
        spans +
        '<div id="cur" style="position:absolute;width:2.5px;height:34px;background:#fff;border-radius:2px;left:-4px;top:50%;transform:translateY(-50%);opacity:0;box-shadow:0 0 6px rgba(255,255,255,.5);"></div>' +
        "</div>";
    }

    function renderStop() {
      setBoxInstant(RW, RH, BTN_RED);
      box.innerHTML =
        '<span id="label" style="color:#fff;font-size:22px;font-weight:600;letter-spacing:3px;text-transform:uppercase;opacity:0;">Stop</span>';
      gsap.to("#label", { opacity: 1, duration: 0.35 });
    }

    // 等待连接状态（USB / 蓝牙模式）— 蓝色按钮，文字呼吸闪烁
    function renderWaiting() {
      setBoxInstant(RW, RH, BTN_BLUE);
      box.innerHTML =
        '<span id="waitLabel" style="color:#fff;font-size:18px;font-weight:600;letter-spacing:2px;opacity:0;">等待设备连接</span>';
      gsap.to("#waitLabel", { opacity: 1, duration: 0.35 });
    }

    function startWaitPulse() {
      stopWaitPulse();
      waitPulseTween = gsap.to("#waitLabel", {
        opacity: 0.4,
        duration: 0.9,
        yoyo: true,
        repeat: -1,
        ease: "sine.inOut",
      });
    }

    function stopWaitPulse() {
      if (waitPulseTween) {
        waitPulseTween.kill();
        waitPulseTween = null;
      }
    }

    function startBreathing() {
      const maxInner = 12;
      breathTweensRef.current = [
        gsap.to("#fcTL", { x: maxInner, y: maxInner, duration: 1, yoyo: true, repeat: -1, ease: "sine.inOut" }),
        gsap.to("#fcTR", { x: -maxInner, y: maxInner, duration: 1, yoyo: true, repeat: -1, ease: "sine.inOut" }),
        gsap.to("#fcBL", { x: maxInner, y: -maxInner, duration: 1, yoyo: true, repeat: -1, ease: "sine.inOut" }),
        gsap.to("#fcBR", { x: -maxInner, y: -maxInner, duration: 1, yoyo: true, repeat: -1, ease: "sine.inOut" }),
      ];
    }

    function stopBreathing() {
      breathTweensRef.current.forEach((t) => t.kill());
      breathTweensRef.current = [];
    }

    function cursorReveal() {
      const cur = document.getElementById("cur")!;
      const pds = document.querySelectorAll<HTMLElement>(".pd");
      return new Promise<void>((resolve) => {
        cur.style.animation = "nexusCursorBlink 0.6s step-end infinite";
        const tw = 6 * 28, sx = -4, ex = tw + 4, dur = 900;
        let t0: number | null = null;
        (function tick(ts: number) {
          if (!t0) t0 = ts;
          const t = Math.min((ts - t0) / dur, 1);
          const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          const x = sx + (ex - sx) * e;
          cur.style.left = x + "px";
          for (let i = 0; i < pds.length; i++) {
            if (x >= 14 + i * 28 - 8 && pds[i].style.opacity === "0") {
              pds[i].style.opacity = "1";
              pds[i].style.transform = "translateY(0)";
            }
          }
          if (t < 1) requestAnimationFrame(tick);
          else { cur.style.animation = "none"; cur.style.opacity = "0"; resolve(); }
        })(0);
      });
    }

    function cursorErase() {
      const cur = document.getElementById("cur")!;
      const pds = document.querySelectorAll<HTMLElement>(".pd");
      return new Promise<void>((resolve) => {
        cur.style.animation = "nexusCursorBlink 0.6s step-end infinite";
        const tw = 6 * 28, sx = tw + 4, ex = -4, dur = 800;
        let t0: number | null = null;
        (function tick(ts: number) {
          if (!t0) t0 = ts;
          const t = Math.min((ts - t0) / dur, 1);
          const e = t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2;
          const x = sx + (ex - sx) * e;
          cur.style.left = x + "px";
          for (let i = 0; i < pds.length; i++) {
            if (x <= 14 + (i + 1) * 28 + 4 && pds[i].style.opacity === "1") {
              pds[i].style.opacity = "0";
              pds[i].style.transform = "translateY(4px)";
            }
          }
          if (t < 1) requestAnimationFrame(tick);
          else { cur.style.animation = "none"; cur.style.opacity = "0"; resolve(); }
        })(0);
      });
    }

    // ── Transition functions ──

    function startToQR() {
      if (busyRef.current) return;
      busyRef.current = true;
      stateRef.current = "toQR";
      hint.style.opacity = "0";
      gsap.to("#label", { opacity: 0, duration: 0.25 });
      setTimeout(() => {
        renderQR();
        requestAnimationFrame(() => {
          requestAnimationFrame(() => {
            const fillEl = document.getElementById("fill")!;
            const sfEl = document.getElementById("sf")!;
            gsap.timeline({
              onComplete: () => {
                const qrl = document.getElementById("qrLayer");
                if (qrl) gsap.to(qrl, { opacity: 1, duration: 0.4 });
                startBreathing();
                stateRef.current = "qr";
                hint.textContent = "扫描二维码继续";
                hint.style.opacity = "1";
                busyRef.current = false;
                notifyState("qr");
              },
            })
              .to(box, { width: SQ, height: SQ, borderRadius: BR, backgroundColor: "rgba(50,131,255,0)", duration: 0.6, ease: "power2.inOut" }, 0)
              .to(fillEl, { opacity: 0, scale: 0.08, duration: 0.65, ease: "power2.inOut" }, 0)
              .to(sfEl, { opacity: 1, scale: 1, duration: 0.65, ease: "power2.inOut" }, 0);
          });
        });
      }, 280);
    }

    function startToPIN() {
      if (busyRef.current) return;
      busyRef.current = true;
      stateRef.current = "toPIN";
      hint.style.opacity = "0";
      stopBreathing();
      const qrl = document.getElementById("qrLayer");
      if (qrl) gsap.to(qrl, { opacity: 0, duration: 0.35 });
      setTimeout(() => {
        const fillEl = document.getElementById("fill")!;
        const sfEl = document.getElementById("sf")!;
        gsap.timeline({
          onComplete: () => {
            renderPIN();
            setTimeout(() => {
              stateRef.current = "pin";
              hint.textContent = "输入上方配对码";
              hint.style.opacity = "1";
              busyRef.current = false;
              notifyState("pin");
              requestAnimationFrame(() => cursorReveal());
            }, 80);
          },
        })
          .to(box, { width: RW, height: RH, borderRadius: BR, backgroundColor: BTN_BLUE, duration: 0.6, ease: "power2.inOut" }, 0)
          .set(box, { overflow: "hidden" }, 0)
          .to(fillEl, { opacity: 1, scale: 1, duration: 0.6, ease: "power2.inOut" }, 0)
          .to(sfEl, { opacity: 0, duration: 0.6, ease: "power2.inOut" }, 0)
          .to(document.getElementById("fcTL")!, { x: 0, y: 0, duration: 0.6, ease: "power2.inOut" }, 0)
          .to(document.getElementById("fcTR")!, { x: 0, y: 0, duration: 0.6, ease: "power2.inOut" }, 0)
          .to(document.getElementById("fcBL")!, { x: 0, y: 0, duration: 0.6, ease: "power2.inOut" }, 0)
          .to(document.getElementById("fcBR")!, { x: 0, y: 0, duration: 0.6, ease: "power2.inOut" }, 0);
      }, 380);
    }

    function startToStop() {
      if (busyRef.current) return;
      const fromWait = stateRef.current === "wait" || stateRef.current === "toWait";
      busyRef.current = true;
      stateRef.current = "toDone";
      hint.style.opacity = "0";

      const finish = () => {
        renderStop();
        gsap.from(box, { backgroundColor: BTN_BLUE, duration: 0.45, ease: "power2.out" });
        setTimeout(() => {
          stateRef.current = "done";
          hint.textContent = "点击停止服务";
          hint.style.opacity = "1";
          busyRef.current = false;
          notifyState("done");
        }, 350);
      };

      if (fromWait) {
        // USB / 蓝牙：从等待状态直接淡入 STOP（无 PIN 光标动画）
        stopWaitPulse();
        gsap.to("#waitLabel", { opacity: 0, duration: 0.25, onComplete: finish });
      } else {
        // 局域网：先擦除 PIN 光标，再切到 STOP
        cursorErase().then(finish);
      }
    }

    // USB / 蓝牙：START → 等待连接状态
    function startToWaiting() {
      if (busyRef.current) return;
      busyRef.current = true;
      stateRef.current = "toWait";
      hint.style.opacity = "0";
      gsap.to("#label", { opacity: 0, duration: 0.25 });
      setTimeout(() => {
        renderWaiting();
        setTimeout(() => {
          stateRef.current = "wait";
          hint.textContent = "在手机端发起连接";
          hint.style.opacity = "1";
          busyRef.current = false;
          startWaitPulse();
          notifyState("wait");
        }, 360);
      }, 280);
    }

    function startReset() {
      if (busyRef.current) return;
      busyRef.current = true;
      stopWaitPulse();
      gsap.to("#label", { opacity: 0, duration: 0.25 });
      setTimeout(() => {
        renderIdle();
        gsap.from(box, { backgroundColor: BTN_RED, duration: 0.45, ease: "power2.out" });
        setTimeout(() => {
          stateRef.current = "idle";
          hint.textContent = "点击开启服务";
          hint.style.opacity = "1";
          busyRef.current = false;
          notifyState("idle");
        }, 400);
      }, 280);
    }

    // Reset from any state (QR, PIN, or STOP) back to START
    function resetFromAny() {
      if (busyRef.current) return;
      const s = stateRef.current;
      if (s === "idle") return;
      busyRef.current = true;
      hint.style.opacity = "0";

      // Stop any active animations
      stopBreathing();
      stopWaitPulse();

      function onResetComplete() {
        stateRef.current = "idle";
        hint.textContent = "点击开启服务";
        hint.style.opacity = "1";
        busyRef.current = false;
        notifyState("idle");
      }

      if (s === "qr" || s === "toQR") {
        const qrl = document.getElementById("qrLayer");
        const sfEl = document.getElementById("sf");
        const fillEl = document.getElementById("fill");
        if (qrl) gsap.to(qrl, { opacity: 0, duration: 0.3 });
        if (sfEl) gsap.to(sfEl, { opacity: 0, duration: 0.3 });
        gsap.timeline({
          onComplete: () => {
            renderIdle();
            setTimeout(onResetComplete, 300);
          }
        })
          .to(box, { width: RW, height: RH, borderRadius: BR, backgroundColor: BTN_BLUE, duration: 0.5, ease: "power2.inOut" }, 0)
          .set(box, { overflow: "hidden" }, 0)
          .to(fillEl, { opacity: 1, scale: 1, duration: 0.5, ease: "power2.inOut" }, 0);
      } else if (s === "pin" || s === "toPIN") {
        cursorErase().then(() => {
          renderIdle();
          gsap.from(box, { backgroundColor: BTN_BLUE, duration: 0.35, ease: "power2.out" });
          setTimeout(onResetComplete, 300);
        });
      } else if (s === "wait" || s === "toWait") {
        // USB / 蓝牙等待状态 → START（蓝→蓝，仅淡出文字）
        const wl = document.getElementById("waitLabel");
        if (wl) {
          gsap.to(wl, {
            opacity: 0, duration: 0.25, onComplete: () => {
              renderIdle();
              setTimeout(onResetComplete, 300);
            }
          });
        } else {
          renderIdle();
          setTimeout(onResetComplete, 300);
        }
      } else {
        gsap.to("#label", { opacity: 0, duration: 0.2 });
        setTimeout(() => {
          renderIdle();
          gsap.from(box, { backgroundColor: BTN_RED, duration: 0.35, ease: "power2.out" });
          setTimeout(onResetComplete, 300);
        }, 220);
      }
    }

    // Store transitions for useImperativeHandle
    (box as any).__transitions = { startToQR, startToPIN, startToStop, startToWaiting, startReset, resetFromAny };

    // ── Click handler ──
    async function handleClick() {
      const s = stateRef.current;
      if (s === "idle") {
        // Get port from SettingsPanel input
        const portInput = document.querySelector('[data-port-input]') as HTMLInputElement;
        const port = portInput ? parseInt(portInput.value) : 8765;
        if (port < 1 || port > 65535) return;

        try {
          const available: boolean = await invoke("check_port", { port });
          if (!available) {
            hint.textContent = "端口 " + port + " 已被占用";
            hint.style.color = "#e53e3e";
            setTimeout(() => { hint.style.color = "#5a8fb5"; hint.textContent = "点击开启服务"; }, 3000);
            return;
          }
        } catch { }

        hint.textContent = "启动中...";
        hint.style.opacity = "1";
        try {
          const status: any = await invoke("start_server_cmd", { port });
          qrSvgRef.current = status.qr_svg || "";
          if (status.pin) currentPinRef.current = status.pin;
          // 按连接模式分流：局域网走二维码/PIN，USB/蓝牙走等待连接
          if (modeRef.current === "wifi") {
            startToQR();
          } else {
            startToWaiting();
          }
        } catch (e: any) {
          hint.textContent = typeof e === "string" ? e : "启动失败";
          hint.style.color = "#e53e3e";
          setTimeout(() => { hint.textContent = "点击开启服务"; hint.style.color = "#5a8fb5"; }, 3000);
        }
      } else if (s === "wait") {
        // USB / 蓝牙等待连接时再次点击 = 取消并停止服务
        try { await invoke("stop_server_cmd"); } catch { }
        onStopped?.();
        resetFromAny();
      } else if (s === "done") {
        try { await invoke("stop_server_cmd"); } catch { }
        onStopped?.();
        startReset();
      }
    }

    renderIdle();
    hint.textContent = "点击开启服务";
    box.addEventListener("click", handleClick);

    return () => {
      box.removeEventListener("click", handleClick);
      stopBreathing();
    };
  }, []);

  // Expose transition methods to parent
  useImperativeHandle(ref, () => ({
    showPIN: () => {
      const box = boxRef.current;
      if (box) { const t = (box as any).__transitions; if (t) t.startToPIN(); }
    },
    showStop: () => {
      const box = boxRef.current;
      if (box) { const t = (box as any).__transitions; if (t) t.startToStop(); }
    },
    showIdle: () => {
      const box = boxRef.current;
      if (box) { const t = (box as any).__transitions; if (t) t.startReset(); }
    },
    resetToIdle: () => {
      const box = boxRef.current;
      if (box) { const t = (box as any).__transitions; if (t) t.resetFromAny(); }
    },
    updatePin: (pin: string) => {
      currentPinRef.current = pin;
    },
  }), []);

  return (
    <div
      style={{
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        gap: "18px",
        padding: "28px 36px",
        background: "#EBF6FF",
        borderRadius: "14px",
        border: "1px solid rgba(0,98,171,0.12)",
      }}
    >
      <style>{`
        @keyframes nexusCursorBlink {
          0%, 100% { opacity: 1; }
          50% { opacity: 0; }
        }
      `}</style>
      <div
        ref={boxRef}
        style={{
          position: "relative",
          cursor: "pointer",
          userSelect: "none",
          WebkitUserSelect: "none",
        }}
      />
      <div
        ref={hintRef}
        style={{
          color: "#5a8fb5",
          fontSize: "13px",
          letterSpacing: "0.04em",
          transition: "opacity 0.4s",
          fontFamily: "system-ui, sans-serif",
        }}
      >
        点击开启服务
      </div>
    </div>
  );
});
