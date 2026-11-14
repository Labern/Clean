//! Draws the menu, the icon and the session animation to PNG files, with sample apps — for checking the pictures
//! on any machine without running the app.   cargo run -p focus-ui --example render -- OUT_DIR
use focus_core::{AppRef, Launch, OpenApp, State};
use focus_ui::draw::{Canvas, Rgba};
use focus_ui::menu::{Apps, Menu};
use focus_ui::{glyph, pill, Fonts, Image, Theme};

fn app(id: &str, name: &str, mb: u64) -> OpenApp {
    OpenApp { app: AppRef { id: id.into(), name: name.into(), launch: Launch::Exe { path: id.into() } }, memory: mb << 20, protected: false }
}
fn tile(seed: &str) -> Image {
    let mut c = Canvas::new(44.0, 44.0, 2.0);
    glyph::placeholder(&mut c, 0.0, 0.0, 44.0, seed, 1.0);
    let rgba = c.pixmap.pixels().iter().flat_map(|p| { let c = p.demultiply(); [c.red(), c.green(), c.blue(), c.alpha()] }).collect();
    Image { width: c.pixmap.width(), height: c.pixmap.height(), rgba }
}

fn main() {
    let out = std::env::args().nth(1).unwrap_or_else(|| "out".into());
    std::fs::create_dir_all(&out).unwrap();
    let fonts = Fonts::system().expect("an interface font");
    let apps = [app("browser", "Browser", 7500), app("chat", "Chat", 2600), app("editor", "Code Editor", 1900), app("notes", "Notes", 310),
                app("music", "Music", 240), app("dictation", "Dictation", 90)];
    let none = |_: &AppRef| None;
    let key = |k: u8| format!("Ctrl+{k}");

    let mut state = State::default();
    state.keep = vec!["chat".into(), "editor".into()];
    state.never_close = vec!["dictation".into()];
    state.create_mode("AI", vec![apps[1].app.clone(), apps[0].app.clone()]);
    state.create_mode("Programming", vec![apps[2].app.clone()]);
    for (name, light, style, session) in [("menu-dark", false, 1u8, false), ("menu-light", true, 1, false), ("menu-verbose", false, 2, false), ("menu-session", false, 1, true)] {
        let mut s = state.clone();
        s.settings.light = light; s.settings.heading_style = style;
        let open: Vec<OpenApp> = if session { s.start(&apps, None, 0); apps.iter().filter(|a| ["chat", "editor", "dictation"].contains(&a.app.id.as_str())).cloned().collect() } else { apps.to_vec() };
        let menu = Menu::build(&s, &Apps { open: &open, icon: &none }, &fonts, "Ctrl+Shift+F", &key);
        let hover = menu.rows.iter().position(|r| matches!(r, focus_ui::menu::Row::Mode(m) if m.name == "Programming"));
        menu.render(&fonts, 2.0, hover, false).save_png(&format!("{out}/{name}.png")).unwrap();
    }

    // the icon, out of session → in session, on a dark and a light taskbar
    let mut strip = Canvas::new(5.0 * 40.0, 80.0, 4.0);
    strip.rect(0.0, 0.0, 200.0, 40.0, 0.0, Rgba::hex(0x1C1C1E, 1.0));
    strip.rect(0.0, 40.0, 200.0, 40.0, 0.0, Rgba::hex(0xEDEDF0, 1.0));
    for (i, t) in [0.0f32, 0.25, 0.5, 0.75, 1.0].iter().enumerate() {
        strip.layer(&glyph::lens(18.0, 4.0, *t, Rgba::new(255, 255, 255, 1.0), Rgba::new(255, 255, 255, 1.0)), 11.0 + 40.0 * i as f32, 11.0, 1.0);
        strip.layer(&glyph::lens(18.0, 4.0, *t, Rgba::new(0, 0, 0, 1.0), Rgba::new(0, 0, 0, 1.0)), 11.0 + 40.0 * i as f32, 51.0, 1.0);
    }
    strip.save_png(&format!("{out}/icon.png")).unwrap();

    // the session animation as a filmstrip: start, then end
    let icons: Vec<Image> = ["browser", "notes", "music", "mail", "game"].iter().map(|s| tile(s)).collect();
    let theme = Theme::dark();
    for (name, start) in [("pill-start", true), ("pill-end", false)] {
        let show = pill::Show { start, icons: icons.clone(), label: "Focus".into(), hold: pill::hold(0), home: (300.0, 96.0), target: (560.0, 22.0) };
        let frames = 8;
        let (w, h) = (640.0f32, 260.0f32);
        let mut film = Canvas::new(w, h * frames as f32, 1.5);
        film.clear(Rgba::hex(0x6B6B6B, 1.0));
        for k in 0..frames {
            let now = show.length() * (k as f64 + 0.5) / frames as f64;
            film.origin = (0.0, h * k as f32);
            film.rect(0.0, h - 44.0, w, 44.0, 0.0, Rgba::hex(0x202022, 1.0));                       // a taskbar along the bottom
            film.layer(&glyph::lens(18.0, 1.5, if start { 0.0 } else { 1.0 }, theme.hud_ink, theme.hud_ink), 551.0, h - 31.0, 1.0);
            show.draw(&mut film, h, now, &theme, &fonts);
            fonts.draw(&mut film, &format!("{now:.2}s"), 8.0, 8.0, 11.0, focus_ui::text::Weight::Regular, Rgba::new(255, 255, 255, 0.9));
        }
        film.save_png(&format!("{out}/{name}.png")).unwrap();
    }
    println!("drawn to {out}/");
}
