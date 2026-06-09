use serde::{Deserialize, Serialize};

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
    #[serde(rename = "approval_resp")]
    ApprovalResp { r: String },
    #[serde(rename = "auth")]
    Auth { pin: String },
}

fn default_button() -> u8 { 1 }
fn default_one() -> u32 { 1 }

/// Server → Client messages
#[derive(Debug, Clone, Serialize)]
#[serde(tag = "a")]
pub enum ServerMsg {
    #[serde(rename = "ctrl_ok")]
    CtrlOk,
    #[serde(rename = "wait")]
    Wait { #[serde(skip_serializing_if = "Option::is_none")] reason: Option<String> },
    #[serde(rename = "approval_req")]
    ApprovalReq { ip: String },
    #[serde(rename = "auth_required")]
    AuthRequired,
    #[serde(rename = "auth_fail")]
    AuthFail,
}
