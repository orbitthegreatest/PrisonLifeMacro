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
        private static extern uint SendInput(uint nInputs, [In] INPUT[] pInputs, int cbSize);
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

        private static bool SendInputBatch(INPUT[] inputs)
        {
            if (inputs == null || inputs.Length == 0) return true;
            return SendInput((uint)inputs.Length, inputs, Marshal.SizeOf(typeof(INPUT))) != 0;
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

        private static INPUT MakeKeyInput(int vk, bool down)
        {
            ushort scan = (ushort)(MapVirtualKey((uint)vk, MAPVK_VK_TO_VSC) & 0xFF);
            INPUT inp = new INPUT();
            inp.type = INPUT_KEYBOARD;
            inp.U.ki.wVk = (ushort)vk;
            inp.U.ki.wScan = scan;
            inp.U.ki.dwFlags = down ? 0 : KEYEVENTF_KEYUP;
            if (IsExtendedKey(vk))
                inp.U.ki.dwFlags |= KEYEVENTF_EXTENDEDKEY;
            return inp;
        }

        private static INPUT MakeMouseInput(uint flags)
        {
            INPUT inp = new INPUT();
            inp.type = INPUT_MOUSE;
            inp.U.mi.dwFlags = flags;
            return inp;
        }

        /// <summary>Press+release a key in a SINGLE atomic SendInput call (AHK "SendInput, {Blind}key" parity).</summary>
        public static void SendKeyTap(int vk)
        {
            INPUT[] batch = new INPUT[] { MakeKeyInput(vk, true), MakeKeyInput(vk, false) };
            if (!SendInputBatch(batch))
                LogSendInputFailure("SendKeyTap vk=0x" + vk.ToString("X"), System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }

        /// <summary>Send a sequence of key taps in ONE atomic SendInput call (AHK "SendInput, keys" parity).</summary>
        public static void SendKeyTapSequence(int[] vks)
        {
            if (vks == null || vks.Length == 0) return;
            INPUT[] batch = new INPUT[vks.Length * 2];
            for (int i = 0; i < vks.Length; i++)
            {
                batch[i * 2] = MakeKeyInput(vks[i], true);
                batch[i * 2 + 1] = MakeKeyInput(vks[i], false);
            }
            if (!SendInputBatch(batch))
                LogSendInputFailure("SendKeyTapSequence", System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }

        public static void SendKeyDown(int vk)
        {
            INPUT[] batch = new INPUT[] { MakeKeyInput(vk, true) };
            if (!SendInputBatch(batch))
                LogSendInputFailure("SendKeyDown vk=0x" + vk.ToString("X"), System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }

        public static void SendKeyUp(int vk)
        {
            INPUT[] batch = new INPUT[] { MakeKeyInput(vk, false) };
            if (!SendInputBatch(batch))
                LogSendInputFailure("SendKeyUp vk=0x" + vk.ToString("X"), System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }

        // ---------------- mouse_event ----------------
        [DllImport("user32.dll")]
        private static extern void mouse_event(uint dwFlags, int dx, int dy, uint dwData, UIntPtr dwExtraInfo);

        private const uint MOUSEEVENTF_LEFTDOWN = 0x0002;
        private const uint MOUSEEVENTF_LEFTUP = 0x0004;
        private const uint MOUSEEVENTF_MOVE = 0x0001;

        /// <summary>Left click at the current cursor position (SendInput, AHK "Click" parity).</summary>
        public static void Click()
        {
            INPUT[] batch = new INPUT[] { MakeMouseInput(MOUSEEVENTF_LEFTDOWN), MakeMouseInput(MOUSEEVENTF_LEFTUP) };
            if (!SendInputBatch(batch))
                LogSendInputFailure("Click", System.Runtime.InteropServices.Marshal.GetLastWin32Error());
        }

        public static void MouseDown(int button)
        {
            if (button == 0x01)
            {
                INPUT[] batch = new INPUT[] { MakeMouseInput(MOUSEEVENTF_LEFTDOWN) };
                if (!SendInputBatch(batch))
                    LogSendInputFailure("MouseDown", System.Runtime.InteropServices.Marshal.GetLastWin32Error());
            }
        }

        public static void MouseUp(int button)
        {
            if (button == 0x01)
            {
                INPUT[] batch = new INPUT[] { MakeMouseInput(MOUSEEVENTF_LEFTUP) };
                if (!SendInputBatch(batch))
                    LogSendInputFailure("MouseUp", System.Runtime.InteropServices.Marshal.GetLastWin32Error());
            }
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

        // ---------------- WinDivert (lag switch) ----------------
        [StructLayout(LayoutKind.Sequential)]
        public struct WINDIVERT_ADDRESS
        {
            public ulong Timestamp;
            public uint Flags;
            public uint Reserved2;
            public ulong Reserved3;
        }

        [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Ansi)]
        private static extern IntPtr LoadLibrary(string lpFileName);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr GetProcAddress(IntPtr hModule, string lpProcName);

        private delegate IntPtr WinDivertOpenDelegate(string filter, int layer, short priority, ulong flags);
        private delegate bool WinDivertRecvDelegate(IntPtr handle, byte[] packet, uint packetLen, ref uint recvLen, ref WINDIVERT_ADDRESS addr);
        private delegate bool WinDivertSendDelegate(IntPtr handle, byte[] packet, uint packetLen, ref uint writeLen, ref WINDIVERT_ADDRESS addr);
        private delegate bool WinDivertCloseDelegate(IntPtr handle);

        private static IntPtr _windivertModule;
        private static WinDivertOpenDelegate _wdOpen;
        private static WinDivertRecvDelegate _wdRecv;
        private static WinDivertSendDelegate _wdSend;
        private static WinDivertCloseDelegate _wdClose;

        /// <summary>Loads the SMCWinDivert.dll from the settings dir and binds the entry points.</summary>
        public static bool LoadWinDivert(string dllPath)
        {
            if (_windivertModule != IntPtr.Zero)
                return true;
            if (!System.IO.File.Exists(dllPath))
                return false;
            IntPtr h = LoadLibrary(dllPath);
            if (h == IntPtr.Zero)
                return false;
            var open = GetProcAddress(h, "WinDivertOpen");
            var recv = GetProcAddress(h, "WinDivertRecv");
            var send = GetProcAddress(h, "WinDivertSend");
            var close = GetProcAddress(h, "WinDivertClose");
            if (open == IntPtr.Zero || recv == IntPtr.Zero || send == IntPtr.Zero || close == IntPtr.Zero)
            {
                _windivertModule = IntPtr.Zero;
                return false;
            }
            _windivertModule = h;
            _wdOpen = (WinDivertOpenDelegate)Marshal.GetDelegateForFunctionPointer(open, typeof(WinDivertOpenDelegate));
            _wdRecv = (WinDivertRecvDelegate)Marshal.GetDelegateForFunctionPointer(recv, typeof(WinDivertRecvDelegate));
            _wdSend = (WinDivertSendDelegate)Marshal.GetDelegateForFunctionPointer(send, typeof(WinDivertSendDelegate));
            _wdClose = (WinDivertCloseDelegate)Marshal.GetDelegateForFunctionPointer(close, typeof(WinDivertCloseDelegate));
            return true;
        }

        public static IntPtr WinDivertOpen(string filter)
        {
            if (_wdOpen == null) return IntPtr.Zero;
            return _wdOpen(filter, 0, 0, 0);
        }

        public static bool WinDivertRecv(IntPtr handle, byte[] packet, uint packetLen, ref uint recvLen, ref WINDIVERT_ADDRESS addr)
        {
            if (_wdRecv == null) return false;
            return _wdRecv(handle, packet, packetLen, ref recvLen, ref addr);
        }

        public static bool WinDivertSend(IntPtr handle, byte[] packet, uint packetLen, ref uint writeLen, ref WINDIVERT_ADDRESS addr)
        {
            if (_wdSend == null) return false;
            return _wdSend(handle, packet, packetLen, ref writeLen, ref addr);
        }

        public static bool WinDivertClose(IntPtr handle)
        {
            if (_wdClose == null || handle == IntPtr.Zero) return true;
            return _wdClose(handle);
        }

        public const int WinDivertInvalidHandleValue = -1;
    }
}