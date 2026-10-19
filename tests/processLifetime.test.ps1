param(
    [Parameter(Mandatory = $true)][string]$Executable,
    [switch]$ExpectAttached
)
$ErrorActionPreference = 'Stop'
# Launch only a disposable welcome-window instance; never stop an existing client
Add-Type -TypeDefinition @"
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
public static class ScopeLifetimeTest {
    [StructLayout(LayoutKind.Sequential)] public struct BasicLimits {
        public long ProcessTime, JobTime;
        public uint Flags;
        public UIntPtr MinWorkingSet, MaxWorkingSet;
        public uint ActiveProcessLimit;
        public UIntPtr Affinity;
        public uint Priority, Scheduling;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ExtendedLimits {
        public BasicLimits Basic;
        public ulong ReadOps, WriteOps, OtherOps, ReadBytes, WriteBytes, OtherBytes;
        public UIntPtr ProcessMemory, JobMemory, PeakProcessMemory, PeakJobMemory;
    }
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)] public struct StartupInfo {
        public int Size;
        public string Reserved, Desktop, Title;
        public uint X, Y, Width, Height, XChars, YChars, Fill, Flags;
        public ushort ShowWindow, ReservedSize;
        public IntPtr ReservedPointer, StdInput, StdOutput, StdError;
    }
    [StructLayout(LayoutKind.Sequential)] public struct ProcessInfo {
        public IntPtr Process, Thread;
        public int ProcessId, ThreadId;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern IntPtr CreateJobObject(IntPtr attributes, string name);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool SetInformationJobObject(IntPtr job, int info, ref ExtendedLimits limits, uint size);
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
    static extern bool CreateProcess(string app, StringBuilder command, IntPtr pa, IntPtr ta, bool inherit, uint flags, IntPtr env, string cwd, ref StartupInfo startup, out ProcessInfo process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern uint ResumeThread(IntPtr thread);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool CloseHandle(IntPtr handle);
    [DllImport("kernel32.dll", SetLastError = true)]
    public static extern bool IsProcessInJob(IntPtr process, IntPtr job, out bool result);
    [DllImport("kernel32.dll", SetLastError = true)]
    static extern bool TerminateProcess(IntPtr process, uint code);
    static void Check(bool success) { if (!success) throw new Win32Exception(); }
    public static IntPtr CreateJob() {
        var job = CreateJobObject(IntPtr.Zero, null);
        Check(job != IntPtr.Zero);
        var limits = new ExtendedLimits();
        limits.Basic.Flags = 0x2000 | 0x0800;
        try { Check(SetInformationJobObject(job, 9, ref limits, (uint)Marshal.SizeOf(limits))); }
        catch { CloseHandle(job); throw; }
        return job;
    }
    public static int Launch(IntPtr job, string executable) {
        var startup = new StartupInfo();
        startup.Size = Marshal.SizeOf(startup);
        ProcessInfo process;
        // Start suspended outside the test runner job, then assign our own job
        Check(CreateProcess(executable, new StringBuilder("\"" + executable + "\""), IntPtr.Zero, IntPtr.Zero, false, 0x01000004, IntPtr.Zero, System.IO.Path.GetDirectoryName(executable), ref startup, out process));
        try {
            Check(AssignProcessToJobObject(job, process.Process));
            Check(ResumeThread(process.Thread) != uint.MaxValue);
            return process.ProcessId;
        } catch { TerminateProcess(process.Process, 1); throw; }
        finally { CloseHandle(process.Thread); CloseHandle(process.Process); }
    }
}
"@
$exePath = (Resolve-Path -LiteralPath $Executable).Path
$jobHandle = [ScopeLifetimeTest]::CreateJob()
$childProcess = $null
try {
    $launcherId = [ScopeLifetimeTest]::Launch($jobHandle, $exePath)
    if ($ExpectAttached) {
        Start-Sleep -Seconds 3
        $launcher = Get-Process -Id $launcherId -ErrorAction Stop
        $isInJob = $false
        if (-not [ScopeLifetimeTest]::IsProcessInJob($launcher.Handle, [IntPtr]::Zero, [ref]$isInJob) -or -not $isInJob) {
            throw 'Baseline did not inherit the terminal job'
        }
        [ScopeLifetimeTest]::CloseHandle($jobHandle) | Out-Null
        $jobHandle = [IntPtr]::Zero
        if (-not $launcher.WaitForExit(5000)) { throw 'Baseline unexpectedly survived terminal closure' }
        Write-Output 'PASS baseline: old client disappears when the terminal job closes.'
    } else {
        $deadline = [DateTime]::UtcNow.AddSeconds(15)
        do {
            $childInfo = Get-CimInstance Win32_Process -Filter "ParentProcessId = $launcherId" |
                Where-Object { $_.ExecutablePath -eq $exePath } | Select-Object -First 1
            if ($null -ne $childInfo) { break }
            Start-Sleep -Milliseconds 100
        } while ([DateTime]::UtcNow -lt $deadline)
        if ($null -eq $childInfo) { throw 'No independent client was started' }
        $childProcess = Get-Process -Id $childInfo.ProcessId -ErrorAction Stop
        # An unrelated outer job may remain; the terminal-owned job must be escaped
        $isInTestJob = $true
        if (-not [ScopeLifetimeTest]::IsProcessInJob($childProcess.Handle, $jobHandle, [ref]$isInTestJob) -or $isInTestJob) {
            throw 'Client still belongs to the terminal-owned job'
        }
        $launcher = Get-Process -Id $launcherId -ErrorAction SilentlyContinue
        if ($null -ne $launcher -and -not $launcher.WaitForExit(5000)) { throw 'Transient launcher did not exit' }
        [ScopeLifetimeTest]::CloseHandle($jobHandle) | Out-Null
        $jobHandle = [IntPtr]::Zero
        Start-Sleep -Seconds 3
        if ($childProcess.HasExited) { throw 'Client disappeared after terminal closure' }
        Write-Output "PASS: launcher exits, independent client survives terminal job closure (PID $($childProcess.Id))."
    }
} finally {
    if ($jobHandle -ne [IntPtr]::Zero) { [ScopeLifetimeTest]::CloseHandle($jobHandle) | Out-Null }
    if ($null -ne $childProcess -and -not $childProcess.HasExited) {
        $childProcess.Kill()
        $childProcess.WaitForExit(5000) | Out-Null
    }
}
