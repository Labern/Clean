//! `focus --selftest`: a real session on a real Windows desktop, with throwaway apps it opens itself.
//! It opens three programs, keeps one, starts a session (the other two must close, one at a time), ends it (they
//! must come back), and prints a plain pass/fail line for each step. It only ever closes the apps it opened.
use crate::apps::{self, Found};
use focus_core::{AppRef, Launch, OpenApp, QueueStep, QuitQueue, State};
use std::time::{Duration, Instant};

fn wait(what: &str, secs: u64, ok: impl Fn() -> bool) -> bool {
    let until = Instant::now() + Duration::from_secs(secs);
    while Instant::now() < until { if ok() { return true; } std::thread::sleep(Duration::from_millis(150)); }
    println!("       (timed out waiting for: {what})");
    false
}
fn find(list: &[Found], program: &str) -> Option<Found> {
    list.iter().find(|f| match &f.open.app.launch {
        Launch::Exe { path } => path.to_lowercase().ends_with(program),
        Launch::Store { aumid } => aumid.to_lowercase().contains(program.trim_end_matches(".exe")),
        _ => false,
    }).cloned()
}
fn is_open(id: &str) -> bool { apps::open_apps().iter().any(|f| f.open.app.id == id) }

pub fn run() -> i32 {
    let mut failed = 0;
    let mut check = |name: &str, pass: bool, detail: String| {
        println!("{}  {name}{}", if pass { "PASS" } else { "FAIL" }, if detail.is_empty() { String::new() } else { format!(" — {detail}") });
        if !pass { failed += 1; }
    };
    let sys = std::env::var("WINDIR").unwrap_or_else(|_| "C:\\Windows".into());
    let programs = ["notepad.exe", "charmap.exe", "winver.exe"];
    for p in programs { apps::launch(&Launch::Exe { path: format!("{sys}\\System32\\{p}") }); }
    let all_up = wait("the three test apps to open", 25, || { let l = apps::open_apps(); programs.iter().all(|p| find(&l, p).is_some()) });
    let before = apps::open_apps();
    println!("Open apps seen:");
    for f in &before { println!("   {:<6} {:>9}  {:<24} {}{}", if f.store { "store" } else { "exe" }, focus_core::memory_text(f.open.memory), f.open.app.name, f.open.app.id, if f.open.protected { " [system]" } else { "" }); }
    let mine: Vec<Found> = programs.iter().filter_map(|p| find(&before, p)).collect();
    check("finds the apps it opened, with a name and their memory", all_up && mine.len() == 3 && mine.iter().all(|f| !f.open.app.name.is_empty() && f.open.memory > 0),
          mine.iter().map(|f| format!("{} {}", f.open.app.name, focus_core::memory_text(f.open.memory))).collect::<Vec<_>>().join(", "));
    check("never lists Focus itself, and marks Windows' own shell as system", !before.iter().any(|f| f.open.app.id.ends_with("focus.exe")) && before.iter().filter(|f| f.open.app.id.ends_with("explorer.exe")).all(|f| f.open.protected), String::new());
    if mine.len() < 3 { return 1; }

    // a session that keeps the first app; only the test apps are in scope
    let scope: Vec<OpenApp> = mine.iter().map(|f| f.open.clone()).collect();
    let mut state = State::default();
    state.keep = vec![scope[0].app.id.clone()];
    let plan = state.start(&scope, None, 0).unwrap_or_default();
    check("a session plans to close everything not kept", plan.close.len() == 2 && !plan.close.iter().any(|a| a.id == scope[0].app.id), format!("closing {}", plan.close.iter().map(|a| a.name.clone()).collect::<Vec<_>>().join(", ")));
    let saved = state.save();

    let started = Instant::now();
    let mut queue = QuitQueue::new(plan.close.clone(), 8000, false);
    let mut one_at_a_time = true;
    let is_open_app = |a: &AppRef| is_open(&a.id);
    loop {
        match queue.step(started.elapsed().as_millis() as u64, &is_open_app) {
            QueueStep::Close(list) => {
                if list.len() != 1 { one_at_a_time = false; }
                let now = apps::open_apps();
                for a in &list { if let Some(f) = now.iter().find(|f| f.open.app.id == a.id) { apps::close(f); } }
            }
            QueueStep::Wait => std::thread::sleep(Duration::from_millis(100)),
            QueueStep::Done => break,
        }
        if started.elapsed() > Duration::from_secs(40) { break; }
    }
    let after = apps::open_apps();
    let gone = plan.close.iter().all(|a| !after.iter().any(|f| f.open.app.id == a.id));
    let kept = after.iter().any(|f| f.open.app.id == scope[0].app.id);
    check("the session closes them politely, one at a time, and the kept app stays", gone && kept && one_at_a_time && queue.waiting.is_empty(),
          format!("closed: {gone}; kept still open: {kept}; one at a time: {one_at_a_time}; took {:.1}s", started.elapsed().as_secs_f32()));

    // as after a crash: a fresh copy of Focus reads the saved state and ends the session
    let mut revived = State::load(&saved);
    check("the session survives a restart of Focus (saved state)", revived.focused && revived.live().map(|s| s.closed.len()) == Some(2), String::new());
    let back = revived.end();
    let launched = back.iter().all(|a| apps::launch(&a.launch));
    let returned = wait("the closed apps to come back", 25, || back.iter().all(|a| is_open(&a.id)));
    check("ending the session reopens what it closed", launched && returned, back.iter().map(|a| a.name.clone()).collect::<Vec<_>>().join(", "));
    let once = { let l = apps::open_apps(); mine.iter().all(|m| l.iter().filter(|f| f.open.app.id == m.open.app.id).count() == 1) };
    check("each app is open once (no duplicates)", once, String::new());

    // tidy up: close the test apps
    let l = apps::open_apps();
    for m in &mine { if let Some(f) = l.iter().find(|f| f.open.app.id == m.open.app.id) { apps::close(f); } }
    wait("the test apps to close", 15, || mine.iter().all(|m| !is_open(&m.open.app.id)));
    println!("{}", if failed == 0 { "All checks passed." } else { "Some checks FAILED." });
    failed
}
