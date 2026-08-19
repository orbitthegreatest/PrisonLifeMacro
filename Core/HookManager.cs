using System;
using System.Runtime.InteropServices;
using System.Threading;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Low-level keyboard + mouse hooks on a dedicated thread. Every key/button
    /// event is forwarded to MacroEngine, which decides whether to block it
    /// (return 1 from the hook) or let it pass through.
    /// </summary>
    public sealed class HookManager
    {
        private const int WH_KEYBOARD_LL = 13;
        private const int WH_MOUSE_LL = 14;
        private const int WM_QUIT = 0x0012;
        private const int WM_KEYDOWN = 0x0100;
        private const int WM_KEYUP = 0x0101;
        private const int WM_SYSKEYDOWN = 0x0104;
        private const int WM_SYSKEYUP = 0x0105;

        private const int WM_LBUTTONDOWN = 0x0201, WM_LBUTTONUP = 0x0202;
        private const int WM_RBUTTONDOWN = 0x0204, WM_RBUTTONUP = 0x0205;
        private const int WM_MBUTTONDOWN = 0x0207, WM_MBUTTONUP = 0x0208;
        private const int WM_XBUTTONDOWN = 0x020B, WM_XBUTTONUP = 0x020C;
        private const int WM_MOUSEWHEEL = 0x020A, WM_MOUSEHWHEEL = 0x020E;

        private const uint LLKHF_EXTENDED = 0x01;
        private const uint LLKHF_UP = 0x80;

        private delegate IntPtr HookProc(int nCode, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        private struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct MSLLHOOKSTRUCT
        {
            public int ptX;
            public int ptY;
            public uint mouseData;
            public uint flags;
            public uint time;
            public UIntPtr dwExtraInfo;
        }

        [DllImport("user32.dll")]
        private static extern IntPtr SetWindowsHookEx(int idHook, HookProc lpfn, IntPtr hMod, uint dwThreadId);
        [DllImport("user32.dll")]
        private static extern bool UnhookWindowsHookEx(IntPtr hhk);
        [DllImport("user32.dll")]
        private static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll")]
        private static extern IntPtr GetModuleHandle(string lpModuleName);
        [DllImport("user32.dll")]
        private static extern int GetMessage(out MSG lpMsg, IntPtr hWnd, uint wMsgFilterMin, uint wMsgFilterMax);
        [DllImport("user32.dll")]
        private static extern bool PostThreadMessage(uint idThread, uint msg, IntPtr wParam, IntPtr lParam);
        [DllImport("kernel32.dll")]
        private static extern uint GetCurrentThreadId();

        [StructLayout(LayoutKind.Sequential)]
        private struct MSG
        {
            public IntPtr hwnd;
            public uint message;
            public IntPtr wParam;
            public IntPtr lParam;
            public uint time;
            public int ptX;
            public int ptY;
        }

        private readonly MacroEngine _engine;
        private Thread _thread;
        private uint _threadId;
        private IntPtr _kHook = IntPtr.Zero;
        private IntPtr _mHook = IntPtr.Zero;
        private HookProc _kProc;
        private HookProc _mProc;

        public HookManager(MacroEngine engine)
        {
            _engine = engine;
        }

        public void Start()
        {
            _thread = new Thread(Run) { IsBackground = true, Name = "InputHookThread" };
            _thread.Start();
        }

        public void Stop()
        {
            if (_thread != null && _thread.IsAlive)
            {
                PostThreadMessage(_threadId, WM_QUIT, IntPtr.Zero, IntPtr.Zero);
                if (!_thread.Join(1500))
                    _thread.Abort();
            }
        }

        private void Run()
        {
            _kProc = KeyboardProc;
            _mProc = MouseProc;
            _threadId = GetCurrentThreadId();
            _kHook = SetWindowsHookEx(WH_KEYBOARD_LL, _kProc, GetModuleHandle(null), 0);
            _mHook = SetWindowsHookEx(WH_MOUSE_LL, _mProc, GetModuleHandle(null), 0);
            MSG msg;
            while (GetMessage(out msg, IntPtr.Zero, 0, 0) > 0) { }
            if (_kHook != IntPtr.Zero) UnhookWindowsHookEx(_kHook);
            if (_mHook != IntPtr.Zero) UnhookWindowsHookEx(_mHook);
        }

        private IntPtr KeyboardProc(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (nCode >= 0)
                {
                    var k = (KBDLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(KBDLLHOOKSTRUCT));
                    int vk = (int)k.vkCode;
                    bool up = (k.flags & LLKHF_UP) != 0;
                    bool extended = (k.flags & LLKHF_EXTENDED) != 0;
                    int msg = wParam.ToInt32();
                    bool down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
                    bool handled = _engine.OnKeyEvent(vk, down, up, extended);
                    if (handled)
                        return (IntPtr)1;
                }
            }
            catch { }
            return CallNextHookEx(_kHook, nCode, wParam, lParam);
        }

        private IntPtr MouseProc(int nCode, IntPtr wParam, IntPtr lParam)
        {
            try
            {
                if (nCode >= 0)
                {
                var m = (MSLLHOOKSTRUCT)Marshal.PtrToStructure(lParam, typeof(MSLLHOOKSTRUCT));
                int msg = wParam.ToInt32();
                int vk = 0;
                bool down = false;
                bool handled = false;

                switch (msg)
                {
                    case WM_LBUTTONDOWN: vk = 0x01; down = true; break;
                    case WM_LBUTTONUP: vk = 0x01; break;
                    case WM_RBUTTONDOWN: vk = 0x02; down = true; break;
                    case WM_RBUTTONUP: vk = 0x02; break;
                    case WM_MBUTTONDOWN: vk = 0x04; down = true; break;
                    case WM_MBUTTONUP: vk = 0x04; break;
                    case WM_XBUTTONDOWN: vk = (m.mouseData >> 16) == 1 ? 0x05 : 0x06; down = true; break;
                    case WM_XBUTTONUP: vk = (m.mouseData >> 16) == 1 ? 0x05 : 0x06; break;
                    case WM_MOUSEWHEEL:
                        vk = (short)(m.mouseData >> 16) > 0 ? KeyNames.WheelUpVk : KeyNames.WheelDownVk;
                        down = true;
                        handled = _engine.OnKeyEvent(vk, true, false, false);
                        if (handled) return (IntPtr)1;
                        return CallNextHookEx(_mHook, nCode, wParam, lParam);
                    case WM_MOUSEHWHEEL:
                        vk = (short)(m.mouseData >> 16) > 0 ? KeyNames.WheelRightVk : KeyNames.WheelLeftVk;
                        down = true;
                        handled = _engine.OnKeyEvent(vk, true, false, false);
                        if (handled) return (IntPtr)1;
                        return CallNextHookEx(_mHook, nCode, wParam, lParam);
                }

                if (vk != 0)
                {
                    handled = _engine.OnKeyEvent(vk, down, false, false);
                    if (handled)
                        return (IntPtr)1;
                }
            }
            }
            catch { }
            return CallNextHookEx(_mHook, nCode, wParam, lParam);
        }
    }
}