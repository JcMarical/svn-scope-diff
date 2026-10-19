use std::os::windows::process::CommandExt;
use std::process::{Command, Stdio};
use std::ptr::null_mut;
use windows_sys::Win32::System::JobObjects::{
    IsProcessInJob, JobObjectExtendedLimitInformation, QueryInformationJobObject,
    JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_BREAKAWAY_OK,
    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE, JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK,
};
use windows_sys::Win32::System::Threading::{GetCurrentProcess, CREATE_BREAKAWAY_FROM_JOB};

// Keep the release GUI alive when a task terminal closes its process job
pub fn relaunch_outside_terminal_job() -> bool {
    if !needs_independent_process() {
        return false;
    }
    let Ok(executable) = std::env::current_exe() else {
        return false;
    };

    // Preserve folder arguments and the working directory; leave dev builds attached
    Command::new(executable)
        .args(std::env::args_os().skip(1))
        .creation_flags(CREATE_BREAKAWAY_FROM_JOB)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()
        .is_ok()
}

fn needs_independent_process() -> bool {
    // The null job handle queries this process's job without opening another job
    unsafe {
        let mut is_in_job = 0;
        if IsProcessInJob(GetCurrentProcess(), null_mut(), &mut is_in_job) == 0 || is_in_job == 0 {
            return false;
        }
        let mut limits: JOBOBJECT_EXTENDED_LIMIT_INFORMATION = std::mem::zeroed();
        if QueryInformationJobObject(
            null_mut(),
            JobObjectExtendedLimitInformation,
            (&mut limits as *mut JOBOBJECT_EXTENDED_LIMIT_INFORMATION).cast(),
            std::mem::size_of_val(&limits) as u32,
            null_mut(),
        ) == 0
        {
            return false;
        }
        let flags = limits.BasicLimitInformation.LimitFlags;
        flags & JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE != 0
            && flags & (JOB_OBJECT_LIMIT_BREAKAWAY_OK | JOB_OBJECT_LIMIT_SILENT_BREAKAWAY_OK) != 0
    }
}
