//! Focus for Windows.
//!   focus                  the tray app: an icon by the clock; Ctrl+Shift+F starts and ends a session
//!   focus --list           the apps Focus can see, with their memory
//!   focus --selftest       a real session with throwaway apps, pass/fail per step (no windows of its own)
//!   focus --cloud-test DIR the tray app driven like a person would, with a screenshot at every step

#[cfg(windows)]
mod apps;
#[cfg(windows)]
mod cloudtest;
#[cfg(windows)]
mod selftest;
#[cfg(windows)]
mod shell;

#[cfg(windows)]
fn main() {
    let args: Vec<String> = std::env::args().collect();
    let code = match args.get(1).map(|s| s.as_str()) {
        Some("--list") => {
            for f in apps::open_apps() {
                println!("{:<6} {:>9}  {:<28} {}  windows:{}{}", if f.store { "store" } else { "exe" }, focus_core::memory_text(f.open.memory),
                         f.open.app.name, f.open.app.id, f.windows.len(), if f.open.protected { "  [system]" } else { "" });
            }
            0
        }
        Some("--selftest") => selftest::run(),
        Some("--cloud-test") => cloudtest::run(args.get(2).map(|s| s.as_str()).unwrap_or("out")),
        _ => shell::run(None, None, |_| {}),
    };
    std::process::exit(code);
}

#[cfg(not(windows))]
fn main() { println!("This is the Windows app. On this system, draw the pictures instead: cargo run -p focus-ui --example render"); }
