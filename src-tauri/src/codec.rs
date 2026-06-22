/// TLV (Type-Length-Value) 二进制帧编解码 + 高频消息二进制结构
///
/// 帧格式: [1B type][2B length (big-endian)][NB payload]

// ─── 帧类型常量 ──────────────────────────────────────────

pub const FRAME_CONTROL: u8 = 0x01;
pub const FRAME_INPUT: u8 = 0x02;
pub const FRAME_GAMEPAD: u8 = 0x03;
pub const FRAME_SYSTEM: u8 = 0x04;
pub const FRAME_HEARTBEAT: u8 = 0xFF;

// ─── 输入帧子类型 ────────────────────────────────────────

pub const INPUT_SUB_MOVE: u8 = 0x01;
pub const INPUT_SUB_SCROLL: u8 = 0x02;

// ─── TLV 帧编解码 ───────────────────────────────────────

pub struct TlvFrame {
    pub frame_type: u8,
    pub payload: Vec<u8>,
}

impl TlvFrame {
    /// 编码为字节
    pub fn encode(&self) -> Vec<u8> {
        let len = self.payload.len();
        let mut buf = Vec::with_capacity(3 + len);
        buf.push(self.frame_type);
        buf.extend_from_slice(&(len as u16).to_be_bytes());
        buf.extend_from_slice(&self.payload);
        buf
    }

    /// 从字节解码，返回 (帧, 消耗字节数) 或 None
    pub fn decode(data: &[u8]) -> Option<(Self, usize)> {
        if data.len() < 3 {
            return None;
        }
        let frame_type = data[0];
        let len = u16::from_be_bytes([data[1], data[2]]) as usize;
        if data.len() < 3 + len {
            return None;
        }
        Some((
            Self {
                frame_type,
                payload: data[3..3 + len].to_vec(),
            },
            3 + len,
        ))
    }
}

// ─── 手柄帧二进制解码 ────────────────────────────────────

/// 手柄状态二进制结构 (type=0x03 payload)
///
/// 布局: [2B lx][2B ly][2B rx][2B ry][1B lt][1B rt][2B buttons][1B gyro_flag]
pub struct GamepadStateBinary {
    pub lx: i16,
    pub ly: i16,
    pub rx: i16,
    pub ry: i16,
    pub lt: u8,
    pub rt: u8,
    pub buttons: u16,
    pub gyro_flag: u8,
}

impl GamepadStateBinary {
    /// 最小 payload 长度 (无陀螺仪)
    pub const MIN_LEN: usize = 13;

    /// 从 payload 字节解码
    pub fn decode(payload: &[u8]) -> Option<Self> {
        if payload.len() < Self::MIN_LEN {
            return None;
        }
        Some(Self {
            lx: i16::from_be_bytes([payload[0], payload[1]]),
            ly: i16::from_be_bytes([payload[2], payload[3]]),
            rx: i16::from_be_bytes([payload[4], payload[5]]),
            ry: i16::from_be_bytes([payload[6], payload[7]]),
            lt: payload[8],
            rt: payload[9],
            buttons: u16::from_be_bytes([payload[10], payload[11]]),
            gyro_flag: payload[12],
        })
    }

    /// 转换为 f64 值，匹配现有 GamepadManager::update 签名
    pub fn to_f64(&self) -> (f64, f64, f64, f64, f64, f64, u32) {
        (
            self.lx as f64 / 32767.0,
            self.ly as f64 / 32767.0,
            self.rx as f64 / 32767.0,
            self.ry as f64 / 32767.0,
            self.lt as f64 / 255.0,
            self.rt as f64 / 255.0,
            self.buttons as u32,
        )
    }
}

// ─── 输入帧二进制解码 ────────────────────────────────────

/// 从输入帧 payload 解码 move 事件
pub fn decode_input_move(payload: &[u8]) -> Option<(i16, i16)> {
    if payload.len() < 5 || payload[0] != INPUT_SUB_MOVE {
        return None;
    }
    Some((
        i16::from_be_bytes([payload[1], payload[2]]),
        i16::from_be_bytes([payload[3], payload[4]]),
    ))
}

/// 从输入帧 payload 解码 scroll 事件
pub fn decode_input_scroll(payload: &[u8]) -> Option<(i16, i16)> {
    if payload.len() < 5 || payload[0] != INPUT_SUB_SCROLL {
        return None;
    }
    Some((
        i16::from_be_bytes([payload[1], payload[2]]),
        i16::from_be_bytes([payload[3], payload[4]]),
    ))
}
