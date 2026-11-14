//! Focus — the drawing. The menu, the tray icon and the session animation are drawn here in plain Rust, pixel by
//! pixel, with no system calls: the same picture on Windows and Linux, and checkable as images on any machine.
//! Sizes are in points as in the Mac app (menu 320 wide, rows 26 high…); `scale` turns points into pixels.
pub mod draw;
pub mod glyph;
pub mod menu;
pub mod pill;
pub mod text;

pub use draw::{Canvas, Rgba};
pub use text::Fonts;

/// The look: dark (the standard) or light. One token set, as in the Mac app's Theme.
#[derive(Clone, Copy, Debug)]
pub struct Theme {
    pub background: Rgba,
    pub edge: Rgba,
    pub text: Rgba,
    pub faint: Rgba,
    pub heading: Rgba,
    pub dropped: Rgba,
    pub hover: Rgba,
    pub accent: Rgba,
    pub on_accent: Rgba,
    pub hazard: Rgba,
    pub hud_bg: Rgba,
    pub hud_ink: Rgba,
    pub hud_edge: Rgba,
}
impl Theme {
    pub fn dark() -> Theme {
        Theme {
            background: Rgba::hex(0x1F1F21, 1.0), edge: Rgba::new(255, 255, 255, 0.12),
            text: Rgba::new(255, 255, 255, 0.85), faint: Rgba::new(235, 235, 245, 0.55),
            heading: Rgba::new(235, 235, 245, 0.25), dropped: Rgba::new(235, 235, 245, 0.25),
            hover: Rgba::new(255, 255, 255, 0.08), accent: Rgba::new(255, 255, 255, 1.0),
            on_accent: Rgba::new(0, 0, 0, 1.0), hazard: Rgba::hex(0xFF453A, 1.0),
            hud_bg: Rgba::new(18, 18, 18, 0.88), hud_ink: Rgba::new(255, 255, 255, 1.0), hud_edge: Rgba::new(255, 255, 255, 0.14),
        }
    }
    pub fn light() -> Theme {
        Theme {
            background: Rgba::hex(0xF5F5F7, 1.0), edge: Rgba::new(0, 0, 0, 0.12),
            text: Rgba::new(0, 0, 0, 0.85), faint: Rgba::new(60, 60, 67, 0.6),
            heading: Rgba::new(60, 60, 67, 0.3), dropped: Rgba::new(60, 60, 67, 0.3),
            hover: Rgba::new(0, 0, 0, 0.08), accent: Rgba::hex(0x171A20, 1.0),
            on_accent: Rgba::new(255, 255, 255, 1.0), hazard: Rgba::hex(0xFF3B30, 1.0),
            ..Theme::dark()
        }
    }
}

/// A picture supplied by the platform (an app's icon): straight RGBA, row by row.
#[derive(Clone, Debug)]
pub struct Image {
    pub width: u32,
    pub height: u32,
    pub rgba: Vec<u8>,
}
