use serde::{Deserialize, Serialize};

use crate::codec::{
    self, GamepadStateBinary, FRAME_GAMEPAD, FRAME_HEARTBEAT, FRAME_INPUT,
    INPUT_SUB_MOVE, INPUT_SUB_SCROLL, TlvFrame,
};

/// Client → Server messages
#[derive(Debug, Deserialize)]
#[serde(tag = "a")]
pub enum ClientMsg {
    #[serde(rename = "mv")]
    Move { x: f64, y: f64 },
    #[serde(rename = "clk")]
    Click { #[serde(default = "default_button")] b: u8 },
    #[serde(rename = "dbl")]
    DoubleClick,
    #[serde(rename = "md")]
    MouseDown { #[serde(default = "default_button")] b: u8 },
    #[serde(rename = "mu")]
    MouseUp { #[serde(default = "default_button")] b: u8 },
    #[serde(rename = "scr")]
    Scroll { #[serde(default)] y: f64, #[serde(default)] x: f64 },
    #[serde(rename = "pz")]
    PinchZoom { m: f64 },
    #[serde(rename = "type")]
    TypeText { t: String },
    #[serde(rename = "key")]
    Key { k: String },
    #[serde(rename = "kp")]
    KeyPress { k: String },
    #[serde(rename = "bs")]
    Backspace { #[serde(default = "default_one")] n: u32 },
    #[serde(rename = "ime")]
    ToggleIME { #[serde(default)] mode: String },
    /// Request physical IME toggle (simulates platform key, no mode needed)
    #[serde(rename = "ime_toggle")]
    PressImeToggle,
    /// Request server to re-read and push current IME state
    #[serde(rename = "ime_refresh")]
    RefreshIme,
    #[serde(rename = "approval_resp")]
    ApprovalResp { r: String },
    #[serde(rename = "auth")]
    Auth { pin: String },
    /// Check if ViGEmBus driver is installed
    #[serde(rename = "vigem")]
    VigemCheck,
    /// Request to create a virtual gamepad (t = "xbox" | "ps" | "custom")
    #[serde(rename = "gc")]
    GamepadConnect { t: String },
    /// Gamepad state snapshot (axes + triggers + button bitmask)
    #[serde(rename = "gp")]
    GamepadState {
        #[serde(default)] lx: f64,
        #[serde(default)] ly: f64,
        #[serde(default)] rx: f64,
        #[serde(default)] ry: f64,
        #[serde(default)] lt: f64,
        #[serde(default)] rt: f64,
        #[serde(default)] b: u32,
    },
    /// Request to destroy the virtual gamepad
    #[serde(rename = "gd")]
    GamepadDisconnect,
}

fn default_button() -> u8 { 1 }
fn default_one() -> u32 { 1 }

/// Server → Client messages
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "a")]
pub enum ServerMsg {
    #[serde(rename = "ctrl_ok")]
    CtrlOk { #[serde(skip_serializing_if = "Option::is_none")] proot: Option<bool> },
    #[serde(rename = "wait")]
    Wait { #[serde(skip_serializing_if = "Option::is_none")] reason: Option<String> },
    #[serde(rename = "approval_req")]
    ApprovalReq { ip: String },
    #[serde(rename = "auth_required")]
    AuthRequired,
    #[serde(rename = "auth_fail")]
    AuthFail,
    /// Push current IME status to client (sent on connect and after toggle)
    #[serde(rename = "ime_init")]
    ImeInit { status: String },
    /// ViGEmBus driver detection result
    #[serde(rename = "vigem")]
    VigemStatus { installed: bool },
}

// ─── 统一消息分发 ──────────────────────────────────────────

/// 解析后的客户端消息，可来自 JSON 文本帧或 TLV 二进制帧
pub enum ClientMessage {
    /// JSON 文本帧解析结果 (向后兼容)
    Json(ClientMsg),
    /// 二进制手柄帧 (type=0x03)
    BinaryGamepad(GamepadStateBinary),
    /// 二进制输入帧 — move (type=0x02, sub=0x01)
    BinaryMove { x: i16, y: i16 },
    /// 二进制输入帧 — scroll (type=0x02, sub=0x02)
    BinaryScroll { x: i16, y: i16 },
    /// 心跳帧 (type=0xFF)
    Heartbeat,
}

impl ClientMessage {
    /// 从 JSON 文本帧解析
    pub fn from_text(text: &str) -> Option<Self> {
        serde_json::from_str::<ClientMsg>(text)
            .ok()
            .map(ClientMessage::Json)
    }

    /// 从 TLV 二进制帧解析
    pub fn from_binary(data: &[u8]) -> Option<Self> {
        let (frame, _) = TlvFrame::decode(data)?;
        match frame.frame_type {
            FRAME_GAMEPAD => GamepadStateBinary::decode(&frame.payload)
                .map(ClientMessage::BinaryGamepad),
            FRAME_INPUT => {
                if frame.payload.is_empty() {
                    return None;
                }
                match frame.payload[0] {
                    INPUT_SUB_MOVE => codec::decode_input_move(&frame.payload)
                        .map(|(x, y)| ClientMessage::BinaryMove { x, y }),
                    INPUT_SUB_SCROLL => codec::decode_input_scroll(&frame.payload)
                        .map(|(x, y)| ClientMessage::BinaryScroll { x, y }),
                    _ => None,
                }
            }
            FRAME_HEARTBEAT => Some(ClientMessage::Heartbeat),
            _ => None,
        }
    }
}
