using System;
using System.IO;
using System.Net;
using System.Reflection;
using System.Runtime.InteropServices;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Makes the SMCWinDivert DLL + sys driver files available in the settings
    /// folder (%localappdata%\PrisonLifeMacro) on first launch. The files are
    /// embedded inside the exe and extracted when the app runs; if for some
    /// reason they aren't embedded, they're pulled from this repo's GitHub
    /// release assets as a fallback.
    /// </summary>
    public static class DriverInstaller
    {
        public const string DllName = "SMCWinDivert.dll";
        public const string SysName = "SMCWinDivert64.sys";
        public const string WinDivertSysName = "WinDivert64.sys";

        private const string DllRes = "SMCDriver.dll";
        private const string SysRes = "SMCDriver.sys";

        public const string Repo = "orbitthegreatest/PrisonLifeMacro";
        public const string BaseUrl = "https://github.com/" + Repo + "/releases/latest/download/";

        public static string DllPath
        {
            get { return Path.Combine(Settings.SettingsDir, DllName); }
        }

        public static string SysPath
        {
            get { return Path.Combine(Settings.SettingsDir, SysName); }
        }

        public static string WinDivertSysPath
        {
            get { return Path.Combine(Settings.SettingsDir, WinDivertSysName); }
        }

        /// <summary>True when both driver files already exist in the settings folder.</summary>
        public static bool AreInstalled()
        {
            return File.Exists(DllPath) && File.Exists(SysPath);
        }

        /// <summary>
        /// Ensures the driver files exist, extracting them from the app's embedded
        /// resources (or downloading as a fallback). Also makes sure the "WinDivert64.sys"
        /// name the WinDivert DLL actually looks for is present, and unregisters any stale
        /// "WinDivert" service left behind by a previous (possibly deleted) driver install.
        /// Silent on failure so it never blocks the app from starting.
        /// </summary>
        public static bool EnsureInstalled()
        {
            bool ok = true;
            if (!File.Exists(DllPath))
                ok &= ExtractResource(DllRes, DllPath, DllName);
            if (!File.Exists(SysPath))
                ok &= ExtractResource(SysRes, SysPath, SysName);
            // The bundled DLL is stock WinDivert, which resolves its kernel driver as
            // "WinDivert64.sys". Without this exact name next to the DLL (and without a
            // clean service entry) WinDivertOpen fails with ERROR_FILE_NOT_FOUND (2).
            if (!File.Exists(WinDivertSysPath))
                ok &= ExtractResource(SysRes, WinDivertSysPath, WinDivertSysName);

            // If a previous driver install registered a WinDivert service whose .sys file
            // no longer exists (e.g. antivirus deleted it), the stock DLL will just try to
            // start that dead path and report error 2 forever. Remove the stale service so
            // WinDivertOpen re-installs the driver from our freshly extracted files.
            RemoveStaleWinDivertService();
            return ok;
        }

        // ---------------- stale WinDivert driver service cleanup ----------------

        private const uint SC_MANAGER_ALL_ACCESS = 0xF003F;
        private const uint SERVICE_ALL_ACCESS = 0xF01FF;
        private const uint ERROR_INSUFFICIENT_BUFFER = 122;

        [StructLayout(LayoutKind.Sequential)]
        private struct QUERY_SERVICE_CONFIG
        {
            public uint dwServiceType;
            public uint dwStartType;
            public uint dwErrorControl;
            public IntPtr lpBinaryPathName;
            public IntPtr lpLoadOrderGroup;
            public IntPtr dwTagId;
            public IntPtr lpDependencies;
            public IntPtr lpServiceStartName;
            public IntPtr lpDisplayName;
        }

        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr OpenSCManager(string lpMachineName, string lpDatabaseName, uint dwDesiredAccess);
        [DllImport("advapi32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
        private static extern IntPtr OpenService(IntPtr hSCManager, string lpServiceName, uint dwDesiredAccess);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool DeleteService(IntPtr hService);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool CloseServiceHandle(IntPtr hSCObject);
        [DllImport("advapi32.dll", SetLastError = true)]
        private static extern bool QueryServiceConfig(IntPtr hService, IntPtr lpServiceConfig, uint cbBufSize, out uint pcbBytesNeeded);

        /// <summary>Deletes the "WinDivert" service only when it points to a driver file that no longer exists.</summary>
        public static void RemoveStaleWinDivertService()
        {
            try
            {
                IntPtr scm = OpenSCManager(null, null, SC_MANAGER_ALL_ACCESS);
                if (scm == IntPtr.Zero)
                    return;
                try
                {
                    IntPtr svc = OpenService(scm, "WinDivert", SERVICE_ALL_ACCESS);
                    if (svc == IntPtr.Zero)
                        return;   // not installed -> nothing stale to remove
                    try
                    {
                        if (!ServiceBinaryExists(svc))
                            DeleteService(svc);
                    }
                    finally
                    {
                        CloseServiceHandle(svc);
                    }
                }
                finally
                {
                    CloseServiceHandle(scm);
                }
            }
            catch { }
        }

        private static bool ServiceBinaryExists(IntPtr hService)
        {
            uint needed = 0;
            if (!QueryServiceConfig(hService, IntPtr.Zero, 0, out needed))
            {
                if (Marshal.GetLastWin32Error() != ERROR_INSUFFICIENT_BUFFER)
                    return true;   // can't read the config -> leave the service alone
            }
            if (needed < (uint)Marshal.SizeOf(typeof(QUERY_SERVICE_CONFIG)))
                return true;
            IntPtr buf = Marshal.AllocHGlobal((int)needed);
            try
            {
                uint n;
                if (!QueryServiceConfig(hService, buf, needed, out n))
                    return true;
                var cfg = (QUERY_SERVICE_CONFIG)Marshal.PtrToStructure(buf, typeof(QUERY_SERVICE_CONFIG));
                string binPath = Marshal.PtrToStringUni(cfg.lpBinaryPathName);
                if (string.IsNullOrEmpty(binPath))
                    return true;
                // Convert an NT path like "\??\C:\...\WinDivert64.sys" to a normal drive path.
                string p = binPath;
                if (p.StartsWith("\\??\\", StringComparison.OrdinalIgnoreCase))
                    p = p.Substring(4);
                else if (p.StartsWith("\\\\.\\", StringComparison.OrdinalIgnoreCase))
                    p = p.Substring(4);
                return File.Exists(p);
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        private static bool ExtractResource(string resName, string dest, string httpName)
        {
            if (File.Exists(dest))
                return true;
            try
            {
                var asm = Assembly.GetExecutingAssembly();
                using (var s = asm.GetManifestResourceStream(resName))
                {
                    if (s == null)
                        return Download(httpName, dest);   // not embedded -> try release asset
                    Directory.CreateDirectory(Settings.SettingsDir);
                    using (var outS = new FileStream(dest, FileMode.Create, FileAccess.Write))
                        s.CopyTo(outS);
                    return true;
                }
            }
            catch
            {
                CleanupPartial(dest);
                return false;
            }
        }

        private static bool Download(string fileName, string dest)
        {
            if (File.Exists(dest))
                return true;
            try
            {
                Directory.CreateDirectory(Settings.SettingsDir);
                var req = (HttpWebRequest)WebRequest.Create(BaseUrl + fileName);
                req.UserAgent = "PrisonLifeMacro-DriverInstaller";
                req.Timeout = 10000;
                req.ReadWriteTimeout = 20000;
                using (var resp = (HttpWebResponse)req.GetResponse())
                using (var inS = resp.GetResponseStream())
                using (var outS = new FileStream(dest, FileMode.Create, FileAccess.Write))
                {
                    inS.CopyTo(outS);
                }
                return true;
            }
            catch
            {
                CleanupPartial(dest);
                return false;
            }
        }

        private static void CleanupPartial(string dest)
        {
            try
            {
                if (File.Exists(dest))
                    File.Delete(dest);
            }
            catch { }
        }
    }
}

