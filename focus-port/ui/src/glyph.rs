//! The Focus mark and the small symbols the menu uses, drawn as vectors on an 18-point grid like the Mac's.
use crate::draw::{arc, polygon, rounded, Canvas, Rgba};
use tiny_skia::PathBuilder;

/// The Lens: out of session (t = 0) four thick brackets round a dot; in session (t = 1) a solid disc with the dot
/// knocked out. Numbers from the Mac's `glyph()`: stroke 2.6, radius 6.3, gaps 30°, dot 2.3 → 2.8.
/// Drawn on its own transparent canvas of `size` points, so the knocked-out dot shows whatever is behind it.
pub fn lens(size: f32, scale: f32, t: f32, ring: Rgba, dot: Rgba) -> Canvas {
    let mut c = Canvas::new(size, size, scale);
    let k = size / 18.0;
    let t = t.clamp(0.0, 1.0);
    let e = t * t * (3.0 - 2.0 * t);
    let (cx, cy, r, stroke) = (9.0 * k, 9.0 * k, 6.3 * k, 2.6 * k);
    let gap = 30.0 * (1.0 - e);
    if gap < 0.5 { c.ring(cx, cy, r, stroke, ring); } else {
        for q in 0..4 {
            let mid = 45.0 + 90.0 * q as f32;
            if let Some(p) = arc(cx, cy, r, mid - 45.0 + gap / 2.0, mid + 45.0 - gap / 2.0) { c.stroke(&p, ring, stroke, false); }
        }
    }
    c.circle(cx, cy, r, ring.alpha(e));                                   // the disc floods in
    let dr = (2.3 + 0.5 * e) * k;
    let same = ring.r == dot.r && ring.g == dot.g && ring.b == dot.b;
    if same {
        if let Some(p) = PathBuilder::from_circle(cx, cy, dr) { c.knock(&p, e); }    // a see-through dot in the solid disc
        c.circle(cx, cy, dr, dot.alpha(1.0 - e));
    } else { c.circle(cx, cy, dr, dot); }
    c
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Symbol { Check, Empty, Lock, Plus, PlusFilled, Cross, Play, Stop, Chevron, Clock, Wrench, Gear, Sliders, Sparkle, Question }

/// Draws a 16-point symbol with its top-left at (x, y). `ink` is the line or disc colour, `on` the mark inside a
/// filled disc.
pub fn symbol(c: &mut Canvas, s: Symbol, x: f32, y: f32, ink: Rgba, on: Rgba) {
    let (cx, cy) = (x + 8.0, y + 8.0);
    let line = |c: &mut Canvas, pts: &[(f32, f32)], col: Rgba, w: f32| {
        let mut pb = PathBuilder::new();
        for (i, (px, py)) in pts.iter().enumerate() { if i == 0 { pb.move_to(x + px, y + py) } else { pb.line_to(x + px, y + py) } }
        if let Some(p) = pb.finish() { c.stroke(&p, col, w, true) }
    };
    match s {
        Symbol::Check => { c.circle(cx, cy, 7.5, ink); line(c, &[(4.6, 8.3), (7.0, 10.7), (11.4, 5.6)], on, 1.6); }
        Symbol::Empty => c.ring(cx, cy, 6.9, 1.2, ink),
        Symbol::Lock => {
            c.circle(cx, cy, 7.5, ink);
            c.rect(x + 5.0, y + 7.4, 6.0, 4.6, 1.0, on);
            if let Some(p) = arc(cx, y + 7.4, 1.9, 180.0, 360.0) { c.stroke(&p, on, 1.2, true) }
        }
        Symbol::Plus => { c.ring(cx, cy, 6.9, 1.2, ink); line(c, &[(8.0, 4.8), (8.0, 11.2)], ink, 1.3); line(c, &[(4.8, 8.0), (11.2, 8.0)], ink, 1.3); }
        Symbol::PlusFilled => { c.circle(cx, cy, 7.5, ink); line(c, &[(8.0, 4.8), (8.0, 11.2)], on, 1.5); line(c, &[(4.8, 8.0), (11.2, 8.0)], on, 1.5); }
        Symbol::Cross => { c.circle(cx, cy, 7.5, ink); line(c, &[(5.4, 5.4), (10.6, 10.6)], on, 1.5); line(c, &[(10.6, 5.4), (5.4, 10.6)], on, 1.5); }
        Symbol::Play => { c.ring(cx, cy, 6.9, 1.2, ink); if let Some(p) = polygon(&[(x + 6.6, y + 5.2), (x + 11.2, y + 8.0), (x + 6.6, y + 10.8)]) { c.fill(&p, ink) } }
        Symbol::Stop => { c.circle(cx, cy, 7.5, ink); c.rect(x + 5.4, y + 5.4, 5.2, 5.2, 1.0, on); }
        Symbol::Chevron => line(c, &[(6.0, 4.6), (9.6, 8.0), (6.0, 11.4)], ink, 1.4),
        Symbol::Clock => { c.ring(cx, cy, 6.6, 1.2, ink); line(c, &[(8.0, 4.6), (8.0, 8.2), (10.4, 9.6)], ink, 1.2); }
        Symbol::Wrench => { line(c, &[(4.2, 11.8), (9.6, 6.4)], ink, 1.8); if let Some(p) = arc(x + 10.8, y + 5.2, 2.6, 40.0, 320.0) { c.stroke(&p, ink, 1.4, true) } }
        Symbol::Gear => {
            c.ring(cx, cy, 2.2, 1.2, ink); c.ring(cx, cy, 5.0, 1.3, ink);
            for i in 0..8 { let a = (45.0 * i as f32).to_radians(); c.line(cx + 5.4 * a.cos(), cy + 5.4 * a.sin(), cx + 7.2 * a.cos(), cy + 7.2 * a.sin(), ink, 1.5); }
        }
        Symbol::Sliders => {
            for (i, kx) in [10.4f32, 5.6, 8.6].iter().enumerate() {
                let ly = 4.2 + 3.8 * i as f32;
                line(c, &[(2.6, ly), (13.4, ly)], ink, 1.2);
                c.circle(x + kx, y + ly, 1.7, ink);
            }
        }
        Symbol::Sparkle => {
            let star = |c: &mut Canvas, sx: f32, sy: f32, r: f32| {
                let q = r * 0.28;
                if let Some(p) = polygon(&[(sx, sy - r), (sx + q, sy - q), (sx + r, sy), (sx + q, sy + q), (sx, sy + r), (sx - q, sy + q), (sx - r, sy), (sx - q, sy - q)]) { c.fill(&p, ink) }
            };
            star(c, x + 6.6, y + 8.8, 5.0); star(c, x + 12.2, y + 4.0, 2.6);
        }
        Symbol::Question => {
            c.ring(cx, cy, 6.9, 1.1, ink);
            if let Some(p) = arc(cx, y + 6.6, 2.1, 190.0, 420.0) { c.stroke(&p, ink, 1.2, true) }
            line(c, &[(8.0, 8.6), (8.0, 9.6)], ink, 1.2); c.circle(cx, y + 11.6, 0.8, ink);
        }
    }
}

/// A stand-in app icon (a tinted rounded square) for apps whose real icon couldn't be read.
pub fn placeholder(c: &mut Canvas, x: f32, y: f32, size: f32, seed: &str, opacity: f32) {
    let h = seed.bytes().fold(7u32, |a, b| a.wrapping_mul(31).wrapping_add(b as u32));
    let hues = [0x4A90E2u32, 0x7B61FF, 0xE8833A, 0x34A853, 0xD64B6A, 0x2BB5B0];
    if let Some(p) = rounded(x, y, size, size, size * 0.24) { c.fill(&p, Rgba::hex(hues[(h % 6) as usize], opacity)) }
}
