//! Text: the system's own interface font, rasterised here so it looks the same wherever it is drawn.
use crate::draw::{Canvas, Rgba};
use fontdue::{Font, FontSettings};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Weight { Regular, Semibold, Bold }

pub struct Fonts { regular: Font, semibold: Font, bold: Font }

fn load(paths: &[String]) -> Option<Font> {
    for p in paths {
        if let Ok(bytes) = std::fs::read(p) {
            if let Ok(f) = Font::from_bytes(bytes, FontSettings::default()) { return Some(f); }
        }
    }
    None
}

impl Fonts {
    /// The interface font of whatever system this runs on: Segoe UI on Windows; a common sans on Linux; Arial on
    /// a Mac (used only for checking pictures while developing).
    pub fn system() -> Result<Fonts, String> {
        let win = std::env::var("WINDIR").unwrap_or_else(|_| "C:\\Windows".into());
        let w = |f: &str| format!("{win}\\Fonts\\{f}");
        let (r, s, b) = (
            [w("segoeui.ttf"), "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf".into(), "/usr/share/fonts/noto/NotoSans-Regular.ttf".into(),
             "/usr/share/fonts/truetype/noto/NotoSans-Regular.ttf".into(), "/usr/share/fonts/TTF/DejaVuSans.ttf".into(),
             "/System/Library/Fonts/Supplemental/Arial.ttf".into()],
            [w("seguisb.ttf"), "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf".into(), "/usr/share/fonts/noto/NotoSans-SemiBold.ttf".into(),
             "/usr/share/fonts/truetype/noto/NotoSans-SemiBold.ttf".into(), "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf".into(),
             "/System/Library/Fonts/Supplemental/Arial Bold.ttf".into()],
            [w("segoeuib.ttf"), "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf".into(), "/usr/share/fonts/noto/NotoSans-Bold.ttf".into(),
             "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf".into(), "/usr/share/fonts/TTF/DejaVuSans-Bold.ttf".into(),
             "/System/Library/Fonts/Supplemental/Arial Bold.ttf".into()],
        );
        let regular = load(&r).ok_or("no interface font found")?;
        let semibold = load(&s).or_else(|| load(&r)).ok_or("no interface font found")?;
        let bold = load(&b).or_else(|| load(&r)).ok_or("no interface font found")?;
        Ok(Fonts { regular, semibold, bold })
    }
    fn font(&self, w: Weight) -> &Font { match w { Weight::Regular => &self.regular, Weight::Semibold => &self.semibold, Weight::Bold => &self.bold } }

    /// Width of `text` at `size` points.
    pub fn width(&self, text: &str, size: f32, weight: Weight) -> f32 {
        let f = self.font(weight);
        let mut w = 0.0; let mut prev: Option<char> = None;
        for ch in text.chars() {
            if let Some(p) = prev { w += f.horizontal_kern(p, ch, size).unwrap_or(0.0); }
            w += f.metrics(ch, size).advance_width; prev = Some(ch);
        }
        w
    }
    /// Draws one line with its top-left at (x, y) points. `alpha_at(i)` scales each character's opacity (the
    /// letter-by-letter effects use it). Returns the width drawn.
    pub fn draw_with(&self, c: &mut Canvas, text: &str, x: f32, y: f32, size: f32, weight: Weight, color: Rgba, alpha_at: &dyn Fn(usize) -> f32) -> f32 {
        let f = self.font(weight);
        // text follows the canvas's extra transform: moved with it, and sized by its horizontal scale
        let t = c.transform;
        let (x, y) = (x * t.sx + y * t.kx + t.tx, x * t.ky + y * t.sy + t.ty);
        let px = size * c.scale * t.sx.abs().max(0.01);
        let ascent = f.horizontal_line_metrics(px).map(|m| m.ascent).unwrap_or(px * 0.8);
        let (ox, oy) = ((x + c.origin.0) * c.scale, (y + c.origin.1) * c.scale + ascent);
        let (w, h) = (c.pixmap.width() as i32, c.pixmap.height() as i32);
        let mut pen = 0.0f32; let mut prev: Option<char> = None;
        for (i, ch) in text.chars().enumerate() {
            if let Some(p) = prev { pen += f.horizontal_kern(p, ch, px).unwrap_or(0.0); }
            let (m, cover) = f.rasterize(ch, px);
            let a = (color.a * alpha_at(i)).clamp(0.0, 1.0);
            if a > 0.003 && m.width > 0 {
                let gx = (ox + pen).round() as i32 + m.xmin;
                let gy = oy.round() as i32 - m.ymin - m.height as i32;
                let pixels = c.pixmap.pixels_mut();
                for row in 0..m.height as i32 {
                    let py = gy + row; if py < 0 || py >= h { continue; }
                    for col in 0..m.width as i32 {
                        let pxx = gx + col; if pxx < 0 || pxx >= w { continue; }
                        let cov = cover[(row as usize) * m.width + col as usize] as f32 / 255.0 * a;
                        if cov <= 0.0 { continue; }
                        let d = &mut pixels[(py * w + pxx) as usize];
                        // source-over on premultiplied pixels
                        let inv = 1.0 - cov;
                        let nr = color.r as f32 * cov + d.red() as f32 * inv;
                        let ng = color.g as f32 * cov + d.green() as f32 * inv;
                        let nb = color.b as f32 * cov + d.blue() as f32 * inv;
                        let na = 255.0 * cov + d.alpha() as f32 * inv;
                        let na8 = na.round().min(255.0) as u8;
                        if let Some(p) = tiny_skia::PremultipliedColorU8::from_rgba((nr.round() as u8).min(na8), (ng.round() as u8).min(na8), (nb.round() as u8).min(na8), na8) { *d = p; }
                    }
                }
            }
            pen += m.advance_width; prev = Some(ch);
        }
        pen / c.scale
    }
    pub fn draw(&self, c: &mut Canvas, text: &str, x: f32, y: f32, size: f32, weight: Weight, color: Rgba) -> f32 {
        self.draw_with(c, text, x, y, size, weight, color, &|_| 1.0)
    }
    /// Right-aligned: the text ends at `right`.
    pub fn draw_right(&self, c: &mut Canvas, text: &str, right: f32, y: f32, size: f32, weight: Weight, color: Rgba) {
        let w = self.width(text, size, weight);
        self.draw(c, text, right - w, y, size, weight, color);
    }
    /// Breaks text into lines no wider than `max` points.
    pub fn wrap(&self, text: &str, max: f32, size: f32, weight: Weight) -> Vec<String> {
        let mut lines = vec![]; let mut line = String::new();
        for word in text.split_whitespace() {
            let trial = if line.is_empty() { word.to_string() } else { format!("{line} {word}") };
            if self.width(&trial, size, weight) > max && !line.is_empty() { lines.push(std::mem::take(&mut line)); line = word.to_string(); } else { line = trial; }
        }
        if !line.is_empty() { lines.push(line); }
        lines
    }
}
