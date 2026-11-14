//! The Windows app itself: an icon in the notification area, Ctrl+Shift+F, the menu, and the session animation.
//! All drawing comes from `focus-ui`; this file only puts those pictures on screen and turns clicks into actions.
use crate::apps::{self, wide, Found};
use focus_core::{AppRef, ModeAction, OpenApp, QueueStep, QuitQueue, State};
use focus_ui::menu::{Apps, Hit, Menu, WIDTH};
use focus_ui::{glyph, pill, Canvas, Fonts, Image, Rgba, Theme};
use std::cell::RefCell;
use std::collections::HashMap;
use std::ffi::c_void;
use std::time::Instant;
use windows_sys::Win32::Foundation::{HWND, LPARAM, LRESULT, POINT, RECT, SIZE, WPARAM};
use windows_sys::Win32::Graphics::Gdi::{
    BitBlt, CreateBitmap, CreateCompatibleDC, CreateDIBSection, DeleteDC, DeleteObject, GetDC, GetMonitorInfoW, MonitorFromPoint, ReleaseDC, SelectObject,
    AC_SRC_ALPHA, AC_SRC_OVER, BITMAPINFO, BITMAPINFOHEADER, BLENDFUNCTION, CAPTUREBLT, DIB_RGB_COLORS, MONITORINFO, MONITOR_DEFAULTTONEAREST, SRCCOPY,
};
use windows_sys::Win32::System::LibraryLoader::GetModuleHandleW;
use windows_sys::Win32::UI::HiDpi::{GetDpiForSystem, SetProcessDpiAwarenessContext, DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2};
use windows_sys::Win32::UI::Input::KeyboardAndMouse::{RegisterHotKey, TrackMouseEvent, UnregisterHotKey, MOD_CONTROL, MOD_NOREPEAT, MOD_SHIFT, TME_LEAVE, TRACKMOUSEEVENT};
use windows_sys::Win32::UI::Shell::{
    SHGetFileInfoW, ShellExecuteW, Shell_NotifyIconGetRect, Shell_NotifyIconW, NIF_ICON, NIF_MESSAGE, NIF_TIP, NIM_ADD, NIM_DELETE, NIM_MODIFY, NOTIFYICONDATAW,
    NOTIFYICONIDENTIFIER, SHFILEINFOW, SHGFI_ICON, SHGFI_LARGEICON,
};
use windows_sys::Win32::UI::WindowsAndMessaging::{
    CreateIconIndirect, CreateWindowExW, DefWindowProcW, DestroyIcon, DispatchMessageW, DrawIconEx, GetMessageW, GetSystemMetrics, KillTimer,
    PostMessageW, PostQuitMessage, RegisterClassW, SetForegroundWindow, SetTimer, SetWindowPos, ShowWindow, TranslateMessage, UpdateLayeredWindow, DI_NORMAL,
    HICON, HWND_TOPMOST, ICONINFO, MSG, SM_CXSCREEN, SM_CXSMICON, SM_CYSCREEN, SWP_NOACTIVATE, SWP_NOSIZE, SW_HIDE, SW_SHOWNOACTIVATE, SW_SHOWNORMAL, ULW_ALPHA,
    WA_INACTIVE, WM_ACTIVATE, WM_APP, WM_DESTROY, WM_HOTKEY, WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, WM_RBUTTONUP, WM_TIMER, WNDCLASSW, WS_EX_LAYERED,
    WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW, WS_EX_TOPMOST, WS_EX_TRANSPARENT, WS_POPUP,
};

const WM_TRAY: u32 = WM_APP + 1;
/// Messages the cloud test posts to drive the app like a person would.
pub const WM_TEST_MENU: u32 = WM_APP + 10;
pub const WM_TEST_TOGGLE: u32 = WM_APP + 11;
pub const WM_TEST_QUIT: u32 = WM_APP + 12;
pub const WM_TEST_HOVER: u32 = WM_APP + 13;
const WM_MOUSELEAVE: u32 = 0x02A3;
const HOTKEY_SESSION: i32 = 1;
const HOTKEY_MENU: i32 = 2;
const TIMER_QUEUE: usize = 1;
const TIMER_PILL: usize = 2;
pub const SESSION_KEY: &str = "Ctrl+Shift+F";

struct PillRun { show: pill::Show, began: Instant, area: RECT }

struct App {
    main: HWND,
    menu_window: HWND,
    pill_window: HWND,
    fonts: Fonts,
    scale: f32,
    state: State,
    state_path: std::path::PathBuf,
    open: Vec<Found>,
    icons: HashMap<String, Option<Image>>,
    menu: Option<Menu>,
    hover: Option<usize>,
    down: bool,
    queue: Option<(QuitQueue, Instant)>,
    pill: Option<PillRun>,
    tray_icon: HICON,
    /// Only these app ids may ever be closed (the cloud test's own apps). None = no limit.
    scope: Option<Vec<String>>,
}

thread_local! { static APP: RefCell<Option<App>> = const { RefCell::new(None) }; }
fn with<R>(f: impl FnOnce(&mut App) -> R) -> Option<R> { APP.with(|a| a.try_borrow_mut().ok().and_then(|mut g| g.as_mut().map(f))) }

fn state_file() -> std::path::PathBuf {
    let base = std::env::var("APPDATA").unwrap_or_else(|_| ".".into());
    std::path::Path::new(&base).join("Focus").join("state.json")
}
fn mode_key(k: u8) -> String { format!("Ctrl+{k}") }

// —— pictures onto the screen ——

/// Shows premultiplied pixels in a layered window at (x, y) screen pixels.
unsafe fn present(hwnd: HWND, canvas: &Canvas, x: i32, y: i32) {
    let (w, h) = (canvas.pixmap.width() as i32, canvas.pixmap.height() as i32);
    let screen = GetDC(std::ptr::null_mut());
    let mem = CreateCompatibleDC(screen);
    let mut info: BITMAPINFO = std::mem::zeroed();
    info.bmiHeader = BITMAPINFOHEADER { biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32, biWidth: w, biHeight: -h, biPlanes: 1, biBitCount: 32, ..std::mem::zeroed() };
    let mut bits: *mut c_void = std::ptr::null_mut();
    let bmp = CreateDIBSection(mem, &info, DIB_RGB_COLORS, &mut bits, std::ptr::null_mut(), 0);
    if !bmp.is_null() && !bits.is_null() {
        let data = canvas.bgra_premultiplied();
        std::ptr::copy_nonoverlapping(data.as_ptr(), bits as *mut u8, data.len());
        let old = SelectObject(mem, bmp);
        let (pos, size, src) = (POINT { x, y }, SIZE { cx: w, cy: h }, POINT { x: 0, y: 0 });
        let blend = BLENDFUNCTION { BlendOp: AC_SRC_OVER as u8, BlendFlags: 0, SourceConstantAlpha: 255, AlphaFormat: AC_SRC_ALPHA as u8 };
        UpdateLayeredWindow(hwnd, screen, &pos, &size, mem, &src, 0, &blend, ULW_ALPHA);
        SelectObject(mem, old);
        DeleteObject(bmp);
    }
    DeleteDC(mem);
    ReleaseDC(std::ptr::null_mut(), screen);
}

/// A drawn picture as a Windows icon (for the notification area).
unsafe fn icon_from(canvas: &Canvas) -> HICON {
    let (w, h) = (canvas.pixmap.width() as i32, canvas.pixmap.height() as i32);
    let mut bgra = Vec::with_capacity((w * h * 4) as usize);
    for p in canvas.pixmap.pixels() { let c = p.demultiply(); bgra.extend_from_slice(&[c.blue(), c.green(), c.red(), c.alpha()]); }
    let color = CreateBitmap(w, h, 1, 32, bgra.as_ptr() as *const c_void);
    let mask_bits = vec![0u8; ((w + 15) / 16 * 2 * h) as usize];
    let mask = CreateBitmap(w, h, 1, 1, mask_bits.as_ptr() as *const c_void);
    let info = ICONINFO { fIcon: 1, xHotspot: 0, yHotspot: 0, hbmMask: mask, hbmColor: color };
    let icon = CreateIconIndirect(&info);
    DeleteObject(color); DeleteObject(mask);
    icon
}

/// An app's own icon as a picture, from its program file.
unsafe fn icon_of(path: &str) -> Option<Image> {
    let mut info: SHFILEINFOW = std::mem::zeroed();
    if SHGetFileInfoW(wide(path).as_ptr(), 0, &mut info, std::mem::size_of::<SHFILEINFOW>() as u32, SHGFI_ICON | SHGFI_LARGEICON) == 0 || info.hIcon.is_null() { return None; }
    let side = 48i32;
    let screen = GetDC(std::ptr::null_mut());
    let mem = CreateCompatibleDC(screen);
    let mut bi: BITMAPINFO = std::mem::zeroed();
    bi.bmiHeader = BITMAPINFOHEADER { biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32, biWidth: side, biHeight: -side, biPlanes: 1, biBitCount: 32, ..std::mem::zeroed() };
    let mut bits: *mut c_void = std::ptr::null_mut();
    let bmp = CreateDIBSection(mem, &bi, DIB_RGB_COLORS, &mut bits, std::ptr::null_mut(), 0);
    let mut out = None;
    if !bmp.is_null() && !bits.is_null() {
        let old = SelectObject(mem, bmp);
        DrawIconEx(mem, 0, 0, info.hIcon, side, side, 0, std::ptr::null_mut(), DI_NORMAL);
        let px = std::slice::from_raw_parts(bits as *const u8, (side * side * 4) as usize);
        let any_alpha = px.chunks_exact(4).any(|p| p[3] != 0);
        let mut rgba = Vec::with_capacity(px.len());
        for p in px.chunks_exact(4) {
            let a = if any_alpha { p[3] } else if p[0] | p[1] | p[2] != 0 { 255 } else { 0 };
            let un = |v: u8| if a == 0 { 0 } else { ((v as u32 * 255) / a as u32).min(255) as u8 };
            rgba.extend_from_slice(&[un(p[2]), un(p[1]), un(p[0]), a]);
        }
        out = Some(Image { width: side as u32, height: side as u32, rgba });
        SelectObject(mem, old);
        DeleteObject(bmp);
    }
    DeleteDC(mem);
    ReleaseDC(std::ptr::null_mut(), screen);
    DestroyIcon(info.hIcon);
    out
}

/// The whole screen as a picture (the cloud test saves these so a person can see what happened).
pub fn screenshot(path: &str) -> bool {
    unsafe {
        let (w, h) = (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN));
        let screen = GetDC(std::ptr::null_mut());
        let mem = CreateCompatibleDC(screen);
        let mut bi: BITMAPINFO = std::mem::zeroed();
        bi.bmiHeader = BITMAPINFOHEADER { biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32, biWidth: w, biHeight: -h, biPlanes: 1, biBitCount: 32, ..std::mem::zeroed() };
        let mut bits: *mut c_void = std::ptr::null_mut();
        let bmp = CreateDIBSection(mem, &bi, DIB_RGB_COLORS, &mut bits, std::ptr::null_mut(), 0);
        let mut ok = false;
        if !bmp.is_null() && !bits.is_null() {
            let old = SelectObject(mem, bmp);
            BitBlt(mem, 0, 0, w, h, screen, 0, 0, SRCCOPY | CAPTUREBLT);
            let px = std::slice::from_raw_parts(bits as *const u8, (w * h * 4) as usize);
            let rgba: Vec<u8> = px.chunks_exact(4).flat_map(|p| [p[2], p[1], p[0], 255]).collect();
            let mut c = Canvas::new(w as f32, h as f32, 1.0);
            c.image(&Image { width: w as u32, height: h as u32, rgba }, 0.0, 0.0, w as f32, h as f32, 1.0);
            ok = c.save_png(path).is_ok();
            SelectObject(mem, old);
            DeleteObject(bmp);
        }
        DeleteDC(mem);
        ReleaseDC(std::ptr::null_mut(), screen);
        ok
    }
}

// —— the app ——

impl App {
    fn save(&self) {
        if let Some(dir) = self.state_path.parent() { let _ = std::fs::create_dir_all(dir); }
        let _ = std::fs::write(&self.state_path, self.state.save());
    }
    fn refresh(&mut self) {
        self.open = apps::open_apps();
        for f in &self.open {
            if !self.icons.contains_key(&f.open.app.id) {
                let img = match &f.open.app.launch { focus_core::Launch::Exe { path } => unsafe { icon_of(path) }, _ => None };
                self.icons.insert(f.open.app.id.clone(), img);
            }
        }
    }
    fn open_apps(&self) -> Vec<OpenApp> {
        self.open.iter().map(|f| {
            let mut o = f.open.clone();
            // outside the test's scope, everything is treated as part of the system: never closed
            if let Some(scope) = &self.scope { if !scope.contains(&o.app.id) { o.protected = true; } }
            o
        }).collect()
    }
    fn tray_rect(&self) -> RECT {
        let id = NOTIFYICONIDENTIFIER { cbSize: std::mem::size_of::<NOTIFYICONIDENTIFIER>() as u32, hWnd: self.main, uID: 1, guidItem: unsafe { std::mem::zeroed() } };
        let mut r: RECT = unsafe { std::mem::zeroed() };
        if unsafe { Shell_NotifyIconGetRect(&id, &mut r) } != 0 || r.right <= r.left {
            let (w, h) = unsafe { (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)) };
            r = RECT { left: w - 140, top: h - 40, right: w - 116, bottom: h - 16 };
        }
        r
    }
    fn set_tray(&mut self, add: bool) {
        unsafe {
            let size = GetSystemMetrics(SM_CXSMICON).max(16);
            let ink = Rgba::new(255, 255, 255, 1.0);
            let pic = glyph::lens(18.0, size as f32 / 18.0, if self.state.focused { 1.0 } else { 0.0 }, ink, ink);
            let icon = icon_from(&pic);
            let mut d: NOTIFYICONDATAW = std::mem::zeroed();
            d.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32;
            d.hWnd = self.main; d.uID = 1; d.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP; d.uCallbackMessage = WM_TRAY; d.hIcon = icon;
            let tip = match self.state.display_name() { Some(n) => format!("Focus | {n}"), None => "Focus".to_string() };
            for (i, ch) in tip.encode_utf16().take(127).enumerate() { d.szTip[i] = ch; }
            Shell_NotifyIconW(if add { NIM_ADD } else { NIM_MODIFY }, &d);
            if !self.tray_icon.is_null() { DestroyIcon(self.tray_icon); }
            self.tray_icon = icon;
        }
    }
    fn hotkeys(&self) {
        unsafe {
            RegisterHotKey(self.main, HOTKEY_SESSION, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'F' as u32);
            RegisterHotKey(self.main, HOTKEY_MENU, MOD_CONTROL | MOD_SHIFT | MOD_NOREPEAT, 'E' as u32);
            for k in 0..10u8 {
                UnregisterHotKey(self.main, 100 + k as i32);
                if self.state.mode_for_key(k).is_some() { RegisterHotKey(self.main, 100 + k as i32, MOD_CONTROL | MOD_NOREPEAT, ('0' as u32) + k as u32); }
            }
        }
    }

    // —— the menu ——
    fn build_menu(&mut self) {
        let open = self.open_apps();
        let icons = &self.icons;
        let icon = |a: &AppRef| icons.get(&a.id).cloned().flatten();
        self.menu = Some(Menu::build(&self.state, &Apps { open: &open, icon: &icon }, &self.fonts, SESSION_KEY, &mode_key));
    }
    fn menu_origin(&self) -> (i32, i32) {
        let h = self.menu.as_ref().map(|m| m.height()).unwrap_or(400.0);
        let (w, h) = ((WIDTH * self.scale).ceil() as i32, (h * self.scale).ceil() as i32);
        let tray = self.tray_rect();
        let anchor = POINT { x: (tray.left + tray.right) / 2, y: tray.top };
        let mut mi: MONITORINFO = unsafe { std::mem::zeroed() };
        mi.cbSize = std::mem::size_of::<MONITORINFO>() as u32;
        unsafe { GetMonitorInfoW(MonitorFromPoint(anchor, MONITOR_DEFAULTTONEAREST), &mut mi) };
        let work = mi.rcWork;
        let x = (anchor.x - w / 2).clamp(work.left + 8, (work.right - w - 8).max(work.left + 8));
        let y = (work.bottom - h - 8).max(work.top + 8);
        (x, y)
    }
    fn paint_menu(&mut self) {
        let Some(menu) = &self.menu else { return };
        let pic = menu.render(&self.fonts, self.scale, self.hover, self.down);
        let (x, y) = self.menu_origin();
        unsafe { present(self.menu_window, &pic, x, y) };
    }
    fn show_menu(&mut self) {
        self.refresh();
        self.hover = None; self.down = false;
        self.build_menu();
        self.paint_menu();
        unsafe { ShowWindow(self.menu_window, SW_SHOWNORMAL); SetForegroundWindow(self.menu_window); }
    }
    fn hide_menu(&mut self) { unsafe { ShowWindow(self.menu_window, SW_HIDE) }; self.menu = None; }
    fn menu_visible(&self) -> bool { self.menu.is_some() }

    fn click(&mut self, hit: Hit) {
        match hit {
            Hit::Quit => { self.hide_menu(); unsafe { PostMessageW(self.main, WM_TEST_QUIT, 0, 0) }; }
            Hit::Button => { self.hide_menu(); self.toggle(None); }
            Hit::App(id) => {
                if self.state.focused {
                    if let Some(f) = self.open.iter().find(|f| f.open.app.id == id).cloned() {
                        if self.state.take_out(&f.open.app) { self.play(true, vec![f.open.app.clone()]); apps::close(&f); }
                    }
                } else { self.state.toggle_keep(&id); }
                self.save(); self.build_menu(); self.paint_menu();
            }
            Hit::Closed(id) => {
                if let Some(app) = self.state.bring_back(&id) { self.play(false, vec![app.clone()]); apps::launch(&app.launch); }
                self.save(); self.build_menu(); self.paint_menu();
            }
            Hit::Mode(id) => { self.hide_menu(); self.mode(&id); }
            Hit::Help => { self.hide_menu(); unsafe { ShellExecuteW(std::ptr::null_mut(), wide("open").as_ptr(), wide("mailto:help@paradoxica.co.uk?subject=Focus%3A%20").as_ptr(), std::ptr::null(), std::ptr::null(), SW_SHOWNORMAL) }; }
            // The submenus (Create New Mode, Edit Modes, Suggested Modes, Past sessions, Tools, Settings), sorting by
            // Usage and Add or remove are the next milestone: the rows are drawn, the windows behind them are not built yet.
            _ => {}
        }
    }

    // —— sessions ——
    fn play(&mut self, start: bool, apps_shown: Vec<AppRef>) {
        let icons: Vec<Image> = apps_shown.iter().map(|a| self.icons.get(&a.id).cloned().flatten().unwrap_or_else(|| {
            let mut c = Canvas::new(44.0, 44.0, 2.0); glyph::placeholder(&mut c, 0.0, 0.0, 44.0, &a.id, 1.0);
            Image { width: c.pixmap.width(), height: c.pixmap.height(), rgba: c.pixmap.pixels().iter().flat_map(|p| { let d = p.demultiply(); [d.red(), d.green(), d.blue(), d.alpha()] }).collect() }
        })).collect();
        if icons.is_empty() { return; }
        let tray = self.tray_rect();
        let (sw, sh) = unsafe { (GetSystemMetrics(SM_CXSCREEN), GetSystemMetrics(SM_CYSCREEN)) };
        let s = self.scale;
        // the area the show can touch: the bottom 300 points of the screen, full width
        let area = RECT { left: 0, top: sh - (300.0 * s) as i32, right: sw, bottom: sh };
        let to_pt = |x: i32, y: i32| ((x - area.left) as f32 / s, (area.bottom - y) as f32 / s);       // y-up, as the animation is written
        let home = to_pt(sw / 2, sh - (96.0 * s) as i32);
        let target = to_pt((tray.left + tray.right) / 2, (tray.top + tray.bottom) / 2);
        let label = self.state.display_name().unwrap_or_else(|| "Focus".into());
        let show = pill::Show { start, icons, label, hold: pill::hold(self.state.settings.anim_speed), home, target };
        self.pill = Some(PillRun { show, began: Instant::now(), area });
        unsafe {
            SetWindowPos(self.pill_window, HWND_TOPMOST, area.left, area.top, 0, 0, SWP_NOSIZE | SWP_NOACTIVATE);
            ShowWindow(self.pill_window, SW_SHOWNOACTIVATE);
            SetTimer(self.main, TIMER_PILL, 8, None);
        }
        self.pill_frame();
    }
    fn pill_frame(&mut self) {
        let Some(run) = &self.pill else { return };
        let now = run.began.elapsed().as_secs_f64();
        if now > run.show.length() {
            unsafe { KillTimer(self.main, TIMER_PILL); ShowWindow(self.pill_window, SW_HIDE); }
            self.pill = None;
            return;
        }
        let (w, h) = ((run.area.right - run.area.left) as f32 / self.scale, (run.area.bottom - run.area.top) as f32 / self.scale);
        let mut c = Canvas::new(w, h, self.scale);
        run.show.draw(&mut c, h, now, &Theme::dark(), &self.fonts);
        unsafe { present(self.pill_window, &c, run.area.left, run.area.top) };
    }

    /// Start or end a session — the tray button and Ctrl+Shift+F.
    fn toggle(&mut self, mode_id: Option<&str>) {
        self.refresh();
        if self.state.focused {
            if let Some((q, _)) = &mut self.queue { q.cancel(); }
            self.queue = None;
            unsafe { KillTimer(self.main, TIMER_QUEUE) };
            let back = self.state.end();
            let missing: Vec<AppRef> = back.into_iter().filter(|a| !self.open.iter().any(|f| f.open.app.id == a.id)).collect();    // never a second copy
            self.play(false, missing.clone());
            for a in &missing { apps::launch(&a.launch); }
        } else {
            let open = self.open_apps();
            let Some(plan) = self.state.start(&open, mode_id, now_secs()) else { return };
            for a in &plan.open { apps::launch(&a.launch); }
            self.play(true, plan.close.clone());
            self.queue = Some((QuitQueue::new(plan.close, 8000, self.state.settings.speed_first), Instant::now()));
            unsafe { SetTimer(self.main, TIMER_QUEUE, 120, None) };
        }
        self.save();
        self.set_tray(false);
    }
    fn mode(&mut self, id: &str) {
        match self.state.mode_action(id) {
            ModeAction::Start => self.toggle(Some(id)),
            ModeAction::End => self.toggle(None),
            ModeAction::Switch => {
                self.refresh();
                let open = self.open_apps();
                if let Some(plan) = self.state.switch_mode(&open, id) {
                    for a in &plan.open { apps::launch(&a.launch); }
                    self.play(true, plan.close.clone());                    // the standard animation, for the apps that leave
                    self.queue = Some((QuitQueue::new(plan.close, 8000, self.state.settings.speed_first), Instant::now()));
                    unsafe { SetTimer(self.main, TIMER_QUEUE, 120, None) };
                    self.save(); self.set_tray(false);
                }
            }
        }
    }
    fn queue_tick(&mut self) {
        let Some((queue, began)) = &mut self.queue else { unsafe { KillTimer(self.main, TIMER_QUEUE) }; return };
        let now_open = apps::open_apps();
        let is_open = |a: &AppRef| now_open.iter().any(|f| f.open.app.id == a.id);
        match queue.step(began.elapsed().as_millis() as u64, &is_open) {
            QueueStep::Close(list) => for a in &list { if let Some(f) = now_open.iter().find(|f| f.open.app.id == a.id) { apps::close(f); } },
            QueueStep::Wait => {}
            QueueStep::Done => { self.queue = None; unsafe { KillTimer(self.main, TIMER_QUEUE) }; }
        }
    }
}

fn now_secs() -> u64 { std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0) }

unsafe extern "system" fn main_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    match msg {
        WM_TRAY => {
            let event = (lp as u32) & 0xFFFF;
            if event == WM_LBUTTONUP || event == WM_RBUTTONUP { with(|a| if a.menu_visible() { a.hide_menu() } else { a.show_menu() }); }
            0
        }
        WM_HOTKEY => {
            match wp as i32 {
                HOTKEY_SESSION => { with(|a| { a.hide_menu(); a.toggle(None) }); }
                HOTKEY_MENU => { with(|a| if a.menu_visible() { a.hide_menu() } else { a.show_menu() }); }
                k @ 100..=109 => { with(|a| { if let Some(id) = a.state.mode_for_key((k - 100) as u8).map(|m| m.id.clone()) { a.hide_menu(); a.mode(&id); } }); }
                _ => {}
            }
            0
        }
        WM_TIMER => { match wp { TIMER_QUEUE => { with(|a| a.queue_tick()); } TIMER_PILL => { with(|a| a.pill_frame()); } _ => {} } 0 }
        WM_TEST_MENU => { with(|a| if wp == 0 { a.hide_menu() } else { a.show_menu() }); 0 }
        WM_TEST_TOGGLE => { with(|a| { a.hide_menu(); a.toggle(None) }); 0 }
        WM_TEST_HOVER => { with(|a| { a.hover = Some(wp); a.paint_menu() }); 0 }
        WM_TEST_QUIT | WM_DESTROY => {
            with(|a| {
                let mut d: NOTIFYICONDATAW = std::mem::zeroed();
                d.cbSize = std::mem::size_of::<NOTIFYICONDATAW>() as u32; d.hWnd = a.main; d.uID = 1;
                Shell_NotifyIconW(NIM_DELETE, &d);
            });
            PostQuitMessage(0);
            0
        }
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

unsafe extern "system" fn menu_proc(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    let point = |a: &App| (((lp & 0xFFFF) as i16) as f32 / a.scale, (((lp >> 16) & 0xFFFF) as i16) as f32 / a.scale);
    match msg {
        WM_MOUSEMOVE => {
            with(|a| {
                let (x, y) = point(a);
                let hover = a.menu.as_ref().and_then(|m| m.hit(x, y)).map(|h| h.0);
                if hover != a.hover { a.hover = hover; a.paint_menu(); }
                let mut t = TRACKMOUSEEVENT { cbSize: std::mem::size_of::<TRACKMOUSEEVENT>() as u32, dwFlags: TME_LEAVE, hwndTrack: hwnd, dwHoverTime: 0 };
                TrackMouseEvent(&mut t);
            });
            0
        }
        WM_MOUSELEAVE => { with(|a| { if a.hover.is_some() { a.hover = None; a.down = false; a.paint_menu(); } }); 0 }
        WM_LBUTTONDOWN => { with(|a| { let (x, y) = point(a); if matches!(a.menu.as_ref().and_then(|m| m.hit(x, y)), Some((_, Hit::Button))) { a.down = true; a.paint_menu(); } }); 0 }
        WM_LBUTTONUP => {
            with(|a| {
                let (x, y) = point(a);
                a.down = false;
                if let Some((_, hit)) = a.menu.as_ref().and_then(|m| m.hit(x, y)) { a.click(hit); }
            });
            0
        }
        WM_ACTIVATE => { if (wp & 0xFFFF) as u32 == WA_INACTIVE { with(|a| a.hide_menu()); } 0 }      // a click anywhere else closes it
        _ => DefWindowProcW(hwnd, msg, wp, lp),
    }
}

/// Runs Focus. `scope`: the only apps it may close (the cloud test); `on_ready` gets the main window to post to.
pub fn run(scope: Option<Vec<String>>, state_path: Option<std::path::PathBuf>, on_ready: impl FnOnce(isize)) -> i32 {
    unsafe {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        let fonts = match Fonts::system() { Ok(f) => f, Err(e) => { eprintln!("Focus: {e}"); return 1; } };
        let inst = GetModuleHandleW(std::ptr::null());
        let class = |name: &str, proc: unsafe extern "system" fn(HWND, u32, WPARAM, LPARAM) -> LRESULT| {
            let n = wide(name);
            let wc = WNDCLASSW { lpfnWndProc: Some(proc), hInstance: inst, lpszClassName: n.as_ptr(), ..std::mem::zeroed() };
            RegisterClassW(&wc);
            n
        };
        let (c_main, c_menu, c_pill) = (class("FocusMain", main_proc), class("FocusMenu", menu_proc), class("FocusShow", main_proc_passthrough));
        let main = CreateWindowExW(0, c_main.as_ptr(), wide("Focus").as_ptr(), WS_POPUP, 0, 0, 0, 0, std::ptr::null_mut(), std::ptr::null_mut(), inst, std::ptr::null());
        let menu_window = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST, c_menu.as_ptr(), wide("Focus menu").as_ptr(), WS_POPUP, 0, 0, 10, 10,
                                          std::ptr::null_mut(), std::ptr::null_mut(), inst, std::ptr::null());
        let pill_window = CreateWindowExW(WS_EX_LAYERED | WS_EX_TOOLWINDOW | WS_EX_TOPMOST | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE, c_pill.as_ptr(), wide("Focus session").as_ptr(),
                                          WS_POPUP, 0, 0, 10, 10, std::ptr::null_mut(), std::ptr::null_mut(), inst, std::ptr::null());
        if main.is_null() || menu_window.is_null() || pill_window.is_null() { eprintln!("Focus: could not create its windows"); return 1; }
        let state_path = state_path.unwrap_or_else(state_file);
        let state = std::fs::read_to_string(&state_path).map(|s| State::load(&s)).unwrap_or_default();
        let mut app = App { main, menu_window, pill_window, fonts, scale: GetDpiForSystem() as f32 / 96.0, state, state_path, open: vec![], icons: HashMap::new(),
                            menu: None, hover: None, down: false, queue: None, pill: None, tray_icon: std::ptr::null_mut(), scope };
        app.set_tray(true);
        app.hotkeys();
        APP.with(|a| *a.borrow_mut() = Some(app));
        on_ready(main as isize);
        let mut msg: MSG = std::mem::zeroed();
        while GetMessageW(&mut msg, std::ptr::null_mut(), 0, 0) > 0 { TranslateMessage(&msg); DispatchMessageW(&msg); }
        0
    }
}
unsafe extern "system" fn main_proc_passthrough(hwnd: HWND, msg: u32, wp: WPARAM, lp: LPARAM) -> LRESULT { DefWindowProcW(hwnd, msg, wp, lp) }
