# Notify existing Explorer windows after changing context-menu associations
if (-not ('SvnScope.ShellNotifications' -as [type])) {
    Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace SvnScope {
    public static class ShellNotifications {
        [DllImport("shell32.dll")]
        private static extern void SHChangeNotify(uint eventId, uint flags, IntPtr item1, IntPtr item2);

        public static void RefreshAssociations() {
            const uint SHCNE_ASSOCCHANGED = 0x08000000;
            const uint SHCNF_IDLIST = 0x0000;
            const uint SHCNF_FLUSH = 0x1000;
            SHChangeNotify(SHCNE_ASSOCCHANGED, SHCNF_IDLIST | SHCNF_FLUSH, IntPtr.Zero, IntPtr.Zero);
        }
    }
}
"@
}
[SvnScope.ShellNotifications]::RefreshAssociations()
