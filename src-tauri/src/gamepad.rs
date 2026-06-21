use anyhow::Result;
use tracing::{info, warn};

#[cfg(target_os = "windows")]
use vigem_client::{Client, Xbox360Wired, XGamepad, XButtons, TargetId};

/// Gamepad manager — creates and manages a virtual gamepad via ViGEmBus.
pub struct GamepadManager {
    #[cfg(target_os = "windows")]
    client: Option<Client>,
    #[cfg(target_os = "windows")]
    target_xbox: Option<Xbox360Wired<Client>>,
    pad_type: Option<String>,
}

impl GamepadManager {
    pub fn new() -> Self {
        Self {
            #[cfg(target_os = "windows")]
            client: None,
            #[cfg(target_os = "windows")]
            target_xbox: None,
            pad_type: None,
        }
    }

    /// Check if the ViGEmBus driver is installed (Windows only).
    #[cfg(target_os = "windows")]
    pub fn is_installed() -> bool {
        Client::connect().is_ok()
    }

    #[cfg(not(target_os = "windows"))]
    pub fn is_installed() -> bool {
        false
    }

    /// Create an Xbox 360 virtual gamepad.
    #[cfg(target_os = "windows")]
    pub fn create_xbox(&mut self) -> Result<()> {
        // Clean up any existing target
        self.destroy();

        let client = Client::connect()
            .map_err(|e| anyhow::anyhow!("ViGEm connect failed: {:?}. Is ViGEmBus installed?", e))?;

        let id = TargetId::default(); // Default Xbox 360 VID/PID
        let mut target = Xbox360Wired::new(client, id);
        target.plugin()
            .map_err(|e| anyhow::anyhow!("ViGEm plugin failed: {:?}", e))?;
        target.wait_ready()
            .map_err(|e| anyhow::anyhow!("ViGEm wait_ready failed: {:?}", e))?;

        info!("Xbox 360 virtual gamepad created");
        self.target_xbox = Some(target);
        self.pad_type = Some("xbox".into());
        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    pub fn create_xbox(&mut self) -> Result<()> {
        Err(anyhow::anyhow!("Virtual gamepad only supported on Windows"))
    }

    /// Create a DualShock 4 virtual gamepad.
    #[cfg(target_os = "windows")]
    pub fn create_ds4(&mut self) -> Result<()> {
        self.destroy();

        let client = Client::connect()
            .map_err(|e| anyhow::anyhow!("ViGEm connect failed: {:?}", e))?;

        // DS4 support in vigem-client 0.1 is experimental;
        // use Xbox360Wired with DS4-style PID as fallback
        let id = TargetId::default();
        let mut target = Xbox360Wired::new(client, id);
        target.plugin()
            .map_err(|e| anyhow::anyhow!("ViGEm plugin failed: {:?}", e))?;
        target.wait_ready()
            .map_err(|e| anyhow::anyhow!("ViGEm wait_ready failed: {:?}", e))?;

        info!("DualShock 4 virtual gamepad created (via Xbox360 driver)");
        self.target_xbox = Some(target);
        self.pad_type = Some("ps".into());
        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    pub fn create_ds4(&mut self) -> Result<()> {
        Err(anyhow::anyhow!("Virtual gamepad only supported on Windows"))
    }

    /// Update the virtual gamepad state.
    #[cfg(target_os = "windows")]
    pub fn update(&mut self, lx: f64, ly: f64, rx: f64, ry: f64,
                  lt: f64, rt: f64, buttons: u32) -> Result<()> {
        let target = self.target_xbox.as_mut()
            .ok_or_else(|| anyhow::anyhow!("No gamepad created"))?;

        // Build XGamepad report
        let mut gamepad = XGamepad::default();

        // Axes: f64 (-1~1) → i16 (-32768~32767)
        gamepad.thumb_lx = (lx.clamp(-1.0, 1.0) * 32767.0) as i16;
        gamepad.thumb_ly = -(ly.clamp(-1.0, 1.0) * 32767.0) as i16; // Y axis inverted
        gamepad.thumb_rx = (rx.clamp(-1.0, 1.0) * 32767.0) as i16;
        gamepad.thumb_ry = -(ry.clamp(-1.0, 1.0) * 32767.0) as i16;

        // Triggers: f64 (0~1) → u8 (0~255)
        gamepad.left_trigger = (lt.clamp(0.0, 1.0) * 255.0) as u8;
        gamepad.right_trigger = (rt.clamp(0.0, 1.0) * 255.0) as u8;

        // Buttons: bitmask → XButtons
        gamepad.buttons = map_buttons(buttons);

        target.update(&gamepad)
            .map_err(|e| anyhow::anyhow!("ViGEm update failed: {:?}", e))?;
        Ok(())
    }

    #[cfg(not(target_os = "windows"))]
    pub fn update(&mut self, _lx: f64, _ly: f64, _rx: f64, _ry: f64,
                  _lt: f64, _rt: f64, _buttons: u32) -> Result<()> {
        Ok(()) // no-op on non-Windows
    }

    /// Destroy the virtual gamepad.
    pub fn destroy(&mut self) {
        #[cfg(target_os = "windows")]
        {
            if let Some(target) = self.target_xbox.take() {
                drop(target); // Drop calls unplug automatically
                info!("Virtual gamepad destroyed");
            }
            self.client = None;
        }
        self.pad_type = None;
    }
}

impl Drop for GamepadManager {
    fn drop(&mut self) {
        self.destroy();
    }
}

/// Map our protocol bitmask to XButtons.
///
/// Protocol bit layout:
///   0=A, 1=B, 2=X, 3=Y, 4=Up, 5=Down, 6=Left, 7=Right,
///   8=LB, 9=RB, 10=LS, 11=RS, 12=Back, 13=Menu, 14=Guide
#[cfg(target_os = "windows")]
fn map_buttons(b: u32) -> XButtons {
    let mut xb = XButtons::default();
    if b & (1 << 0) != 0 { xb.raw |= XButtons::A; }
    if b & (1 << 1) != 0 { xb.raw |= XButtons::B; }
    if b & (1 << 2) != 0 { xb.raw |= XButtons::X; }
    if b & (1 << 3) != 0 { xb.raw |= XButtons::Y; }
    if b & (1 << 4) != 0 { xb.raw |= XButtons::UP; }
    if b & (1 << 5) != 0 { xb.raw |= XButtons::DOWN; }
    if b & (1 << 6) != 0 { xb.raw |= XButtons::LEFT; }
    if b & (1 << 7) != 0 { xb.raw |= XButtons::RIGHT; }
    if b & (1 << 8) != 0 { xb.raw |= XButtons::LB; }
    if b & (1 << 9) != 0 { xb.raw |= XButtons::RB; }
    if b & (1 << 10) != 0 { xb.raw |= XButtons::LTHUMB; }
    if b & (1 << 11) != 0 { xb.raw |= XButtons::RTHUMB; }
    if b & (1 << 12) != 0 { xb.raw |= XButtons::BACK; }
    if b & (1 << 13) != 0 { xb.raw |= XButtons::START; }
    if b & (1 << 14) != 0 { xb.raw |= XButtons::GUIDE; }
    xb
}
