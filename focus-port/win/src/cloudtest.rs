//! `focus --cloud-test DIR`: runs the real tray app on a real Windows desktop, drives it the way a person would
//! (open the menu, start a session, end it) and saves a screenshot at every step, so the result can be looked at
//! afterwards. It opens three throwaway apps and may only ever close those.
use crate::apps;
use crate::shell::{self, WM_TEST_HOVER, WM_TEST_MENU, WM_TEST_QUIT, WM_TEST_TOGGLE};
use focus_core::{Launch, State};
use std::time::{Duration, Instant};
use windows_sys::Win32::Foundation::HWND;
use windows_sys::Win32::UI::WindowsAndMessaging::PostMessageW;

fn sleep(ms: u64) { std::thread::sleep(Duration::from_millis(ms)); }
fn wait(secs: u64, ok: impl Fn() -> bool) -> bool {
    let until = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < until { if ok() { return true; } sleep(150); }
    false
}
fn id_of(program: &str) -> Option<String> {
    apps::open_apps().into_iter().find(|f| match &f.open.app.launch {
        Launch::Exe { path } => path.to_lowercase().ends_with(program),
        Launch::Store { aumid } => aumid.to_lowercase().contains(program.trim_end_matches(".exe")),
        _ => false,
    }).map(|f| f.open.app.id)
}
fn is_open(id: &str) -> bool { apps::open_apps().iter().any(|f| f.open.app.id == id) }

pub fn run(out: &str) -> i32 {
    let _ = std::fs::create_dir_all(out);
    let sys = std::env::var("WINDIR").unwrap_or_else(|_| "C:\\Windows".into());
    let programs = ["notepad.exe", "charmap.exe", "winver.exe"];
    for p in programs { apps::launch(&Launch::Exe { path: format!("{sys}\\System32\\{p}") }); }
    wait(25, || programs.iter().all(|p| id_of(p).is_some()));
    let ids: Vec<String> = programs.iter().filter_map(|p| id_of(p)).collect();
    if ids.len() < 3 { println!("FAIL  the three test apps did not open ({} of 3)", ids.len()); return 1; }

    // a fresh state: keep the first app, and one mode, so the menu has something in every section
    let mut state = State::default();
    state.keep = vec![ids[0].clone()];
    if let Some(f) = apps::open_apps().into_iter().find(|f| f.open.app.id == ids[0]) { state.create_mode("Writing", vec![f.open.app]); }
    let state_path = std::path::Path::new(out).join("state.json");
    let _ = std::fs::write(&state_path, state.save());

    let out_dir = out.to_string();
    let scope = ids.clone();
    shell::run(Some(scope), Some(state_path.clone()), move |main| {
        std::thread::spawn(move || {
            let post = |msg: u32, wp: usize| unsafe { PostMessageW(main as HWND, msg, wp, 0); };
            let shot = |name: &str| { shell::screenshot(&format!("{out_dir}/{name}.png")); };
            let mut report = vec![];
            let mut check = |name: &str, pass: bool| { let line = format!("{}  {name}", if pass { "PASS" } else { "FAIL" }); println!("{line}"); report.push(line); };
            sleep(1500); shot("1-desktop");
            post(WM_TEST_MENU, 1); sleep(900); shot("2-menu");
            post(WM_TEST_HOVER, 3); sleep(300); shot("3-menu-hover");
            post(WM_TEST_MENU, 0); sleep(300);
            post(WM_TEST_TOGGLE, 0);
            for i in 0..9 { sleep(120); shot(&format!("4-start-{i}")); }
            let closed = wait(30, || !is_open(&ids[1]) && !is_open(&ids[2]));
            sleep(500); shot("5-in-session");
            check("starting a session closes the two apps that weren't kept", closed);
            check("the kept app is still open", is_open(&ids[0]));
            post(WM_TEST_MENU, 1); sleep(900); shot("6-menu-in-session");
            post(WM_TEST_MENU, 0); sleep(300);
            post(WM_TEST_TOGGLE, 0);
            for i in 0..9 { sleep(120); shot(&format!("7-end-{i}")); }
            let back = wait(30, || is_open(&ids[1]) && is_open(&ids[2]));
            sleep(800); shot("8-after");
            check("ending the session brings both back", back);
            let _ = std::fs::write(format!("{out_dir}/report.txt"), report.join("\r\n"));
            let now = apps::open_apps();
            for id in &ids { if let Some(f) = now.iter().find(|f| &f.open.app.id == id) { apps::close(f); } }
            sleep(1500);
            post(WM_TEST_QUIT, 0);
        });
    })
}
