//! The session animation: the pill pops in, a hit stop, the apps fan out above it and are pulled into the Focus
//! icon (start) — or fly out of the icon, gather, and drop into the pill (end).
//!
//! This is a line-for-line port of the Mac app's `SessionPill.play` as it stood in 0.17.0, the version its owner
//! signed off. Every number here is the Mac's. Do not change the timing or the motion; port fixes only.
//! Coordinates are y-up, as on the Mac: `home` is the pill's centre, `target` the Focus icon's centre.
use crate::draw::{rounded, Canvas, Rgba};
use crate::text::{Fonts, Weight};
use crate::{glyph, Image, Theme};
use tiny_skia::Transform;

fn ease(x: f64) -> f64 { x.clamp(0.0, 1.0) }
fn ease_out(x: f64) -> f64 { let t = ease(x); 1.0 - (1.0 - t).powi(3) }
fn ease_in(x: f64) -> f64 { let t = ease(x); t * t * t }
fn ease_back(x: f64) -> f64 { let t = ease(x) - 1.0; let k = 1.9; 1.0 + (k + 1.0) * t * t * t + k * t * t }

/// How long the icons stay on screen: (after the hit stop at start, before the drop at end). Normal is the
/// original timing and the standard; Slow and Fast change only these holds.
pub fn hold(speed: i8) -> (f64, f64) { match speed { -1 => (1.2, 0.9), 1 => (0.08, 0.0), _ => (0.24, 0.02) } }

pub struct Show {
    pub start: bool,
    /// Up to nine are shown.
    pub icons: Vec<Image>,
    pub label: String,
    pub hold: (f64, f64),
    /// The pill's centre and the Focus icon's centre, in points, y-up, within the area being drawn.
    pub home: (f32, f32),
    pub target: (f32, f32),
}

const POP_IN: f64 = 0.16;
const STOP: f64 = 0.10;
const STAGGER: f64 = 0.035;
const FLY: f64 = 0.34;
const ZIP: f64 = 0.22;

impl Show {
    fn n(&self) -> usize { self.icons.len().min(9) }
    fn spread(&self) -> f64 { self.n().saturating_sub(1) as f64 * STAGGER }
    fn impact(&self) -> f64 { if self.start { POP_IN } else { POP_IN + self.spread() + FLY + self.hold.1 + 0.20 } }
    fn after(&self) -> f64 { self.impact() + STOP }
    fn zip_at(&self) -> f64 { if self.start { self.after() + self.hold.0 + self.spread() + FLY } else { self.after() + 0.06 } }
    /// Seconds from the first frame to the last.
    pub fn length(&self) -> f64 { self.zip_at() + ZIP + 0.05 }

    pub fn pill_size(&self, fonts: &Fonts) -> (f32, f32) { ((fonts.width(&self.label, 15.0, Weight::Semibold).ceil() + 74.0).max(136.0), 44.0) }

    fn fan(&self, i: usize) -> (f32, f32) {
        let n = self.n();
        let a = if n == 1 { std::f32::consts::FRAC_PI_2 } else { std::f32::consts::PI * (0.78 - 0.56 * i as f32 / (n - 1) as f32) };
        (self.home.0 + a.cos() * 150.0, self.home.1 + 26.0 + a.sin() * 92.0)
    }

    /// Draws the frame at `now` seconds onto `c` (an area `height` points tall; y is flipped here, once).
    pub fn draw(&self, c: &mut Canvas, height: f32, now: f64, theme: &Theme, fonts: &Fonts) {
        let (impact, after, zip_at) = (self.impact(), self.after(), self.zip_at());
        let lerp = |a: (f32, f32), b: (f32, f32), t: f64| (a.0 + (b.0 - a.0) * t as f32, a.1 + (b.1 - a.1) * t as f32);
        let n = self.n();

        // —— the pill: zop in, shake during the stop, zip out sideways at the end
        let in_p = now / POP_IN;
        let sc = 0.4 + 0.6 * ease_back(in_p);
        let (mut x, mut op) = (self.home.0 as f64, ease(in_p * 1.5));
        if now >= impact && now < after { x += (now * 260.0).sin() * 3.0; }
        let (sx, sy) = if now >= zip_at {
            let z = (now - zip_at) / ZIP;
            x += ease_in(z) * 420.0; op = 1.0 - ease_in(z);
            (1.0 + 0.35 * ease_in(z), 1.0 - 0.18 * ease_in(z))                   // stretch as it goes
        } else { (sc, sc) };
        let (pw, ph) = self.pill_size(fonts);
        let (pcx, pcy) = (x as f32, height - self.home.1);
        let op = op as f32;
        if op > 0.003 {
            c.transform = Transform::from_translate(-pcx, -pcy).post_scale(sx as f32, sy as f32).post_translate(pcx, pcy);
            let (px, py) = (pcx - pw / 2.0, pcy - ph / 2.0);
            for (grow, a) in [(10.0f32, 0.05f32), (6.0, 0.08), (3.0, 0.12)] {       // a soft shadow under the pill
                c.rect(px - grow, py - grow + 4.0, pw + grow * 2.0, ph + grow * 2.0, 22.0 + grow, Rgba::new(0, 0, 0, a * op));
            }
            c.rect(px, py, pw, ph, 22.0, theme.hud_bg.alpha(op));
            if let Some(p) = rounded(px + 0.5, py + 0.5, pw - 1.0, ph - 1.0, 21.5) { c.stroke(&p, theme.hud_edge.alpha(op), 1.0, false) }
            let snapped = now >= impact;                                           // the mark snaps at the impact
            let t = if self.start == snapped { 1.0 } else { 0.0 };
            let mark = glyph::lens(24.0, c.scale, t, theme.hud_ink, theme.hud_ink);
            c.layer(&mark, px + 16.0, py + 10.0, op);
            fonts.draw(c, &self.label, px + 50.0, py + 12.0, 15.0, Weight::Semibold, theme.hud_ink.alpha(op));
            let flash = if now >= impact { 0.85 * (1.0 - ease((now - impact) / 0.16)) } else { 0.0 };
            c.rect(px, py, pw, ph, 22.0, theme.hud_ink.alpha(flash as f32 * op));
            c.transform = Transform::identity();
        }

        // —— the apps
        for i in 0..n {
            let d = i as f64 * STAGGER;
            let (pos, opacity, scale);
            if self.start {
                if now < after { continue; }
                let burst = (now - after - d * 0.5) / 0.16;
                let suck = (now - after - self.hold.0 - d) / FLY;
                if suck <= 0.0 {
                    pos = lerp(self.home, self.fan(i), ease_back(burst)); opacity = ease(burst * 2.0); scale = 0.5 + 0.5 * ease_out(burst);
                } else {
                    let k = ease_in(suck);
                    pos = lerp(self.fan(i), self.target, k); opacity = 1.0 - ease((suck - 0.6) / 0.4); scale = 1.0 - 0.8 * k;
                }
            } else {
                let out = (now - POP_IN - d) / FLY;
                let drop = (now - POP_IN - self.spread() - FLY - self.hold.1) / 0.12;
                if out <= 0.0 { continue; }
                if drop <= 0.0 {
                    let k = ease_out(out);
                    pos = lerp(self.target, self.fan(i), k); opacity = ease(out * 3.0); scale = 0.2 + 0.8 * k;
                } else {
                    let k = ease_in(drop);
                    pos = lerp(self.fan(i), self.home, k); opacity = 1.0 - k; scale = 1.0 - 0.6 * k;
                }
            }
            let side = 44.0 * scale as f32;
            c.image(&self.icons[i], pos.0 - side / 2.0, height - pos.1 - side / 2.0, side, side, opacity as f32);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn show(start: bool, n: usize, speed: i8) -> Show {
        Show { start, icons: vec![Image { width: 1, height: 1, rgba: vec![255; 4] }; n], label: "Focus".into(), hold: hold(speed), home: (400.0, 96.0), target: (700.0, 20.0) }
    }
    /// The Mac's own numbers: with Normal speed and six apps, start lasts 0.16 + 0.10 + 0.24 + 5×0.035 + 0.34 +
    /// 0.22 + 0.05 seconds, and end 0.16 + 5×0.035 + 0.34 + 0.02 + 0.20 + 0.10 + 0.06 + 0.22 + 0.05.
    #[test] fn timing_matches_the_mac() {
        assert!((show(true, 6, 0).length() - 1.285).abs() < 1e-9);
        assert!((show(false, 6, 0).length() - 1.325).abs() < 1e-9);
        assert_eq!(hold(0), (0.24, 0.02));
        assert!(show(true, 6, -1).length() > show(true, 6, 0).length() && show(true, 6, 1).length() < show(true, 6, 0).length());
        assert_eq!(show(true, 30, 0).n(), 9);
    }
    #[test] fn the_fan_is_the_mac_arc() {
        let s = show(true, 3, 0);
        let (l, m, r) = (s.fan(0), s.fan(1), s.fan(2));
        assert!((m.0 - 400.0).abs() < 0.01 && (m.1 - (96.0 + 26.0 + 92.0)).abs() < 0.01);       // the middle one straight above
        assert!(l.0 < 400.0 && r.0 > 400.0 && (l.1 - r.1).abs() < 0.01);
        assert!((show(true, 1, 0).fan(0).0 - 400.0).abs() < 0.01);
    }
}
