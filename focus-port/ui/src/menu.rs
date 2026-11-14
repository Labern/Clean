//! The menu, row for row as in the Mac app (0.18.25): Focus / Quit, the app list with Usage, Critical System
//! Processes, Modes, the three submenus, the big button with its caption, and the help link and maker's mark.
use crate::draw::{star5, Canvas};
use crate::glyph::{self, Symbol};
use crate::text::{Fonts, Weight};
use crate::{Image, Theme};
use focus_core::{caption, memory_text, AppRef, OpenApp, State};

pub const WIDTH: f32 = 320.0;

#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Hit {
    Quit,
    SortByUsage,
    /// An open app's row: tick or untick it (or, in a session, take it out).
    App(String),
    /// A closed app's row during a session: bring it back.
    Closed(String),
    Mode(String),
    AddOrRemove,
    CreateMode,
    EditModes,
    SuggestedModes,
    PastSessions,
    Tools,
    Settings,
    Button,
    Help,
}

#[derive(Clone, Debug)]
pub struct AppItem { pub id: String, pub name: String, pub detail: String, pub icon: Option<Image>, pub on: bool, pub hit: Option<Hit>, pub locked: bool }
#[derive(Clone, Debug)]
pub struct ModeItem { pub id: String, pub name: String, pub key: String, pub live: bool, pub icons: Vec<(String, Option<Image>)> }

#[derive(Clone, Debug)]
pub enum Row {
    Title,
    Columns,
    App(AppItem),
    Separator,
    Heading(String),
    Explain(Vec<String>),
    Mode(ModeItem),
    Command { title: String, symbol: Symbol, chevron: bool, hit: Hit },
    Button { title: String, key: String, caption: Vec<String> },
    Footer,
}

pub struct Menu { pub rows: Vec<Row>, pub theme: Theme }

/// What the platform knows about the apps: the open ones, and a picture for any app id it can find one for.
pub struct Apps<'a> {
    pub open: &'a [OpenApp],
    pub icon: &'a dyn Fn(&AppRef) -> Option<Image>,
}

const PAD: f32 = 5.0;

impl Menu {
    /// Builds the menu for the current state. `session_key` is how the start/end shortcut is written on this
    /// system ("Ctrl+Shift+F"); `mode_key(n)` how a mode's number is ("Ctrl+1").
    pub fn build(state: &State, apps: &Apps, fonts: &Fonts, session_key: &str, mode_key: &dyn Fn(u8) -> String) -> Menu {
        let theme = if state.settings.light { Theme::light() } else { Theme::dark() };
        let style = state.settings.heading_style;
        let mut rows = vec![Row::Title];
        let explain = |rows: &mut Vec<Row>, text: &str| { if style == 2 { rows.push(Row::Explain(fonts.wrap(text, WIDTH - 28.0, 11.0, Weight::Regular))) } };
        let section = |rows: &mut Vec<Row>, name: &str, few: &str, more: &str, optional: bool| {
            if style == 0 { if !optional { rows.push(Row::Heading(name.to_string())) } return; }
            rows.push(Row::Heading(format!("{name} — {few}")));
            if style == 2 { rows.push(Row::Explain(fonts.wrap(more, WIDTH - 28.0, 11.0, Weight::Regular))) }
        };
        let listed = state.listed(apps.open);
        let never = &state.never_close;
        let item = |a: &OpenApp, on: bool, hit: Option<Hit>| AppItem {
            id: a.app.id.clone(), name: a.app.name.clone(), detail: if a.memory > 0 { memory_text(a.memory) } else { String::new() },
            icon: (apps.icon)(&a.app), on, hit, locked: false,
        };
        if let Some(live) = state.live() {
            rows.push(Row::Columns);
            explain(&mut rows, "These apps are in your session. Click one to take it out.");
            for a in listed.iter().filter(|a| !never.contains(&a.app.id)) { rows.push(Row::App(item(a, true, Some(Hit::App(a.app.id.clone()))))); }
            let away: Vec<&AppRef> = live.closed.iter().filter(|c| !apps.open.iter().any(|o| o.app.id == c.id)).collect();
            if !away.is_empty() {
                rows.push(Row::Separator);
                rows.push(Row::Heading("Apps Outside Session".into()));
                explain(&mut rows, "These apps are not in the session right now. Click one to add it to the session.");
                for a in away {
                    rows.push(Row::App(AppItem { id: a.id.clone(), name: a.name.clone(), detail: String::new(), icon: (apps.icon)(a), on: false,
                                                 hit: Some(Hit::Closed(a.id.clone())), locked: false }));
                }
            }
        } else {
            section(&mut rows, "Keep open this session", "click to choose",
                    "Tick the apps you want to keep. Everything else closes when the session starts and comes back when it ends.", true);
            rows.push(Row::Columns);
            for a in listed.iter().filter(|a| !never.contains(&a.app.id)) {
                rows.push(Row::App(item(a, state.keep.contains(&a.app.id), Some(Hit::App(a.app.id.clone())))));
            }
        }
        rows.push(Row::Separator);
        section(&mut rows, "Critical System Processes", "never quit", "These apps are never quit or hidden, in any session. Change the list with Add or remove.", false);
        for a in listed.iter().filter(|a| never.contains(&a.app.id)) {
            rows.push(Row::App(AppItem { locked: true, hit: None, ..item(a, true, None) }));        // shown, never clickable
        }
        rows.push(Row::Command { title: "Add or remove…".into(), symbol: Symbol::Plus, chevron: false, hit: Hit::AddOrRemove });
        rows.push(Row::Separator);
        section(&mut rows, "Modes", "frequently used sessions", "A mode is a set of apps you keep open. Click one to start it, or press its number. Right-click to edit it.", false);
        let live_mode = state.live().and_then(|s| s.mode_id.clone());
        for m in &state.modes {
            rows.push(Row::Mode(ModeItem {
                id: m.id.clone(), name: m.name.clone(), key: m.key.map(|k| mode_key(k)).unwrap_or_default(), live: live_mode.as_deref() == Some(m.id.as_str()),
                icons: m.apps.iter().take(3).map(|a| (a.id.clone(), (apps.icon)(a))).collect(),
            }));
        }
        rows.push(Row::Command { title: "Create New Mode".into(), symbol: Symbol::Plus, chevron: true, hit: Hit::CreateMode });
        if !state.modes.is_empty() { rows.push(Row::Command { title: "Edit Modes".into(), symbol: Symbol::Sliders, chevron: true, hit: Hit::EditModes }); }
        rows.push(Row::Command { title: "Suggested Modes".into(), symbol: Symbol::Sparkle, chevron: true, hit: Hit::SuggestedModes });
        rows.push(Row::Separator);
        if !state.sessions.is_empty() { rows.push(Row::Command { title: "Past sessions".into(), symbol: Symbol::Clock, chevron: true, hit: Hit::PastSessions }); }
        rows.push(Row::Command { title: "Tools".into(), symbol: Symbol::Wrench, chevron: true, hit: Hit::Tools });
        rows.push(Row::Command { title: "Settings".into(), symbol: Symbol::Gear, chevron: true, hit: Hit::Settings });
        rows.push(Row::Separator);
        rows.push(Row::Button {
            title: if state.focused { "End Session".into() } else { "Start New Session".into() }, key: session_key.to_string(),
            caption: fonts.wrap(&caption(state, apps.open), WIDTH - 36.0, 11.0, Weight::Regular),
        });
        rows.push(Row::Footer);
        Menu { rows, theme }
    }

    fn row_height(row: &Row) -> f32 {
        match row {
            Row::Title => 38.0, Row::Columns => 22.0, Row::App(_) | Row::Mode(_) => 26.0, Row::Separator => 11.0, Row::Heading(_) => 24.0,
            Row::Explain(lines) => lines.len() as f32 * 14.0 + 6.0, Row::Command { .. } => 24.0,
            Row::Button { caption, .. } => 66.0 + caption.len().max(1) as f32 * 14.0 + 12.0, Row::Footer => 22.0,
        }
    }
    pub fn height(&self) -> f32 { PAD * 2.0 + self.rows.iter().map(Self::row_height).sum::<f32>() }

    fn tops(&self) -> Vec<f32> {
        let mut y = PAD;
        self.rows.iter().map(|r| { let t = y; y += Self::row_height(r); t }).collect()
    }

    /// What is under the pointer at (x, y) points: the row's index and what a click there does.
    pub fn hit(&self, x: f32, y: f32) -> Option<(usize, Hit)> {
        if !(0.0..WIDTH).contains(&x) { return None; }
        let tops = self.tops();
        let i = (0..self.rows.len()).find(|&i| y >= tops[i] && y < tops[i] + Self::row_height(&self.rows[i]))?;
        let hit = match &self.rows[i] {
            Row::Title => if x > WIDTH - 62.0 { Some(Hit::Quit) } else { None },
            Row::Columns => if x > WIDTH - 110.0 { Some(Hit::SortByUsage) } else { None },
            Row::App(a) => a.hit.clone(),
            Row::Mode(m) => Some(Hit::Mode(m.id.clone())),
            Row::Command { hit, .. } => Some(hit.clone()),
            Row::Button { .. } => if y - tops[i] < 60.0 && x > 12.0 && x < WIDTH - 12.0 { Some(Hit::Button) } else { None },
            Row::Footer => if x < 170.0 { Some(Hit::Help) } else { None },
            _ => None,
        }?;
        Some((i, hit))
    }

    /// Draws the whole menu. `hover` is the row under the pointer; `down` whether the button is being pressed.
    pub fn render(&self, fonts: &Fonts, scale: f32, hover: Option<usize>, down: bool) -> Canvas {
        let t = &self.theme;
        let h = self.height();
        let mut c = Canvas::new(WIDTH, h, scale);
        c.rect(0.0, 0.0, WIDTH, h, 10.0, t.background);
        c.rect_stroke(0.5, 0.5, WIDTH - 1.0, h - 1.0, 9.5, t.edge, 1.0);
        let tops = self.tops();
        for (i, row) in self.rows.iter().enumerate() {
            let y = tops[i];
            let hot = hover == Some(i);
            let highlight = |c: &mut Canvas| c.rect(5.0, y + 1.0, WIDTH - 10.0, Self::row_height(row) - 2.0, 5.0, t.hover);
            match row {
                Row::Title => {
                    fonts.draw(&mut c, "Focus", 14.0, y + 6.0, 21.0, Weight::Bold, t.text);
                    let w = fonts.width("Quit", 13.0, Weight::Regular);
                    if hot { c.rect(WIDTH - w - 26.0, y + 9.0, w + 16.0, 20.0, 5.0, t.hover); }
                    fonts.draw(&mut c, "Quit", WIDTH - w - 18.0, y + 11.0, 13.0, Weight::Regular, if hot { t.text } else { t.faint });
                }
                Row::Columns => {
                    fonts.draw(&mut c, "Apps in Session", 14.0, y + 4.0, 11.0, Weight::Semibold, t.heading);
                    fonts.draw_right(&mut c, "Usage", WIDTH - 42.0, y + 4.0, 11.0, Weight::Semibold, t.heading);
                }
                Row::Heading(text) => { fonts.draw(&mut c, text, 14.0, y + 7.0, 11.0, Weight::Semibold, t.heading); }
                Row::Explain(lines) => for (k, l) in lines.iter().enumerate() { fonts.draw(&mut c, l, 14.0, y + 2.0 + 14.0 * k as f32, 11.0, Weight::Regular, t.faint); },
                Row::Separator => c.rect(14.0, y + 5.0, WIDTH - 28.0, 1.0, 0.0, t.edge),
                Row::App(a) => {
                    let clickable = a.hit.is_some();
                    if hot && clickable { highlight(&mut c) }
                    let dim = if a.on { 1.0 } else { 0.55 };
                    match &a.icon { Some(img) => c.image(img, 14.0, y + 5.0, 16.0, 16.0, dim), None => glyph::placeholder(&mut c, 14.0, y + 5.0, 16.0, &a.id, dim) }
                    fonts.draw(&mut c, &a.name, 38.0, y + 5.0, 13.0, Weight::Regular, if a.on { t.text } else { t.faint });
                    fonts.draw_right(&mut c, &a.detail, WIDTH - 42.0, y + 7.0, 11.0, Weight::Regular, t.faint);
                    let mx = WIDTH - 32.0;
                    if a.locked { glyph::symbol(&mut c, Symbol::Lock, mx, y + 5.0, t.accent, t.on_accent) }
                    else if hot && clickable { if a.on { glyph::symbol(&mut c, Symbol::Cross, mx, y + 5.0, t.accent, t.on_accent) } else { glyph::symbol(&mut c, Symbol::Plus, mx, y + 5.0, t.text, t.text) } }
                    else if a.on { glyph::symbol(&mut c, Symbol::Check, mx, y + 5.0, t.accent, t.on_accent) }
                    else { glyph::symbol(&mut c, Symbol::Empty, mx, y + 5.0, t.dropped, t.dropped) }
                }
                Row::Mode(m) => {
                    if hot { highlight(&mut c) }
                    for (k, (id, img)) in m.icons.iter().enumerate().rev() {
                        let x = 14.0 + 7.0 * k as f32;
                        match img { Some(img) => c.image(img, x, y + 5.0, 16.0, 16.0, 1.0), None => glyph::placeholder(&mut c, x, y + 5.0, 16.0, id, 1.0) }
                    }
                    fonts.draw(&mut c, &m.name, 58.0, y + 5.0, 13.0, Weight::Regular, t.text);     // one fixed place, clear of three icons
                    fonts.draw_right(&mut c, &m.key, WIDTH - 42.0, y + 5.0, 13.0, Weight::Regular, t.faint);
                    let mx = WIDTH - 32.0;
                    if m.live { glyph::symbol(&mut c, if hot { Symbol::Stop } else { Symbol::Check }, mx, y + 5.0, t.accent, t.on_accent) }
                    else if hot { glyph::symbol(&mut c, Symbol::Play, mx, y + 5.0, t.text, t.text) }
                }
                Row::Command { title, symbol, chevron, .. } => {
                    if hot { highlight(&mut c) }
                    glyph::symbol(&mut c, *symbol, 14.0, y + 4.0, t.text, t.text);
                    fonts.draw(&mut c, title, 38.0, y + 4.0, 13.0, Weight::Regular, t.text);
                    if *chevron { glyph::symbol(&mut c, Symbol::Chevron, WIDTH - 26.0, y + 4.0, t.faint, t.faint) }
                }
                Row::Button { title, key, caption } => {
                    let fill = if down { t.accent.alpha(0.7) } else if hot { t.accent.alpha(0.88) } else { t.accent };
                    c.rect(12.0, y + 8.0, WIDTH - 24.0, 48.0, 11.0, fill);
                    fonts.draw(&mut c, title, 26.0, y + 23.0, 14.0, Weight::Semibold, t.on_accent);
                    fonts.draw_right(&mut c, key, WIDTH - 26.0, y + 24.0, 13.0, Weight::Regular, t.on_accent.alpha(0.6));
                    for (k, l) in caption.iter().enumerate() {
                        let w = fonts.width(l, 11.0, Weight::Regular);
                        fonts.draw(&mut c, l, (WIDTH - w) / 2.0, y + 66.0 + 14.0 * k as f32, 11.0, Weight::Regular, t.faint);
                    }
                }
                Row::Footer => {
                    let ink = if hot { t.text } else { t.faint };
                    let mut small = Canvas::new(12.0, 12.0, scale);
                    small.transform = tiny_skia::Transform::from_scale(0.7, 0.7);
                    glyph::symbol(&mut small, Symbol::Question, 0.0, 0.0, ink, ink);
                    c.layer(&small, 14.0, y + 5.0, 1.0);
                    fonts.draw(&mut c, "Help / Suggest Improvement", 29.0, y + 5.0, 9.0, Weight::Regular, ink);
                    // ★★★★★ × PARADOX™ — small, bottom right; the stars are drawn, so they never depend on a font
                    let tm = fonts.width("™", 9.0, Weight::Regular);
                    let word = fonts.width("× PARADOX", 9.0, Weight::Regular);
                    let right = WIDTH - 14.0;
                    fonts.draw(&mut c, "™", right - tm, y + 5.0, 9.0, Weight::Regular, t.faint);
                    fonts.draw(&mut c, "× PARADOX", right - tm - word, y + 5.0, 9.0, Weight::Regular, t.faint);
                    for k in 0..5 { if let Some(p) = star5(right - tm - word - 7.0 - 8.4 * (4 - k) as f32, y + 11.3, 4.1) { c.fill(&p, t.faint) } }
                }
            }
        }
        c
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use focus_core::Launch;
    fn open(id: &str, mb: u64) -> OpenApp {
        OpenApp { app: AppRef { id: id.into(), name: id.into(), launch: Launch::Exe { path: id.into() } }, memory: mb << 20, protected: false }
    }
    #[test] fn rows_follow_the_mac_order_and_clicks_land_on_the_right_thing() {
        let Ok(fonts) = Fonts::system() else { return };                          // a machine with no known font: nothing to check
        let mut state = State::default();
        state.never_close = vec!["dictation".into()];
        state.create_mode("AI", vec![open("chat", 1).app]);
        let apps = [open("chat", 2000), open("notes", 300), open("dictation", 90)];
        let none = |_: &AppRef| None;
        let menu = Menu::build(&state, &Apps { open: &apps, icon: &none }, &fonts, "Ctrl+Shift+F", &|k| format!("Ctrl+{k}"));
        assert!(matches!(menu.rows.first(), Some(Row::Title)) && matches!(menu.rows.last(), Some(Row::Footer)));
        let headings: Vec<&str> = menu.rows.iter().filter_map(|r| if let Row::Heading(h) = r { Some(h.as_str()) } else { None }).collect();
        assert_eq!(headings, ["Keep open this session — click to choose", "Critical System Processes — never quit", "Modes — frequently used sessions"]);
        let tops = menu.tops();
        let at = |pred: &dyn Fn(&Row) -> bool| { let i = menu.rows.iter().position(|r| pred(r)).unwrap(); tops[i] + 10.0 };
        assert_eq!(menu.hit(300.0, 20.0).unwrap().1, Hit::Quit);
        assert!(menu.hit(40.0, 20.0).is_none());
        assert_eq!(menu.hit(100.0, at(&|r| matches!(r, Row::App(a) if a.id == "notes"))).unwrap().1, Hit::App("notes".into()));
        assert!(menu.hit(100.0, at(&|r| matches!(r, Row::App(a) if a.locked))).is_none());                 // lock rows are never clickable
        assert!(matches!(menu.hit(100.0, at(&|r| matches!(r, Row::Mode(_)))).unwrap().1, Hit::Mode(_)));
        assert_eq!(menu.hit(100.0, at(&|r| matches!(r, Row::Button { .. })) + 10.0).unwrap().1, Hit::Button);
        assert_eq!(menu.hit(60.0, at(&|r| matches!(r, Row::Footer))).unwrap().1, Hit::Help);
        let pic = menu.render(&fonts, 2.0, None, false);
        assert_eq!(pic.pixmap.width(), 640);
    }
}
