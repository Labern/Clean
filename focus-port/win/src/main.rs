//! Focus for Windows.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "console")]

#[cfg(windows)]
mod apps;
#[cfg(windows)]
mod selftest;

#[cfg(windows)]
fn main() {
    let args: Vec<String> = std::env::args().collect();
    match args.get(1).map(|s| s.as_str()) {
        Some("--list") => {
            for f in apps::open_apps() {
                println!("{:<8} {:>9}  {:<28} {}  windows:{}{}", if f.store { "store" } else { "exe" }, focus_core::memory_text(f.open.memory),
                         f.open.app.name, f.open.app.id, f.windows.len(), if f.open.protected { "  [system]" } else { "" });
            }
        }
        Some("--selftest") => std::process::exit(selftest::run()),
        _ => println!("Focus for Windows — the tray app is not built yet. Try --list or --selftest."),
    }
}

#[cfg(not(windows))]
fn main() { println!("This is the Windows app. On this system, build the drawing examples instead: cargo run -p focus-ui --example render"); }
