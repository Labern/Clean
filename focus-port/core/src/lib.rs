//! Focus — the shared core. Everything a session is, with no system calls: what is kept, what is closed, the
//! careful quit queue, modes, saved state. Each platform supplies "which apps are open / close this / reopen that"
//! and the drawing; the behaviour lives here so every platform is held to the same rules as the Mac app (0.18.25).
use serde::{Deserialize, Serialize};
use std::collections::HashSet;

/// How an app is started again after a session.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "kind", rename_all = "lowercase")]
pub enum Launch {
    /// An ordinary program: the path of its .exe (Windows) or binary.
    Exe { path: String },
    /// A Microsoft Store (packaged) app: its Application User Model ID.
    Store { aumid: String },
    /// A Linux desktop entry (.desktop file id).
    Desktop { entry: String },
}

/// One app, as the user thinks of it. `id` is stable across launches (never a process id).
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct AppRef {
    pub id: String,
    pub name: String,
    pub launch: Launch,
}

/// An app that is open right now.
#[derive(Clone, Debug)]
pub struct OpenApp {
    pub app: AppRef,
    /// Bytes of memory it is using (all its processes).
    pub memory: u64,
    /// Part of the system itself, or Focus: never listed, never closed.
    pub protected: bool,
}

#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Session {
    /// Unix seconds.
    pub started: u64,
    /// Ids of the apps it kept open — what defines the session.
    pub kept: Vec<String>,
    /// The apps it closed, to bring back when it ends.
    pub closed: Vec<AppRef>,
    pub name: Option<String>,
    pub mode_id: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
pub struct Mode {
    pub id: String,
    pub name: String,
    pub apps: Vec<AppRef>,
    /// Its number, 0–9: pressed with the mode modifier it starts the mode.
    pub key: Option<u8>,
}

#[derive(Clone, Debug, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct Settings {
    /// Close everything at once instead of one app at a time.
    pub speed_first: bool,
    /// Light menu instead of the standard dark one.
    pub light: bool,
    /// 0 Minimalist, 1 Normal, 2 Verbose.
    pub heading_style: u8,
    /// -1 slow, 0 normal, 1 fast. Normal is the original timing and the standard.
    pub anim_speed: i8,
}
impl Default for Settings {
    fn default() -> Self { Settings { speed_first: false, light: false, heading_style: 1, anim_speed: 0 } }
}

/// Everything Focus remembers. Saved as JSON after every change, so a crash or restart loses nothing.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
#[serde(default)]
pub struct State {
    pub focused: bool,
    /// Newest first; the last 12 are kept.
    pub sessions: Vec<Session>,
    pub modes: Vec<Mode>,
    /// The user's ticks: ids of apps to keep open in a session started with the shortcut.
    pub keep: Vec<String>,
    /// Critical System Processes: never closed, in any session.
    pub never_close: Vec<String>,
    pub settings: Settings,
    next_id: u64,
}

pub const HISTORY: usize = 12;
pub const MODE_KEYS: [u8; 10] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0];

/// What starting a session will do.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct StartPlan {
    /// To close, biggest first (the most memory comes back soonest).
    pub close: Vec<AppRef>,
    /// A mode's apps that aren't running yet, to open.
    pub open: Vec<AppRef>,
}

impl State {
    pub fn load(json: &str) -> State { serde_json::from_str(json).unwrap_or_default() }
    pub fn save(&self) -> String { serde_json::to_string_pretty(self).unwrap_or_else(|_| "{}".into()) }

    /// The apps the menu lists: everything open that isn't part of the system.
    pub fn listed<'a>(&self, open: &'a [OpenApp]) -> Vec<&'a OpenApp> { open.iter().filter(|a| !a.protected).collect() }

    fn keep_set(&self, mode: Option<&Mode>) -> HashSet<String> {
        match mode {
            Some(m) => m.apps.iter().map(|a| a.id.clone()).collect(),
            None => self.keep.iter().cloned().collect(),
        }
    }

    /// What a session would close and open, without starting it (the button's caption uses this).
    pub fn plan(&self, open: &[OpenApp], mode: Option<&Mode>) -> StartPlan {
        let keep = self.keep_set(mode);
        let never: HashSet<&String> = self.never_close.iter().collect();
        let mut leaving: Vec<&OpenApp> = open.iter()
            .filter(|a| !a.protected && !keep.contains(&a.app.id) && !never.contains(&a.app.id)).collect();
        leaving.sort_by(|a, b| b.memory.cmp(&a.memory));
        let running: HashSet<&String> = open.iter().map(|a| &a.app.id).collect();
        let to_open = mode.map(|m| m.apps.iter().filter(|a| !running.contains(&a.id)).cloned().collect()).unwrap_or_default();
        StartPlan { close: leaving.into_iter().map(|a| a.app.clone()).collect(), open: to_open }
    }

    /// Starts a session. Starts nothing (and returns None) when every open app is kept and no mode asks for apps
    /// to open — the same as the Mac app.
    pub fn start(&mut self, open: &[OpenApp], mode_id: Option<&str>, now: u64) -> Option<StartPlan> {
        if self.focused { return None; }
        let mode = mode_id.and_then(|id| self.modes.iter().find(|m| m.id == id)).cloned();
        if mode_id.is_some() && mode.is_none() { return None; }
        let plan = self.plan(open, mode.as_ref());
        if plan.close.is_empty() && plan.open.is_empty() { return None; }
        let closing: HashSet<&String> = plan.close.iter().map(|a| &a.id).collect();
        let kept = match &mode {
            Some(m) => m.apps.iter().map(|a| a.id.clone()).collect(),
            None => open.iter().filter(|a| !a.protected && !closing.contains(&a.app.id)).map(|a| a.app.id.clone()).collect(),
        };
        self.sessions.insert(0, Session { started: now, kept, closed: plan.close.clone(),
                                          name: mode.as_ref().map(|m| m.name.clone()), mode_id: mode.map(|m| m.id) });
        self.sessions.truncate(HISTORY);
        self.focused = true;
        Some(plan)
    }

    /// Ends the session. Returns the apps to bring back.
    pub fn end(&mut self) -> Vec<AppRef> {
        if !self.focused { return vec![]; }
        self.focused = false;
        self.sessions.first().map(|s| s.closed.clone()).unwrap_or_default()
    }

    pub fn live(&self) -> Option<&Session> { if self.focused { self.sessions.first() } else { None } }

    /// Takes one open app out of the running session: it is closed now and comes back at the end.
    pub fn take_out(&mut self, app: &AppRef) -> bool {
        if !self.focused || self.never_close.contains(&app.id) { return false; }
        let Some(s) = self.sessions.first_mut() else { return false };
        if s.closed.iter().any(|a| a.id == app.id) { return false; }
        s.kept.retain(|id| id != &app.id);
        s.closed.push(app.clone());
        true
    }

    /// Brings one closed app back into the running session now. Returns it, to reopen.
    pub fn bring_back(&mut self, id: &str) -> Option<AppRef> {
        if !self.focused { return None; }
        let s = self.sessions.first_mut()?;
        let i = s.closed.iter().position(|a| a.id == id)?;
        let app = s.closed.remove(i);
        if !s.kept.contains(&app.id) { s.kept.push(app.id.clone()); }
        Some(app)
    }

    /// Moves the running session to a mode: returns what to close and what to bring back or open. One session
    /// throughout, so ending it restores everything that was open before the first mode started. The user's own
    /// ticks (`keep`) are never rewritten by a mode.
    pub fn switch_mode(&mut self, open: &[OpenApp], mode_id: &str) -> Option<StartPlan> {
        if !self.focused { return None; }
        let mode = self.modes.iter().find(|m| m.id == mode_id)?.clone();
        let want: HashSet<&String> = mode.apps.iter().map(|a| &a.id).collect();
        let never: HashSet<String> = self.never_close.iter().cloned().collect();
        let s = self.sessions.first_mut()?;
        let was_closed: HashSet<String> = s.closed.iter().map(|a| a.id.clone()).collect();
        let running: HashSet<&String> = open.iter().map(|a| &a.app.id).collect();
        // back from the closed list, or opened fresh
        let arriving: Vec<AppRef> = mode.apps.iter().filter(|a| was_closed.contains(&a.id) || !running.contains(&a.id)).cloned().collect();
        s.closed.retain(|a| !want.contains(&a.id));
        let mut leaving: Vec<&OpenApp> = open.iter()
            .filter(|a| !a.protected && !want.contains(&a.app.id) && !never.contains(&a.app.id) && !was_closed.contains(&a.app.id)).collect();
        leaving.sort_by(|a, b| b.memory.cmp(&a.memory));
        for a in &leaving { s.closed.push(a.app.clone()); }
        s.kept = mode.apps.iter().map(|a| a.id.clone()).collect();
        s.name = Some(mode.name.clone());
        s.mode_id = Some(mode.id.clone());
        Some(StartPlan { close: leaving.into_iter().map(|a| a.app.clone()).collect(), open: arriving })
    }

    /// A mode's key, or the menu click: start it; if it is the live one, end the session; else switch to it.
    pub fn mode_action(&self, mode_id: &str) -> ModeAction {
        if !self.focused { ModeAction::Start }
        else if self.live().and_then(|s| s.mode_id.as_deref()) == Some(mode_id) { ModeAction::End }
        else { ModeAction::Switch }
    }

    // —— modes ——
    pub fn next_mode_key(&self) -> Option<u8> {
        let used: HashSet<u8> = self.modes.iter().filter_map(|m| m.key).collect();
        MODE_KEYS.iter().copied().find(|k| !used.contains(k))
    }
    /// A new mode takes the next free number and, unnamed, is called by it ("Mode 3"). A mode needs an app.
    pub fn create_mode(&mut self, name: &str, apps: Vec<AppRef>) -> Option<String> {
        let mut seen = HashSet::new();
        let apps: Vec<AppRef> = apps.into_iter().filter(|a| seen.insert(a.id.clone())).collect();
        if apps.is_empty() { return None; }
        let key = self.next_mode_key();
        let name = name.trim();
        let name = if name.is_empty() { format!("Mode {}", key.map(|k| k.to_string()).unwrap_or_else(|| (self.modes.len() + 1).to_string())) } else { name.to_string() };
        self.next_id += 1;
        let id = format!("m{}", self.next_id);
        self.modes.push(Mode { id: id.clone(), name, apps, key });
        Some(id)
    }
    /// A number belongs to one mode: giving it to one takes it from any other.
    pub fn set_mode_key(&mut self, mode_id: &str, key: Option<u8>) {
        for m in self.modes.iter_mut() {
            if m.id == mode_id { m.key = key } else if key.is_some() && m.key == key { m.key = None }
        }
    }
    pub fn mode_for_key(&self, key: u8) -> Option<&Mode> { self.modes.iter().find(|m| m.key == Some(key)) }
    pub fn rename_mode(&mut self, mode_id: &str, name: &str) {
        let name = name.trim();
        if name.is_empty() { return; }
        if let Some(m) = self.modes.iter_mut().find(|m| m.id == mode_id) { m.name = name.to_string(); }
    }
    pub fn delete_mode(&mut self, mode_id: &str) { self.modes.retain(|m| m.id != mode_id); }

    /// What the tray shows beside the icon during a session: the session's name, else the mode whose apps it
    /// mostly kept (at least half of them), else "Focus".
    pub fn display_name(&self) -> Option<String> {
        let live = self.live()?;
        if let Some(n) = live.name.as_ref().filter(|n| !n.is_empty()) { return Some(n.clone()); }
        let kept: HashSet<&String> = live.kept.iter().collect();
        let mut best: Option<(f64, &String)> = None;
        for m in self.modes.iter().filter(|m| !m.apps.is_empty()) {
            let hit = m.apps.iter().filter(|a| kept.contains(&a.id)).count() as f64 / m.apps.len() as f64;
            if best.map_or(true, |b| hit > b.0) { best = Some((hit, &m.name)); }
        }
        Some(match best { Some((hit, name)) if hit >= 0.5 => name.clone(), _ => "Focus".to_string() })
    }

    pub fn toggle_keep(&mut self, id: &str) -> bool {
        if let Some(i) = self.keep.iter().position(|k| k == id) { self.keep.remove(i); false } else { self.keep.push(id.to_string()); true }
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ModeAction { Start, End, Switch }

/// "2.4 GB" / "310 MB", as the Mac menu writes memory.
pub fn memory_text(bytes: u64) -> String {
    let mb = bytes as f64 / 1_048_576.0;
    if mb >= 1000.0 { format!("{:.1} GB", mb / 1024.0) } else { format!("{:.0} MB", mb) }
}
pub fn apps_text(n: usize) -> String { if n == 1 { "1 app".into() } else { format!("{n} apps") } }

/// The line under the big button: plain words for what a click will do.
pub fn caption(state: &State, open: &[OpenApp]) -> String {
    if let Some(live) = state.live() {
        return format!("Ending the session will reopen {} exactly as they were.", apps_text(live.closed.len()));
    }
    let plan = state.plan(open, None);
    if plan.close.is_empty() { return "Every open app is kept, so there's nothing to quit.".into(); }
    let ids: HashSet<&String> = plan.close.iter().map(|a| &a.id).collect();
    let freed: u64 = open.iter().filter(|a| ids.contains(&a.app.id)).map(|a| a.memory).sum();
    let them = if plan.close.len() == 1 { "it" } else { "them" };
    format!("Starting a new session will save and quit {}, freeing about {} of RAM. Click again to reopen {}.",
            apps_text(plan.close.len()), memory_text(freed), them)
}

// —— the careful quit queue ——

/// Closes apps one at a time: ask one to close, wait until it has gone (it may be saving), then the next. An app
/// still open after `patience_ms` — usually a "save changes?" prompt — goes on the waiting list and the queue
/// moves on, so one prompt never stalls a session. Nothing is ever forced. With `all_at_once` every app is asked
/// at the same moment ("Speed first").
#[derive(Debug)]
pub struct QuitQueue {
    pending: Vec<AppRef>,
    current: Option<(AppRef, u64)>,
    asked: Vec<(AppRef, u64)>,
    pub waiting: Vec<AppRef>,
    patience_ms: u64,
    all_at_once: bool,
}
#[derive(Debug, PartialEq)]
pub enum QueueStep {
    /// Ask these apps to close now.
    Close(Vec<AppRef>),
    /// Nothing to do this tick.
    Wait,
    /// Every app has gone or is on the waiting list.
    Done,
}
impl QuitQueue {
    pub fn new(apps: Vec<AppRef>, patience_ms: u64, all_at_once: bool) -> Self {
        QuitQueue { pending: apps, current: None, asked: vec![], waiting: vec![], patience_ms, all_at_once }
    }
    pub fn is_done(&self) -> bool { self.pending.is_empty() && self.current.is_none() && self.asked.is_empty() }
    pub fn step(&mut self, now_ms: u64, is_open: &dyn Fn(&AppRef) -> bool) -> QueueStep {
        if self.all_at_once {
            if !self.pending.is_empty() {
                let all: Vec<AppRef> = self.pending.drain(..).collect();
                self.asked = all.iter().cloned().map(|a| (a, now_ms)).collect();
                return QueueStep::Close(all);
            }
            let patience = self.patience_ms;
            let mut late = vec![];
            self.asked.retain(|(a, t)| {
                if !is_open(a) { return false; }
                if now_ms.saturating_sub(*t) >= patience { late.push(a.clone()); return false; }
                true
            });
            self.waiting.extend(late);
            return if self.asked.is_empty() { QueueStep::Done } else { QueueStep::Wait };
        }
        if let Some((app, since)) = self.current.take() {
            if is_open(&app) {
                if now_ms.saturating_sub(since) < self.patience_ms { self.current = Some((app, since)); return QueueStep::Wait; }
                self.waiting.push(app);
            }
        }
        // skip anything that has already gone on its own
        while !self.pending.is_empty() {
            let next = self.pending.remove(0);
            if is_open(&next) { self.current = Some((next.clone(), now_ms)); return QueueStep::Close(vec![next]); }
        }
        QueueStep::Done
    }
    /// Stop: the session ended (or was restarted) while apps were still closing.
    pub fn cancel(&mut self) { self.pending.clear(); self.current = None; self.asked.clear(); }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn app(id: &str) -> AppRef { AppRef { id: id.into(), name: id.to_uppercase(), launch: Launch::Exe { path: format!("C:\\{id}.exe") } } }
    fn open(id: &str, mb: u64) -> OpenApp { OpenApp { app: app(id), memory: mb * 1_048_576, protected: false } }
    fn ids(v: &[AppRef]) -> Vec<&str> { v.iter().map(|a| a.id.as_str()).collect() }

    #[test] fn a_session_closes_what_is_not_kept_biggest_first_and_brings_it_back() {
        let mut s = State::default();
        s.keep = vec!["editor".into()];
        let apps = [open("editor", 300), open("small", 50), open("big", 4000),
                    OpenApp { protected: true, ..open("shell", 900) }];
        let plan = s.start(&apps, None, 100).unwrap();
        assert_eq!(ids(&plan.close), ["big", "small"]);
        assert!(s.focused);
        assert_eq!(s.live().unwrap().kept, ["editor"]);
        assert_eq!(ids(&s.end()), ["big", "small"]);
        assert!(!s.focused && s.end().is_empty());
    }
    #[test] fn nothing_to_close_starts_nothing() {
        let mut s = State::default();
        s.keep = vec!["a".into()];
        assert!(s.start(&[open("a", 10)], None, 0).is_none());
        assert!(!s.focused);
    }
    #[test] fn critical_processes_are_never_closed() {
        let mut s = State::default();
        s.never_close = vec!["dictation".into()];
        let plan = s.start(&[open("dictation", 10), open("x", 10)], None, 0).unwrap();
        assert_eq!(plan.close.len(), 1);
        assert!(!s.take_out(&app("dictation")));
    }
    #[test] fn history_is_capped_at_twelve() {
        let mut s = State::default();
        for i in 0..15 { s.start(&[open("x", 1)], None, i); s.end(); }
        assert_eq!(s.sessions.len(), HISTORY);
        assert_eq!(s.sessions[0].started, 14);
    }
    #[test] fn state_survives_saving_and_corruption() {
        let mut s = State::default();
        s.create_mode("AI", vec![app("chat")]);
        s.start(&[open("x", 1)], None, 7);
        assert_eq!(State::load(&s.save()), s);
        assert_eq!(State::load("{ not json"), State::default());
        assert_eq!(State::load(r#"{"focused":"yes","modes":7}"#), State::default());
        assert!(State::load(r#"{"focused":true,"unknown":1}"#).focused);
    }
    #[test] fn modes_take_the_next_number_and_a_number_belongs_to_one_mode() {
        let mut s = State::default();
        let a = s.create_mode("", vec![app("x")]).unwrap();
        let b = s.create_mode("Web", vec![app("browser"), app("browser")]).unwrap();
        assert_eq!((s.modes[0].name.as_str(), s.modes[0].key), ("Mode 1", Some(1)));
        assert_eq!((s.modes[1].key, s.modes[1].apps.len()), (Some(2), 1));
        assert!(s.create_mode("Empty", vec![]).is_none());
        s.set_mode_key(&b, Some(1));
        assert_eq!(s.mode_for_key(1).unwrap().id, b);
        assert_eq!(s.modes.iter().find(|m| m.id == a).unwrap().key, None);
        for _ in 0..12 { s.create_mode("", vec![app("x")]); }
        assert_eq!(s.next_mode_key(), None);
    }
    #[test] fn a_mode_opens_its_apps_closes_the_rest_and_names_the_session() {
        let mut s = State::default();
        let id = s.create_mode("Research", vec![app("browser"), app("notes")]).unwrap();
        let plan = s.start(&[open("browser", 10), open("game", 9000)], Some(&id), 0).unwrap();
        assert_eq!(plan.close[0].id, "game");
        assert_eq!(plan.open[0].id, "notes");
        assert_eq!(s.display_name().unwrap(), "Research");
        assert_eq!(s.mode_action(&id), ModeAction::End);
    }
    #[test] fn switching_modes_is_one_session_and_leaves_the_ticks_alone() {
        let mut s = State::default();
        s.keep = vec!["mine".into()];
        let writing = s.create_mode("Writing", vec![app("editor")]).unwrap();
        let sums = s.create_mode("Sums", vec![app("calc")]).unwrap();
        s.start(&[open("editor", 10), open("calc", 10), open("mail", 10)], Some(&writing), 0).unwrap();
        assert_eq!(s.mode_action(&sums), ModeAction::Switch);
        let plan = s.switch_mode(&[open("editor", 10)], &sums).unwrap();
        assert_eq!(ids(&plan.open), ["calc"]);
        assert_eq!(ids(&plan.close), ["editor"]);
        assert_eq!(s.keep, ["mine"]);
        assert_eq!(s.sessions.len(), 1);
        let mut back: Vec<String> = s.end().into_iter().map(|a| a.id).collect();
        back.sort();
        assert_eq!(back, ["editor", "mail"]);
    }
    #[test] fn an_app_can_leave_and_rejoin_a_running_session() {
        let mut s = State::default();
        s.keep = vec!["a".into(), "b".into()];
        s.start(&[open("a", 1), open("b", 1), open("c", 1)], None, 0).unwrap();
        assert!(s.take_out(&app("b")));
        assert!(!s.take_out(&app("b")));
        assert_eq!(s.bring_back("c").unwrap().id, "c");
        assert_eq!(ids(&s.end()), ["b"]);
    }
    #[test] fn an_unnamed_session_is_called_by_the_mode_it_matches() {
        let mut s = State::default();
        s.create_mode("AI", vec![app("chat"), app("browser")]);
        s.keep = vec!["chat".into(), "notes".into()];
        s.start(&[open("chat", 1), open("notes", 1), open("x", 1)], None, 0).unwrap();
        assert_eq!(s.display_name().unwrap(), "AI");
        s.end();
        s.keep = vec!["notes".into()];
        s.start(&[open("notes", 1), open("x", 1)], None, 0).unwrap();
        assert_eq!(s.display_name().unwrap(), "Focus");
    }
    #[test] fn the_caption_says_what_a_click_will_do() {
        let mut s = State::default();
        let apps = [open("a", 2048), open("b", 512)];
        assert_eq!(caption(&s, &apps), "Starting a new session will save and quit 2 apps, freeing about 2.5 GB of RAM. Click again to reopen them.");
        s.keep = vec!["a".into(), "b".into()];
        assert_eq!(caption(&s, &apps), "Every open app is kept, so there's nothing to quit.");
        s.keep.clear();
        s.start(&apps, None, 0);
        assert_eq!(caption(&s, &apps), "Ending the session will reopen 2 apps exactly as they were.");
        assert_eq!(memory_text(310 * 1_048_576), "310 MB");
    }
    #[test] fn the_queue_closes_one_at_a_time_and_a_save_prompt_never_stalls_it() {
        let mut q = QuitQueue::new(vec![app("a"), app("stuck"), app("c")], 8000, false);
        let open_now = std::cell::RefCell::new(vec!["a", "stuck", "c"]);
        let is_open = |a: &AppRef| open_now.borrow().contains(&a.id.as_str());
        assert_eq!(q.step(0, &is_open), QueueStep::Close(vec![app("a")]));
        assert_eq!(q.step(500, &is_open), QueueStep::Wait);
        open_now.borrow_mut().retain(|x| *x != "a");
        assert_eq!(q.step(600, &is_open), QueueStep::Close(vec![app("stuck")]));
        assert_eq!(q.step(5000, &is_open), QueueStep::Wait);
        assert_eq!(q.step(8700, &is_open), QueueStep::Close(vec![app("c")]));
        assert_eq!(q.waiting, vec![app("stuck")]);
        open_now.borrow_mut().retain(|x| *x != "c");
        assert_eq!(q.step(8800, &is_open), QueueStep::Done);
        assert!(q.is_done());
    }
    #[test] fn speed_first_asks_everything_at_once() {
        let mut q = QuitQueue::new(vec![app("a"), app("b")], 8000, true);
        let gone = std::cell::Cell::new(false);
        let is_open = |_: &AppRef| !gone.get();
        assert_eq!(q.step(0, &is_open), QueueStep::Close(vec![app("a"), app("b")]));
        assert_eq!(q.step(100, &is_open), QueueStep::Wait);
        gone.set(true);
        assert_eq!(q.step(200, &is_open), QueueStep::Done);
    }
}
