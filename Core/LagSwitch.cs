using System;
using System.Collections.Generic;
using System.IO;
using System.Threading;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Faithful C# port of the LagSwitchMacro Worker: drops Roblox UDP packets
    /// through WinDivert (with periodic pulse windows so you don't disconnect),
    /// toggled by the Lag Switch hotkey while Roblox is focused.
    /// </summary>
    public sealed class LagSwitch
    {
        public const int NetworkLayer = 0;
        public const int MaxMtu = 40 + 0xFFFF;

        private static readonly string RobloxRangeFilter =
            "((ip.SrcAddr >= 128.116.0.0 and ip.SrcAddr <= 128.116.255.255) or " +
            "(ip.DstAddr >= 128.116.0.0 and ip.DstAddr <= 128.116.255.255))";

        private readonly object _lock = new object();
        private readonly HashSet<string> _dynamicIps = new HashSet<string>();
        private volatile bool _running;
        private volatile bool _active;
        private Thread _captureThread;
        private Thread _scanThread;
        private long _activeStartTick;
        private const long IntervalMs = 19900;
        private const long PulseWindowMs = 250;

        public event Action<string> Status;

        public bool Active { get { return _active; } }

        public void Start()
        {
            if (_running)
                return;
            // Re-extract every start in case antivirus removed the drivers.
            DriverInstaller.EnsureInstalled();
            if (!Native.LoadWinDivert(DriverInstaller.DllPath))
            {
                RaiseStatus("Lag Switch unavailable - antivirus may have blocked the drivers");
                return;
            }
            _running = true;
            _captureThread = new Thread(CaptureLoop) { IsBackground = true, Name = "LagSwitchCapture" };
            _captureThread.Start();
            _scanThread = new Thread(ScanLoop) { IsBackground = true, Name = "LagSwitchLogScan" };
            _scanThread.Start();
        }

        public void Stop()
        {
            _running = false;
            _active = false;
        }

        public void SetActive(bool active)
        {
            _active = active;
            if (active)
                Interlocked.Exchange(ref _activeStartTick, Environment.TickCount);
        }

        public void Toggle()
        {
            SetActive(!_active);
        }

        private string BuildFilter()
        {
            string f = RobloxRangeFilter;
            lock (_lock)
            {
                if (_dynamicIps.Count > 0)
                {
                    var parts = new List<string> { RobloxRangeFilter };
                    foreach (var ip in _dynamicIps)
                        parts.Add("(ip.SrcAddr == " + ip + " or ip.DstAddr == " + ip + ")");
                    f = "(" + string.Join(" or ", parts) + ")";
                }
            }
            return "(inbound or outbound) and udp and " + f;
        }

        private void CaptureLoop()
        {
            var packet = new byte[MaxMtu];
            // WinDivert looks for the .sys in the working directory, so point it
            // at the settings folder where the drivers live.
            try { Environment.CurrentDirectory = Settings.SettingsDir; } catch { }
            while (_running)
            {
                string filter = BuildFilter();
                IntPtr handle = Native.WinDivertOpen(filter);
                if (handle == IntPtr.Zero || handle == (IntPtr)Native.WinDivertInvalidHandleValue)
                {
                    int err = System.Runtime.InteropServices.Marshal.GetLastWin32Error();
                    RaiseStatus(err == 5 ? "Lag Switch needs Admin rights" : "Lag Switch error " + err);
                    Thread.Sleep(1000);
                    continue;
                }

                RaiseStatus("Lag Switch ready");
                while (_running)
                {
                    uint recvLen = 0;
                    var addr = new Native.WINDIVERT_ADDRESS();
                    if (!Native.WinDivertRecv(handle, packet, (uint)packet.Length, ref recvLen, ref addr))
                        break;

                    if (!_active)
                    {
                        uint writeLen = 0;
                        Native.WinDivertSend(handle, packet, recvLen, ref writeLen, ref addr);
                        continue;
                    }

                    if (ShouldPulse())
                    {
                        uint writeLen = 0;
                        Native.WinDivertSend(handle, packet, recvLen, ref writeLen, ref addr);
                    }
                }

                Native.WinDivertClose(handle);
                if (_running)
                    Thread.Sleep(200);
            }
        }

        private bool ShouldPulse()
        {
            long start = Interlocked.Read(ref _activeStartTick);
            if (start == 0)
                return false;
            long elapsed = Environment.TickCount - start;
            long cycle = IntervalMs + PulseWindowMs;
            long pos = elapsed % cycle;
            return pos >= IntervalMs;
        }

        // ---------------- Roblox log IP scanner ----------------
        private void ScanLoop()
        {
            while (_running)
            {
                try
                {
                    string logsFolder = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Roblox", "logs");
                    if (Directory.Exists(logsFolder))
                    {
                        string newest = FindNewestLog(logsFolder);
                        if (newest != null)
                            ParseLog(newest);
                    }
                }
                catch { }
                Thread.Sleep(1000);
            }
        }

        private static string FindNewestLog(string folder)
        {
            string newest = null;
            DateTime newestTime = default(DateTime);
            try
            {
                foreach (var f in Directory.GetFiles(folder, "*.log"))
                {
                    DateTime mt = File.GetLastWriteTime(f);
                    if (newest == null || mt > newestTime)
                    {
                        newest = f;
                        newestTime = mt;
                    }
                }
            }
            catch { }
            return newest;
        }

        private void ParseLog(string path)
        {
            try
            {
                string[] lines = File.ReadAllLines(path);
                int startIdx = Math.Max(0, lines.Length - 200);
                for (int i = startIdx; i < lines.Length; i++)
                {
                    string line = lines[i];
                    if (line.IndexOf("GameIp:", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        line.IndexOf("ServerIP:", StringComparison.OrdinalIgnoreCase) >= 0 ||
                        line.IndexOf("UDMUX", StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        foreach (var part in line.Split(new[] { ' ', '\t' }, StringSplitOptions.RemoveEmptyEntries))
                        {
                            if (IsValidRobloxIp(part))
                            {
                                lock (_lock) _dynamicIps.Add(part);
                            }
                        }
                    }
                }
            }
            catch { }
        }

        private static bool IsValidRobloxIp(string s)
        {
            if (string.IsNullOrEmpty(s) || !s.Contains("."))
                return false;
            string[] parts = s.Split('.');
            if (parts.Length != 4)
                return false;
            var nums = new int[4];
            for (int i = 0; i < 4; i++)
            {
                int n;
                if (!int.TryParse(parts[i], out n) || n < 0 || n > 255)
                    return false;
                nums[i] = n;
            }
            if (nums[0] == 0 || nums[0] == 127 || nums[0] == 10)
                return false;
            if (nums[0] == 192 && nums[1] == 168)
                return false;
            if (nums[0] == 172 && nums[1] >= 16 && nums[1] <= 31)
                return false;
            return true;
        }

        private void RaiseStatus(string text)
        {
            var s = Status;
            if (s != null)
            {
                try { s(text); } catch { }
            }
        }
    }
}
