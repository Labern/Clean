//! A small canvas over tiny-skia: shapes in points, drawn in pixels.
use crate::Image;
use tiny_skia::{BlendMode, Color, FillRule, FilterQuality, Paint, Path, PathBuilder, Pixmap, PixmapPaint, Stroke, Transform};

#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Rgba { pub r: u8, pub g: u8, pub b: u8, pub a: f32 }
impl Rgba {
    pub const fn new(r: u8, g: u8, b: u8, a: f32) -> Rgba { Rgba { r, g, b, a } }
    pub const fn hex(rgb: u32, a: f32) -> Rgba { Rgba { r: (rgb >> 16) as u8, g: (rgb >> 8) as u8, b: rgb as u8, a } }
    pub fn alpha(self, k: f32) -> Rgba { Rgba { a: (self.a * k).clamp(0.0, 1.0), ..self } }
    fn color(self) -> Color { Color::from_rgba8(self.r, self.g, self.b, (self.a.clamp(0.0, 1.0) * 255.0).round() as u8) }
}

/// A pixel surface with a scale (pixels per point) and an origin, so drawing code works in points.
pub struct Canvas {
    pub pixmap: Pixmap,
    pub scale: f32,
    /// Added to every x, y (points): lets one drawing routine be placed anywhere.
    pub origin: (f32, f32),
    /// Applied on top (rotation / scaling about a point), for the animation.
    pub transform: Transform,
}

impl Canvas {
    pub fn new(width_pt: f32, height_pt: f32, scale: f32) -> Canvas {
        let w = (width_pt * scale).ceil().max(1.0) as u32;
        let h = (height_pt * scale).ceil().max(1.0) as u32;
        Canvas { pixmap: Pixmap::new(w, h).expect("canvas size"), scale, origin: (0.0, 0.0), transform: Transform::identity() }
    }
    pub fn width(&self) -> f32 { self.pixmap.width() as f32 / self.scale }
    pub fn height(&self) -> f32 { self.pixmap.height() as f32 / self.scale }
    fn ts(&self) -> Transform {
        // the extra transform works in the drawing's own coordinates; the origin then places the whole drawing
        self.transform.post_translate(self.origin.0, self.origin.1).post_scale(self.scale, self.scale)
    }
    fn paint(c: Rgba) -> Paint<'static> { let mut p = Paint::default(); p.set_color(c.color()); p.anti_alias = true; p }

    pub fn clear(&mut self, c: Rgba) { self.pixmap.fill(c.color()); }
    pub fn fill(&mut self, path: &Path, c: Rgba) {
        if c.a <= 0.003 { return; }
        let ts = self.ts();
        self.pixmap.fill_path(path, &Self::paint(c), FillRule::Winding, ts, None);
    }
    pub fn fill_even_odd(&mut self, path: &Path, c: Rgba) {
        if c.a <= 0.003 { return; }
        let ts = self.ts();
        self.pixmap.fill_path(path, &Self::paint(c), FillRule::EvenOdd, ts, None);
    }
    /// Punches a see-through hole (used for the dot knocked out of the solid icon).
    pub fn knock(&mut self, path: &Path, amount: f32) {
        if amount <= 0.003 { return; }
        let mut p = Self::paint(Rgba::new(0, 0, 0, amount)); p.blend_mode = BlendMode::DestinationOut;
        let ts = self.ts();
        self.pixmap.fill_path(path, &p, FillRule::Winding, ts, None);
    }
    pub fn stroke(&mut self, path: &Path, c: Rgba, width: f32, round: bool) {
        if c.a <= 0.003 || width <= 0.0 { return; }
        let mut s = Stroke::default(); s.width = width;
        if round { s.line_cap = tiny_skia::LineCap::Round; s.line_join = tiny_skia::LineJoin::Round; }
        let ts = self.ts();
        self.pixmap.stroke_path(path, &Self::paint(c), &s, ts, None);
    }
    pub fn rect(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, c: Rgba) { if let Some(p) = rounded(x, y, w, h, radius) { self.fill(&p, c) } }
    pub fn rect_stroke(&mut self, x: f32, y: f32, w: f32, h: f32, radius: f32, c: Rgba, width: f32) {
        if let Some(p) = rounded(x, y, w, h, radius) { self.stroke(&p, c, width, false) }
    }
    pub fn circle(&mut self, cx: f32, cy: f32, r: f32, c: Rgba) { if r > 0.02 { if let Some(p) = PathBuilder::from_circle(cx, cy, r) { self.fill(&p, c) } } }
    pub fn ring(&mut self, cx: f32, cy: f32, r: f32, width: f32, c: Rgba) { if let Some(p) = PathBuilder::from_circle(cx, cy, r) { self.stroke(&p, c, width, false) } }
    pub fn line(&mut self, x0: f32, y0: f32, x1: f32, y1: f32, c: Rgba, width: f32) {
        let mut pb = PathBuilder::new(); pb.move_to(x0, y0); pb.line_to(x1, y1);
        if let Some(p) = pb.finish() { self.stroke(&p, c, width, true) }
    }
    /// Draws a picture into the box (x, y, w, h), in points.
    pub fn image(&mut self, img: &Image, x: f32, y: f32, w: f32, h: f32, opacity: f32) {
        if opacity <= 0.003 || img.width == 0 || img.height == 0 { return; }
        let Some(mut src) = Pixmap::new(img.width, img.height) else { return };
        for (px, s) in src.pixels_mut().iter_mut().zip(img.rgba.chunks_exact(4)) {
            let a = s[3] as u32;
            if let Some(c) = tiny_skia::PremultipliedColorU8::from_rgba((s[0] as u32 * a / 255) as u8, (s[1] as u32 * a / 255) as u8, (s[2] as u32 * a / 255) as u8, s[3]) { *px = c; }
        }
        let ts = Transform::from_scale(w / img.width as f32, h / img.height as f32).post_translate(x, y).post_concat(self.ts());
        let paint = PixmapPaint { opacity: opacity.clamp(0.0, 1.0), blend_mode: BlendMode::SourceOver, quality: FilterQuality::Bilinear };
        self.pixmap.draw_pixmap(0, 0, src.as_ref(), &paint, ts, None);
    }
    /// Composites another canvas of the same scale at (x, y) points.
    pub fn layer(&mut self, other: &Canvas, x: f32, y: f32, opacity: f32) {
        let ts = Transform::from_scale(1.0 / other.scale, 1.0 / other.scale).post_translate(x, y).post_concat(self.ts());
        let paint = PixmapPaint { opacity: opacity.clamp(0.0, 1.0), blend_mode: BlendMode::SourceOver, quality: FilterQuality::Bilinear };
        self.pixmap.draw_pixmap(0, 0, other.pixmap.as_ref(), &paint, ts, None);
    }
    /// Straight (not premultiplied) BGRA bytes, top row first: what a Windows layered window wants premultiplied,
    /// so this returns PREMULTIPLIED BGRA.
    pub fn bgra_premultiplied(&self) -> Vec<u8> {
        let mut out = Vec::with_capacity(self.pixmap.data().len());
        for p in self.pixmap.pixels() { out.extend_from_slice(&[p.blue(), p.green(), p.red(), p.alpha()]); }
        out
    }
    pub fn save_png(&self, path: &str) -> Result<(), String> { self.pixmap.save_png(path).map_err(|e| e.to_string()) }
}

/// A rounded rectangle (radius clamped to half the shorter side).
pub fn rounded(x: f32, y: f32, w: f32, h: f32, radius: f32) -> Option<Path> {
    if w <= 0.0 || h <= 0.0 { return None; }
    let r = radius.min(w / 2.0).min(h / 2.0).max(0.0);
    let k = r * 0.5523;
    let mut p = PathBuilder::new();
    p.move_to(x + r, y);
    p.line_to(x + w - r, y); p.cubic_to(x + w - r + k, y, x + w, y + r - k, x + w, y + r);
    p.line_to(x + w, y + h - r); p.cubic_to(x + w, y + h - r + k, x + w - r + k, y + h, x + w - r, y + h);
    p.line_to(x + r, y + h); p.cubic_to(x + r - k, y + h, x, y + h - r + k, x, y + h - r);
    p.line_to(x, y + r); p.cubic_to(x, y + r - k, x + r - k, y, x + r, y);
    p.close();
    p.finish()
}
/// An open arc, angles in degrees, drawn as short segments.
pub fn arc(cx: f32, cy: f32, r: f32, from_deg: f32, to_deg: f32) -> Option<Path> {
    let steps = (((to_deg - from_deg).abs() / 4.0).ceil() as usize).max(2);
    let mut p = PathBuilder::new();
    for i in 0..=steps {
        let a = (from_deg + (to_deg - from_deg) * i as f32 / steps as f32).to_radians();
        let (x, y) = (cx + r * a.cos(), cy + r * a.sin());
        if i == 0 { p.move_to(x, y) } else { p.line_to(x, y) }
    }
    p.finish()
}
pub fn polygon(points: &[(f32, f32)]) -> Option<Path> {
    let mut p = PathBuilder::new();
    for (i, (x, y)) in points.iter().enumerate() { if i == 0 { p.move_to(*x, *y) } else { p.line_to(*x, *y) } }
    p.close();
    p.finish()
}
/// A five-point star centred at (cx, cy) with outer radius r.
pub fn star5(cx: f32, cy: f32, r: f32) -> Option<Path> {
    let pts: Vec<(f32, f32)> = (0..10).map(|i| {
        let a = (-90.0 + 36.0 * i as f32).to_radians();
        let rr = if i % 2 == 0 { r } else { r * 0.4 };
        (cx + rr * a.cos(), cy + rr * a.sin())
    }).collect();
    polygon(&pts)
}
