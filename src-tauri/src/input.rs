use enigo::{
    Button,
    Coordinate::Rel,
    Direction::{Click, Press, Release},
    Enigo, Keyboard, Mouse, Settings,
};
use std::sync::Mutex;
use anyhow::Result;
use tracing::info;

/// Cross-platform input simulator using enigo (works on Windows, macOS, Linux).
pub struct InputSimulator {
    enigo: Mutex<Enigo>,
}

impl InputSimulator {
    pub async fn new() -> Result<Self> {
        let enigo = tokio::task::spawn_blocking(|| {
            Enigo::new(&Settings::default())
        }).await
            .map_err(|e| anyhow::anyhow!("spawn_blocking failed: {}", e))?
            .map_err(|e| anyhow::anyhow!("Failed to init enigo: {}", e))?;
        info!("Enigo input simulator initialized");
        Ok(Self {
            enigo: Mutex::new(enigo),
        })
    }

    pub async fn mouse_move(&self, dx: f64, dy: f64) -> Result<()> {
        let mut e = self.enigo.lock().unwrap();
        e.move_mouse(dx as i32, dy as i32, Rel)
            .map_err(|e| anyhow::anyhow!("mouse_move: {}", e))
    }

    pub async fn mouse_click(&self, button: u8) -> Result<()> {
        let btn = map_button(button);
        let mut e = self.enigo.lock().unwrap();
        e.button(btn, Click)
            .map_err(|e| anyhow::anyhow!("mouse_click: {}", e))
    }

    pub async fn mouse_double_click(&self) -> Result<()> {
        let mut e = self.enigo.lock().unwrap();
        e.button(Button::Left, Click)
            .map_err(|e| anyhow::anyhow!("dbl_click 1: {}", e))?;
        e.button(Button::Left, Click)
            .map_err(|e| anyhow::anyhow!("dbl_click 2: {}", e))
    }

    pub async fn mouse_down(&self, button: u8) -> Result<()> {
        let btn = map_button(button);
        let mut e = self.enigo.lock().unwrap();
        e.button(btn, Press)
            .map_err(|e| anyhow::anyhow!("mouse_down: {}", e))
    }

    pub async fn mouse_up(&self, button: u8) -> Result<()> {
        let btn = map_button(button);
        let mut e = self.enigo.lock().unwrap();
        e.button(btn, Release)
            .map_err(|e| anyhow::anyhow!("mouse_up: {}", e))
    }

    pub async fn mouse_scroll(&self, dy: f64) -> Result<()> {
        let amount = dy.round() as i32;
        if amount == 0 { return Ok(()); }
        let mut e = self.enigo.lock().unwrap();
        e.scroll(amount, enigo::Axis::Vertical)
            .map_err(|e| anyhow::anyhow!("scroll: {}", e))
    }

    /// Send a key combo like "ctrl+c", "Escape", "shift+Tab".
    pub async fn send_key(&self, key: &str) -> Result<()> {
        let (modifiers, main_key) = parse_key_string(key);
        let mut e = self.enigo.lock().unwrap();

        // Press modifiers
        for m in &modifiers {
            e.key(*m, Press)
                .map_err(|e| anyhow::anyhow!("mod press: {}", e))?;
        }

        // Press+release main key
        e.key(main_key, Click)
            .map_err(|e| anyhow::anyhow!("key click: {}", e))?;

        // Release modifiers in reverse order
        for m in modifiers.iter().rev() {
            e.key(*m, Release)
                .map_err(|e| anyhow::anyhow!("mod release: {}", e))?;
        }

        Ok(())
    }

    /// Type text using clipboard paste (works for CJK and all Unicode).
    pub async fn type_text(&self, text: &str) -> Result<()> {
        if text.is_empty() {
            return Ok(());
        }

        for (i, line) in text.split('\n').enumerate() {
            if !line.is_empty() {
                // Try clipboard paste first (reliable for CJK)
                if self.clipboard_paste(line).await.is_err() {
                    // Fallback: enigo text input
                    let mut e = self.enigo.lock().unwrap();
                    e.text(line)
                        .map_err(|e| anyhow::anyhow!("text: {}", e))?;
                }
            }
            if i < text.split('\n').count() - 1 {
                self.send_key("Return").await?;
            }
        }
        Ok(())
    }

    /// Copy text to clipboard then Ctrl+V paste.
    async fn clipboard_paste(&self, text: &str) -> Result<()> {
        {
            let mut ctx = arboard::Clipboard::new()
                .map_err(|e| anyhow::anyhow!("clipboard: {}", e))?;
            ctx.set_text(text.to_string())
                .map_err(|e| anyhow::anyhow!("clipboard set: {}", e))?;
        }

        // Small delay to ensure clipboard is populated
        tokio::time::sleep(tokio::time::Duration::from_millis(20)).await;

        // Ctrl+V
        let mut e = self.enigo.lock().unwrap();
        e.key(enigo::Key::Control, Press).map_err(|e| anyhow::anyhow!("ctrl press: {}", e))?;
        e.key(enigo::Key::Unicode('v'), Click).map_err(|e| anyhow::anyhow!("v click: {}", e))?;
        e.key(enigo::Key::Control, Release).map_err(|e| anyhow::anyhow!("ctrl release: {}", e))?;
        Ok(())
    }

    pub async fn close(&mut self) {
        // enigo doesn't need explicit cleanup
    }
}

/// Map button number (1=left, 2=middle, 3=right) to enigo Button.
fn map_button(b: u8) -> Button {
    match b {
        1 => Button::Left,
        2 => Button::Middle,
        3 => Button::Right,
        _ => Button::Left,
    }
}

/// Parse a key string like "ctrl+shift+Tab" into (modifier_keys, main_key).
fn parse_key_string(key: &str) -> (Vec<enigo::Key>, enigo::Key) {
    let parts: Vec<&str> = key.split('+').map(|s| s.trim()).collect();
    let mut modifiers = Vec::new();
    let mut main_key_str = "";

    for (i, part) in parts.iter().enumerate() {
        if i == parts.len() - 1 {
            // Last part is the main key
            main_key_str = part;
        } else {
            // Modifier
            if let Some(m) = map_modifier(part) {
                modifiers.push(m);
            }
        }
    }

    let main_key = map_key_name(main_key_str);
    (modifiers, main_key)
}

/// Map modifier name to enigo Key.
fn map_modifier(name: &str) -> Option<enigo::Key> {
    match name.to_lowercase().as_str() {
        "ctrl" | "control" => Some(enigo::Key::Control),
        "shift" => Some(enigo::Key::Shift),
        "alt" | "option" => Some(enigo::Key::Alt),
        "meta" | "super" | "win" | "cmd" | "command" => Some(enigo::Key::Meta),
        _ => None,
    }
}

/// Map key name to enigo Key.
fn map_key_name(name: &str) -> enigo::Key {
    match name {
        // Special keys
        "Escape" | "Esc" => enigo::Key::Escape,
        "Tab" => enigo::Key::Tab,
        "Return" | "Enter" => enigo::Key::Return,
        "BackSpace" | "Backspace" => enigo::Key::Backspace,
        "Delete" | "Del" => enigo::Key::Delete,
        "Space" => enigo::Key::Unicode(' '),
        "Up" => enigo::Key::UpArrow,
        "Down" => enigo::Key::DownArrow,
        "Left" => enigo::Key::LeftArrow,
        "Right" => enigo::Key::RightArrow,
        "Home" => enigo::Key::Home,
        "End" => enigo::Key::End,
        "Page_Up" | "PageUp" => enigo::Key::PageUp,
        "Page_Down" | "PageDown" => enigo::Key::PageDown,
        "Insert" | "Ins" => enigo::Key::Insert,
        // Function keys
        "F1" => enigo::Key::F1,
        "F2" => enigo::Key::F2,
        "F3" => enigo::Key::F3,
        "F4" => enigo::Key::F4,
        "F5" => enigo::Key::F5,
        "F6" => enigo::Key::F6,
        "F7" => enigo::Key::F7,
        "F8" => enigo::Key::F8,
        "F9" => enigo::Key::F9,
        "F10" => enigo::Key::F10,
        "F11" => enigo::Key::F11,
        "F12" => enigo::Key::F12,
        // Modifiers as standalone keys
        "ctrl" | "control" => enigo::Key::Control,
        "shift" => enigo::Key::Shift,
        "alt" | "option" => enigo::Key::Alt,
        "meta" | "super" | "win" | "cmd" => enigo::Key::Meta,
        // Punctuation / symbols commonly sent
        "slash" | "/" => enigo::Key::Unicode('/'),
        "backslash" | "\\" => enigo::Key::Unicode('\\'),
        "period" | "." => enigo::Key::Unicode('.'),
        "comma" | "," => enigo::Key::Unicode(','),
        "semicolon" | ";" => enigo::Key::Unicode(';'),
        "quote" | "'" => enigo::Key::Unicode('\''),
        "bracketleft" | "[" => enigo::Key::Unicode('['),
        "bracketright" | "]" => enigo::Key::Unicode(']'),
        "minus" | "-" => enigo::Key::Unicode('-'),
        "equal" | "=" => enigo::Key::Unicode('='),
        "grave" | "`" => enigo::Key::Unicode('`'),
        // Single character → Unicode
        _ if name.chars().count() == 1 => enigo::Key::Unicode(name.chars().next().unwrap()),
        // Unknown → try Unicode for the first char (fallback)
        _ => {
            tracing::warn!("Unknown key name: '{}', trying as Unicode", name);
            enigo::Key::Unicode(name.chars().next().unwrap_or(' '))
        }
    }
}
