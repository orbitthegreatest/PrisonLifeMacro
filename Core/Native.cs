using System;
using System.Runtime.InteropServices;

namespace PrisonLifeMacro.Core
{
    public static class Native
    {
        // ---------------- timeBeginPeriod ----------------
        [DllImport("winmm.dll")]
        public static extern uint timeBeginPeriod(uint uMilliseconds);
        [DllImport("winmm.dll")]
        public static extern uint timeEndPeriod(uint uMilliseconds);

        // ---------------- SendInput ----------------
        [StructLayout(LayoutKind.Sequential)]
        private struct INPUT
        {
            public uint type;
            public INPUTUNION U;
        }

        [StructLayout(LayoutKind.Explicit)]
        private struct INPUTUNION
        {
            [FieldOffset(0)] public KEYBDINPUT ki;
            [FieldOffset(0)] public MOUSEINPUT mi;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct KEYBDINPUT
        {
            public ushort wVk;
            public ushort wScan;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MOUSEINPUT
        {
            public int dx;
            public int dy;
            public uint mouseData;
            public uint dwFlags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        private const uint INPUT_MOUSE = 0;
        private const uint INPUT_KEYBOARD = 1;
        private const uint KEYEVENTF_EXTENDEDKEY = 0x0001;
        private const uint KEYEVENTF_KEYUP = 0x0002;

        [DllImport("user32.dll", SetLastError = true)]
        private static extern uint SendInput(uint nInputs, ref INPUT pInputs, int cbSize);
        [DllImport("user32.dll")]
        private static extern uint MapVirtualKey(uint uCode, uint uMapType);

        private const uint MAPVK_VK_TO_VSC = 0;

        private static bool IsExtendedKey(int vk)
        {
            switch (vk)
            {
                case 0x0D:      // NumpadEnter (Enter itself is not extended)
                case 0x21:      // PgUp
                case 0x22:      // PgDn
                case 0x23:      // End
                case 0x24:      // Home
                case 0x25:      // Left
                case 0x26:      // Up
                case 0x27:      // Right
                case 0x28:      // Down
                case 0x2D:      // Insert
                case 0x2E:      // Delete
                case 0x5C:      // RWin
                case 0x5D:      // AppsKey
                case 0x6F:      // NumpadDiv
                case 0xA3:      // RCtrl
                case 0xA5:      // RAlt
                    return true;
                default:
                    return false;
            }
        }

        private static void SendKeyEvent(int vk, bool down)
        {
            ushort scan = (ushort)(MapVirtualKey((uint)vk, MAPVK_VK_TO_VSC) & 0xFF);
            INPUT inp = new INPUT();
            inp.type = INPUT_KEYBOARD;
            inp.U.ki.wVk = (ushort)vk;                       // AHK parity: VK+scan, no SCANCODE flag
            inp.U.ki.wScan = scan;
            inp.U.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
            if (IsExtendedKey(vk))
                inp.U.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
            if (SendInput(1, ref inp, Marshal.SizeOf(typeof(INPUT))) == 0)
                LogSendInputFailure("vk=0x" + vk.ToString("X") + (down ? " down" : " up"), Marshal.GetLastWin32Error());
        }

        private static void LogSendInputFailure(string what, int lastError)
        {
            try
            {
                string dir = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PrisonLifeMacro");
                System.IO.Directory.CreateDirectory(dir);
                System.IO.File.AppendAllText(System.IO.Path.Combine(dir, "error.log"),
                    DateTime.Now.ToString("yyyy-MM-dd HH:mm:ss") + " [SendInput] " + what + " failed, GetLastError=" + lastError + "\r\n");
            }
            catch { }
        }

        /// <summary>Press+release a key by VK code. Modifiers currently held are left untouched ("Blind").</summary>
        public static void SendKeyTap(int vk)
        {
            SendKeyEvent(vk, true);
            SendKeyEvent(vk, false);
        }

        public static void SendKeyDown(int vk) { SendKeyEvent(vk, true); }
        public static void SendKeyUp(int vk) { SendKeyEvent(vk, false); }

        // ---------------- mouse_event ----------------
        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_MOVE = 0x0001;

        /// <summary>Left click at the current cursor position (SendInput, AHK "Click" parity).</summary>
        public static void Click()
        {
            SendMouseEvent(MOUSEEVENTF_LEFTDOWN, 0);
            SendMouseEvent(MOUSEEVENTF_LEFTUP, 0);
        }

        private static void SendMouseEvent(uint flags, uint mouseData)
        {
            INPUT inp = new INPUT();
            inp.type = INPUT_MOUSE;
            inp.U.mi.dwFlags = flags;
            inp.U.mi.mouseData = mouseData;
            if (SendInput(1, ref inp, Marshal.SizeOf(typeof(INPUT))) == 0)
                LogSendInputFailure("mouse flags=0x" + flags.ToString("X"), Marshal.GetLastWin32Error());
        }

        /// <summary>Relative synthetic mouse move (unaffected by physical DPI).</summary>
        public static void MoveMouse(int dx, int dy)
        {
            mouse_event(MOUSEEVENTF_MOVE, dx, dy, 0, UIntPtr.Zero);
        }

        // ---------------- key state / focus ----------------
        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);

        [DllImport("user32.dll")]
        private static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")]
        private static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
        [DllImport("psapi.dll", CharSet = CharSet.Unicode)]
        private static extern int GetModuleBaseName(IntPtr hProcess, IntPtr hModule, System.Text.StringBuilder lpBaseName, uint nSize);
        [DllImport("kernel32.dll")]
        private static extern IntPtr OpenProcess(uint dwDesiredAccess, bool bInheritHandle, uint dwProcessId);
        [DllImport("kernel32.dll")]
        private static extern bool CloseHandle(IntPtr hObject);
        [DllImport("ntdll.dll")]
        private static extern int NtSuspendProcess(IntPtr hProcess);
        [DllImport("ntdll.dll")]
        private static extern int NtResumeProcess(IntPtr hProcess);

        private const uint PROCESS_ALL_ACCESS = 0x1F0FFF;

        /// <summary>True when the given process name owns the foreground window.</summary>
        public static bool IsProcessFocused(string processName)
        {
            IntPtr hwnd = GetForegroundWindow();
            if (hwnd == IntPtr.Zero)
                return false;
            uint pid;
            GetWindowThreadProcessId(hwnd, out pid);
            if (pid == 0)
                return false;
            IntPtr hProc = OpenProcess(0x0400 | 0x0010, false, pid);   // PROCESS_QUERY_INFORMATION | PROCESS_VM_READ
            if (hProc == IntPtr.Zero)
                return false;
            var sb = new System.Text.StringBuilder(260);
            GetModuleBaseName(hProc, IntPtr.Zero, sb, 260);
            CloseHandle(hProc);
            return string.Equals(sb.ToString(), processName, StringComparison.OrdinalIgnoreCase);
        }

        public static void SuspendProcessByName(string processName)
        {
            var procs = System.Diagnostics.Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(processName));
            foreach (var p in procs)
            {
                try
                {
                    IntPtr h = OpenProcess(PROCESS_ALL_ACCESS, false, (uint)p.Id);
                    if (h != IntPtr.Zero)
                    {
                        NtSuspendProcess(h);
                        CloseHandle(h);
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
        }

        public static void ResumeProcessByName(string processName)
        {
            var procs = System.Diagnostics.Process.GetProcessesByName(System.IO.Path.GetFileNameWithoutExtension(processName));
            foreach (var p in procs)
            {
                try
                {
                    IntPtr h = OpenProcess(PROCESS_ALL_ACCESS, false, (uint)p.Id);
                    if (h != IntPtr.Zero)
                    {
                        NtResumeProcess(h);
                        CloseHandle(h);
                    }
                }
                catch { }
                finally { p.Dispose(); }
            }
        }
    }
}