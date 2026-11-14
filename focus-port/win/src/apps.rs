//! Windows: what "an app" is, and how to close and reopen one.
//!
//! Windows has processes and windows, not apps. Focus's rule:
//! - An app is every visible, top-level window a person could switch to (what Alt+Tab shows), grouped by the
//!   program that owns them.
//! - A classic program is identified by the path of its .exe; it is reopened by starting that .exe.
//! - A Microsoft Store (packaged) app is identified by its Application User Model ID, and reopened through the
//!   shell's AppsFolder, which is how the Start menu starts it. Store apps drawn inside a shared frame window
//!   (ApplicationFrameHost) are traced to the real process behind the frame.
//! - Closing is always polite: each window is sent the same close request as clicking its ✕, so the app can save
//!   or ask. Nothing is ever terminated.
use focus_core::{AppRef, Launch, OpenApp};
use std::collections::HashMap;
use std::ffi::c_void;
use windows_sys::Win32::Foundation::{CloseHandle, BOOL, HANDLE, HWND, LPARAM, MAX_PATH};
use windows_sys::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows_sys::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows_sys::Win32::Storage::Packaging::Appx::GetApplicationUserModelId;
use windows_sys::Win32::System::Diagnostics::ToolHelp::{CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS};
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS, PROCESS_MEMORY_COUNTERS_EX};
use windows_sys::Win32::System::Threading::{GetCurrentProcessId, OpenProcess, QueryFullProcessImageNameW, PROCESS_QUERY_LIMITED_INFORMATION};
use windows_sys::Win32::UI::Shell::ShellExecuteW;
use windows_sys::Win32::UI::WindowsAndMessaging::{
    EnumWindows, FindWindowExW, GetClassNameW, GetWindow, GetWindowLongPtrW, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible,
    PostMessageW, GWL_EXSTYLE, GW_OWNER, SW_SHOWNORMAL, WM_CLOSE, WS_EX_APPWINDOW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

pub fn wide(s: &str) -> Vec<u16> { s.encode_utf16().chain(std::iter::once(0)).collect() }
fn from_wide(buf: &[u16]) -> String { let n = buf.iter().position(|&c| c == 0).unwrap_or(buf.len()); String::from_utf16_lossy(&buf[..n]) }

/// An app that is open: the core's view of it, plus the windows to ask when it should close.
#[derive(Clone, Debug)]
pub struct Found {
    pub open: OpenApp,
    pub windows: Vec<isize>,
    pub store: bool,
}

struct Process { handle: HANDLE }
impl Process {
    fn open(pid: u32) -> Option<Process> {
        let h = unsafe { OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, 0, pid) };
        if h.is_null() { None } else { Some(Process { handle: h }) }
    }
    fn path(&self) -> Option<String> {
        let mut buf = [0u16; 1024]; let mut len = buf.len() as u32;
        if unsafe { QueryFullProcessImageNameW(self.handle, 0, buf.as_mut_ptr(), &mut len) } == 0 { return None; }
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }
    /// The Store identity of a packaged process, if it has one.
    fn aumid(&self) -> Option<String> {
        let mut buf = [0u16; 512]; let mut len = buf.len() as u32;
        if unsafe { GetApplicationUserModelId(self.handle, &mut len, buf.as_mut_ptr()) } != 0 { return None; }
        let s = from_wide(&buf);
        if s.is_empty() { None } else { Some(s) }
    }
    /// Private bytes: memory that goes back to the system when the process ends.
    fn memory(&self) -> u64 {
        let mut c: PROCESS_MEMORY_COUNTERS_EX = unsafe { std::mem::zeroed() };
        let size = std::mem::size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32;
        if unsafe { K32GetProcessMemoryInfo(self.handle, &mut c as *mut _ as *mut PROCESS_MEMORY_COUNTERS, size) } == 0 { return 0; }
        c.PrivateUsage as u64
    }
}
impl Drop for Process { fn drop(&mut self) { unsafe { CloseHandle(self.handle); } } }

fn class_name(hwnd: HWND) -> String { let mut b = [0u16; 256]; unsafe { GetClassNameW(hwnd, b.as_mut_ptr(), b.len() as i32) }; from_wide(&b) }
fn title(hwnd: HWND) -> String {
    let n = unsafe { GetWindowTextLengthW(hwnd) };
    if n <= 0 { return String::new(); }
    let mut b = vec![0u16; n as usize + 1];
    unsafe { GetWindowTextW(hwnd, b.as_mut_ptr(), b.len() as i32) };
    from_wide(&b)
}
fn pid_of(hwnd: HWND) -> u32 { let mut pid = 0u32; unsafe { GetWindowThreadProcessId(hwnd, &mut pid) }; pid }

/// A window a person could switch to: visible, not hidden by the system ("cloaked"), top-level, not a tool window.
fn switchable(hwnd: HWND) -> bool {
    unsafe {
        if IsWindowVisible(hwnd) == 0 { return false; }
        let mut cloaked = 0u32;
        DwmGetWindowAttribute(hwnd, DWMWA_CLOAKED as u32, &mut cloaked as *mut u32 as *mut c_void, 4);
        if cloaked != 0 { return false; }
        let ex = GetWindowLongPtrW(hwnd, GWL_EXSTYLE) as u32;
        if ex & WS_EX_APPWINDOW != 0 { return true; }
        if ex & (WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE) != 0 { return false; }
        if !GetWindow(hwnd, GW_OWNER).is_null() { return false; }
        GetWindowTextLengthW(hwnd) > 0
    }
}

unsafe extern "system" fn collect(hwnd: HWND, lparam: LPARAM) -> BOOL {
    let list = &mut *(lparam as *mut Vec<HWND>);
    list.push(hwnd);
    1
}

/// The product's own description of a program ("Notepad", "Google Chrome"), from its version information.
fn description(path: &str) -> Option<String> {
    let w = wide(path);
    unsafe {
        let mut handle = 0u32;
        let size = GetFileVersionInfoSizeW(w.as_ptr(), &mut handle);
        if size == 0 { return None; }
        let mut data = vec![0u8; size as usize];
        if GetFileVersionInfoW(w.as_ptr(), 0, size, data.as_mut_ptr() as *mut c_void) == 0 { return None; }
        let mut ptr: *mut c_void = std::ptr::null_mut(); let mut len = 0u32;
        let mut langs: Vec<String> = vec![];
        if VerQueryValueW(data.as_ptr() as *const c_void, wide("\\VarFileInfo\\Translation").as_ptr(), &mut ptr, &mut len) != 0 && len >= 4 {
            let t = std::slice::from_raw_parts(ptr as *const u16, (len / 2) as usize);
            for pair in t.chunks_exact(2) { langs.push(format!("{:04x}{:04x}", pair[0], pair[1])); }
        }
        langs.extend(["040904b0".to_string(), "040904e4".to_string(), "000004b0".to_string()]);
        for lang in langs {
            let key = wide(&format!("\\StringFileInfo\\{lang}\\FileDescription"));
            if VerQueryValueW(data.as_ptr() as *const c_void, key.as_ptr(), &mut ptr, &mut len) != 0 && len > 1 {
                let s = from_wide(std::slice::from_raw_parts(ptr as *const u16, len as usize));
                let s = s.trim().to_string();
                if !s.is_empty() { return Some(s); }
            }
        }
        None
    }
}

/// Parts of Windows itself, by program name: the desktop and taskbar, the frame that hosts Store apps, the Start
/// menu, search, the on-screen keyboard and the lock screen. Never listed, never closed. (Names of Windows
/// components only — never a person's own apps.)
const SYSTEM: [&str; 12] = ["explorer.exe", "applicationframehost.exe", "shellexperiencehost.exe", "startmenuexperiencehost.exe", "searchhost.exe",
                            "searchapp.exe", "textinputhost.exe", "lockapp.exe", "dwm.exe", "sihost.exe", "ctfmon.exe", "widgets.exe"];

fn file_name(path: &str) -> String { path.rsplit(['\\', '/']).next().unwrap_or(path).to_string() }

/// Memory of every running process, keyed by the lower-cased path of its program: an app's memory is the sum over
/// all its processes (a browser is dozens).
fn memory_by_program() -> HashMap<String, u64> {
    let mut map = HashMap::new();
    unsafe {
        let snap = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
        if snap as isize == -1 { return map; }
        let mut e: PROCESSENTRY32W = std::mem::zeroed();
        e.dwSize = std::mem::size_of::<PROCESSENTRY32W>() as u32;
        if Process32FirstW(snap, &mut e) != 0 {
            loop {
                if let Some(p) = Process::open(e.th32ProcessID) {
                    if let Some(path) = p.path() { *map.entry(path.to_lowercase()).or_insert(0) += p.memory(); }
                }
                if Process32NextW(snap, &mut e) == 0 { break; }
            }
        }
        CloseHandle(snap);
    }
    map
}

/// Every app that is open now.
pub fn open_apps() -> Vec<Found> {
    let mut hwnds: Vec<HWND> = vec![];
    unsafe { EnumWindows(Some(collect), &mut hwnds as *mut Vec<HWND> as LPARAM) };
    let me = unsafe { GetCurrentProcessId() };
    let memory = memory_by_program();
    let mut found: Vec<Found> = vec![];
    for hwnd in hwnds {
        if !switchable(hwnd) { continue; }
        let mut pid = pid_of(hwnd);
        let framed = class_name(hwnd) == "ApplicationFrameWindow";
        if framed {
            // a Store app inside the shared frame: the real app is the process behind the frame's core window
            let core = unsafe { FindWindowExW(hwnd, std::ptr::null_mut(), wide("Windows.UI.Core.CoreWindow").as_ptr(), std::ptr::null()) };
            if core.is_null() { continue; }                    // an empty frame (the app is suspended elsewhere)
            pid = pid_of(core);
        }
        if pid == me { continue; }
        let Some(process) = Process::open(pid) else { continue };
        let Some(path) = process.path() else { continue };
        let program = file_name(&path).to_lowercase();
        let aumid = process.aumid();
        let (id, launch, store) = match &aumid {
            Some(a) => (a.clone(), Launch::Store { aumid: a.clone() }, true),
            None => (path.to_lowercase(), Launch::Exe { path: path.clone() }, false),
        };
        if let Some(f) = found.iter_mut().find(|f| f.open.app.id == id) { f.windows.push(hwnd as isize); continue; }
        let window_title = title(hwnd);
        let name = if framed { window_title.clone() } else {
            description(&path).unwrap_or_else(|| window_title.rsplit(" - ").next().unwrap_or(&window_title).to_string())
        };
        let name = if name.trim().is_empty() { file_name(&path).trim_end_matches(".exe").to_string() } else { name };
        found.push(Found {
            open: OpenApp { app: AppRef { id, name, launch }, memory: memory.get(&path.to_lowercase()).copied().unwrap_or_else(|| process.memory()),
                            protected: SYSTEM.contains(&program.as_str()) },
            windows: vec![hwnd as isize], store,
        });
    }
    found
}

/// Asks an app to close, the way clicking ✕ on each of its windows does. It may save, or ask first.
pub fn close(app: &Found) { for &w in &app.windows { unsafe { PostMessageW(w as HWND, WM_CLOSE, 0, 0) }; } }

/// Starts an app again. True if Windows accepted the request.
pub fn launch(how: &Launch) -> bool {
    let target = match how {
        Launch::Exe { path } => path.clone(),
        Launch::Store { aumid } => format!("shell:AppsFolder\\{aumid}"),
        Launch::Desktop { .. } => return false,
    };
    let r = unsafe { ShellExecuteW(std::ptr::null_mut(), wide("open").as_ptr(), wide(&target).as_ptr(), std::ptr::null(), std::ptr::null(), SW_SHOWNORMAL) };
    r as isize > 32
}

#[allow(dead_code)]
pub const MAX: u32 = MAX_PATH;
