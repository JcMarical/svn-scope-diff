#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

#[cfg(all(windows, not(debug_assertions)))]
mod process_lifetime;

fn main() {
    #[cfg(all(windows, not(debug_assertions)))]
    if process_lifetime::relaunch_outside_terminal_job() {
        return;
    }

    svn_scope_lib::run();
}
