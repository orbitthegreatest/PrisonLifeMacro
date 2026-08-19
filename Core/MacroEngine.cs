using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Faithful port of the AHK macro suite. Routing decisions run on the hook
    /// thread (must be fast); macro bodies run serialized on one action thread
    /// (mirroring AHK's single hotkey thread).
    ///
    /// Focus rules (AHK parity):
    ///   - Macro hotkeys only fire while RobloxPlayerBeta.exe is focused.
    ///   - The Global Suspend key and keybind capture work from any window.
    ///   - Keys with "~" semantics pass through to the game; consumed keys
    ///     (PJ, Freeze, Sprint, Suspend) are blocked from reaching the game.
    /// </summary>
    public sealed class MacroEngine
    {
        public const string TargetProcess = "RobloxPlayerBeta.exe";

        // Fixed constants (AHK parity)
        private const double Spin = 5000;
        private const double BaseCS = 0.36;
        private const int RotationFlickDegrees = 179;
        private const int RotationWallhopLengthMs = 19;
        private const int RotationBonusDelayMs = 0;
        private const bool RotationLeftFlick = false;
        private const bool RotationJumpDuring = false;
        private const bool RotationFlickBack = false;

        // Runtime state (read/written from hook + action threads)
        public volatile bool GlobalSuspended;
        public volatile bool FastGunSwapOn;
        public volatile bool FastGunSwapHolding;
        public volatile bool SprintHeld;
        public volatile bool Frozen;
        public volatile bool Capturing;
        public string CaptureTarget;

        public int X = 7200;
        public int RotX = 2977;

        private readonly BlockingCollection<Action> _actions = new BlockingCollection<Action>();
        private readonly Thread _actionThread;
        private readonly Dictionary<int, bool> _prevDown = new Dictionary<int, bool>();
        private readonly object _prevLock = new object();
        private Timer _focusTimer;
        private long _lastSuspendToggleTick;

        public event Action<string> Feedback;
        public event Action<string> Captured;

        public MacroEngine()
        {
            _actionThread = new Thread(() =>
            {
                foreach (var a in _actions.GetConsumingEnumerable())
                {
                    try { a(); } catch { }
                }
            })
            { IsBackground = true, Name = "MacroActionThread" };
            _actionThread.Start();

            _focusTimer = new Timer(_ => WatchFocus(), null, 300, 300);
            RecalculatePixels();
        }

        public void Shutdown()
        {
            _focusTimer.Dispose();
            if (Frozen)
            {
                Frozen = false;
                Native.ResumeProcessByName(TargetProcess);
            }
            if (SprintHeld)
            {
                SprintHeld = false;
                Native.SendKeyUp(0xA0);
            }
            FastGunSwapHolding = false;
            _actions.CompleteAdding();
        }

        public void RecalculatePixels()
        {
            double cs = Settings.CS > 0 ? Settings.CS : 0.01;
            X = (int)Math.Round((Spin * BaseCS) / cs);
            RotX = (int)Math.Round(RotationFlickDegrees * 720.0 / (360.0 * cs));
        }

        public void BeginCapture(string target)
        {
            Capturing = true;
            CaptureTarget = target;
        }

        /// <summary>Manual suspend/resume toggle (tray menu item).</summary>
        public void ToggleSuspendFromUi()
        {
            Post(ToggleSuspend);
        }

        // ------------------------------------------------------------------
        // Hook-thread entry: returns true when the event must be blocked.
        // ------------------------------------------------------------------
        public bool OnKeyEvent(int vk, bool down, bool up, bool extended)
        {
            bool repeat = false;
            lock (_prevLock)
            {
                bool wasDown = _prevDown.ContainsKey(vk) && _prevDown[vk];
                if (down)
                {
                    if (wasDown)
                        repeat = true;
                    else
                        _prevDown[vk] = true;
                }
                else
                {
                    _prevDown[vk] = false;
                }
            }

            // ---- Keybind capture: works from any window, blocks everything ----
            if (Capturing)
            {
                if (down && !repeat)
                {
                    string name = KeyNames.VkToName(vk, extended);
                    Capturing = false;
                    if (name == "Escape")
                        name = null;
                    var captured = name;
                    Captured?.Invoke(captured);
                }
                return true;
            }

            // ---- Global suspend key: works from any window, blocks the key ----
            if (!string.IsNullOrEmpty(Settings.GlobalSuspendKey))
            {
                int svk = KeyNames.NameToVk(Settings.GlobalSuspendKey);
                if (vk == svk)
                {
                    if (up && !repeat)
                        Post(() => ToggleSuspend());
                    return true;
                }
            }

            if (GlobalSuspended)
                return false;                       // everything passes through

            if (!Native.IsProcessFocused(TargetProcess))
                return false;                       // macros only work while Roblox is focused

            // ---- Pressure Jump (consumed) ----
            if (Settings.PressureJumpEnabled && !string.IsNullOrEmpty(Settings.PressureJumpKey) &&
                vk == KeyNames.NameToVk(Settings.PressureJumpKey))
            {
                if (down && !repeat) Post(PressureJumpAction);
                return true;
            }

            // ---- Freeze (consumed) ----
            if (Settings.FreezeEnabled && !string.IsNullOrEmpty(Settings.FreezeKey) &&
                vk == KeyNames.NameToVk(Settings.FreezeKey))
            {
                if (Settings.FreezeMode == "Hold")
                {
                    if (down && !repeat) Post(FreezeHoldDown);
                    if (up) Post(FreezeHoldUp);
                }
                else
                {
                    if (down && !repeat) Post(ToggleFreeze);
                }
                return true;
            }

            // ---- Rotation (pass-through) ----
            if (Settings.RotationEnabled && !string.IsNullOrEmpty(Settings.RotationKey) &&
                vk == KeyNames.NameToVk(Settings.RotationKey))
            {
                if (down && !repeat) Post(RotationAction);
                return false;
            }

            // ---- Sprint (Shift, consumed) ----
            if (Settings.SprintEnabled && (vk == 0xA0 || vk == 0xA1))
            {
                if (down && !repeat) Post(ToggleSprint);
                return true;
            }

            // ---- Fast Gun Swap (pass-through) ----
            if (Settings.FastGunSwapEnabled && !string.IsNullOrEmpty(Settings.FastGunSwapKey) &&
                vk == KeyNames.NameToVk(Settings.FastGunSwapKey))
            {
                if (Settings.FastGunSwapMode == "Hold")
                {
                    if (down && !repeat) Post(() => FastGunSwapHoldStart(Settings.FastGunSwapKey));
                }
                else
                {
                    if (down && !repeat) Post(FastGunSwapToggle);
                }
                return false;
            }

            // ---- Fast Gun Swap On/Off (pass-through) ----
            if (Settings.FastGunSwapEnabled && !string.IsNullOrEmpty(Settings.FastGunSwapOnOffKey) &&
                vk == KeyNames.NameToVk(Settings.FastGunSwapOnOffKey))
            {
                if (down && !repeat) Post(FastGunSwapOnOffToggle);
                return false;
            }

            // ---- Shuffle Reload (pass-through) ----
            if (Settings.ShuffleReloadEnabled && !string.IsNullOrEmpty(Settings.ShuffleReloadKey) &&
                vk == KeyNames.NameToVk(Settings.ShuffleReloadKey))
            {
                if (down && !repeat) Post(ShuffleReloadAction);
                return false;
            }

            // ---- Main Gun Slots +/- (pass-through) ----
            if (!string.IsNullOrEmpty(Settings.IncreaseSlotKey) && vk == KeyNames.NameToVk(Settings.IncreaseSlotKey))
            {
                if (down && !repeat) Post(() => ChangeSlotCount(+1));
                return false;
            }
            if (!string.IsNullOrEmpty(Settings.DecreaseSlotKey) && vk == KeyNames.NameToVk(Settings.DecreaseSlotKey))
            {
                if (down && !repeat) Post(() => ChangeSlotCount(-1));
                return false;
            }

            return false;
        }

        private void Post(Action a)
        {
            try { _actions.Add(a); } catch { }
        }

        private void ShowFeedback(string text, int ms = 1500)
        {
            var f = Feedback;
            if (f != null)
            {
                try { f(text); } catch { }
            }
        }

        // ------------------------------------------------------------------
        // Pressure Jump
        // ------------------------------------------------------------------
        private void PressureJumpAction()
        {
            Native.SendKeyTap(0x43);                       // c
            Thread.Sleep(6);
            Native.SendKeyDown(0x20);                      // Space down
            Thread.Sleep(50);
            Native.SendKeyUp(0x20);                        // Space up
            Thread.Sleep(4);

            long start = Environment.TickCount;
            while (Environment.TickCount - start <= 200)
            {
                Native.MoveMouse(X, 0);
                Thread.Sleep(4);
            }
        }

        // ------------------------------------------------------------------
        // Freeze
        // ------------------------------------------------------------------
        private void ToggleFreeze()
        {
            if (Frozen)
            {
                Frozen = false;
                Native.ResumeProcessByName(TargetProcess);
            }
            else
            {
                Frozen = true;
                Native.SuspendProcessByName(TargetProcess);
            }
        }

        private void FreezeHoldDown()
        {
            if (!Frozen)
            {
                Frozen = true;
                Native.SuspendProcessByName(TargetProcess);
            }
        }

        private void FreezeHoldUp()
        {
            if (Frozen)
            {
                Frozen = false;
                Native.ResumeProcessByName(TargetProcess);
            }
        }

        // ------------------------------------------------------------------
        // Rotation (wallhop flick)
        // ------------------------------------------------------------------
        private void RotationAction()
        {
            RecalculatePixels();
            int dx = RotationLeftFlick ? -RotX : RotX;
            Native.MoveMouse(dx, 0);

            if (RotationFlickBack)
            {
                if (RotationBonusDelayMs > 0 && RotationBonusDelayMs < RotationWallhopLengthMs)
                {
                    Thread.Sleep(RotationBonusDelayMs);
                    if (RotationJumpDuring) Native.SendKeyDown(KeyNames.NameToVk("Space"));
                    Thread.Sleep(RotationWallhopLengthMs - RotationBonusDelayMs);
                }
                else
                {
                    if (RotationJumpDuring) Native.SendKeyDown(KeyNames.NameToVk("Space"));
                    Thread.Sleep(RotationWallhopLengthMs);
                }
                Native.MoveMouse(dx, 0);
            }
            else if (RotationJumpDuring)
            {
                Native.SendKeyDown(KeyNames.NameToVk("Space"));
            }

            if (RotationJumpDuring)
            {
                int remaining = 100 - RotationWallhopLengthMs;
                if (remaining > 0) Thread.Sleep(remaining);
                Native.SendKeyUp(KeyNames.NameToVk("Space"));
            }
        }

        // ------------------------------------------------------------------
        // Sprint
        // ------------------------------------------------------------------
        private void ToggleSprint()
        {
            if (SprintHeld)
            {
                SprintHeld = false;
                Native.SendKeyUp(0xA0);
            }
            else
            {
                SprintHeld = true;
                Native.SendKeyDown(0xA0);
            }
        }

        private void WatchFocus()
        {
            if (SprintHeld && !Native.IsProcessFocused(TargetProcess))
            {
                SprintHeld = false;
                Native.SendKeyUp(0xA0);
            }
        }

        // ------------------------------------------------------------------
        // Main Gun Slots (shared)
        // ------------------------------------------------------------------
        private static List<int> BuildActiveSlots()
        {
            int count = Settings.GunSlotCount;
            if (count < 1) count = 1;
            if (count > 10) count = 10;
            var slots = new List<int>(count);
            for (int i = 1; i <= count; i++)
                slots.Add(i == 10 ? 0x30 : 0x30 + i);     // '1'..'9', '0'
            return slots;
        }

        private void ChangeSlotCount(int delta)
        {
            int n = Settings.GunSlotCount + delta;
            if (n < 1) n = 1;
            if (n > 10) n = 10;
            Settings.GunSlotCount = n;
            ShowFeedback("Main Gun Slots: " + n);
        }

        // ------------------------------------------------------------------
        // Fast Gun Swap
        // ------------------------------------------------------------------
        private void FastGunSwapOnOffToggle()
        {
            FastGunSwapOn = !FastGunSwapOn;
            if (!FastGunSwapOn)
                FastGunSwapHolding = false;
            ShowFeedback("Fast Gun Swap: " + (FastGunSwapOn ? "ON" : "OFF"));
        }

        private void FastGunSwapHoldStart(string keyName)
        {
            int keyVk = KeyNames.NameToVk(keyName);
            if (keyVk == 0 || !FastGunSwapOn)
                return;
            var slots = BuildActiveSlots();
            if (slots.Count == 0)
                return;
            while ((Native.GetAsyncKeyState(keyVk) & 0x8000) != 0)
            {
                if (!Settings.FastGunSwapEnabled || !FastGunSwapOn || GlobalSuspended)
                    break;
                foreach (var k in slots)
                {
                    if ((Native.GetAsyncKeyState(keyVk) & 0x8000) == 0)
                        break;
                    Native.SendKeyTap(k);
                    Thread.Sleep(1);
                    Native.Click();
                    Thread.Sleep(1);
                }
            }
        }

        private void FastGunSwapToggle()
        {
            if (!FastGunSwapOn)
                return;
            FastGunSwapHolding = !FastGunSwapHolding;
            if (FastGunSwapHolding)
                Post(FastGunSwapLoop);
        }

        private void FastGunSwapLoop()
        {
            if (!FastGunSwapHolding || !Settings.FastGunSwapEnabled || !FastGunSwapOn || GlobalSuspended)
            {
                FastGunSwapHolding = false;
                return;
            }
            var slots = BuildActiveSlots();
            foreach (var k in slots)
            {
                if (!FastGunSwapHolding)
                    break;
                Native.SendKeyTap(k);
                Thread.Sleep(1);
                Native.Click();
                Thread.Sleep(1);
            }
            if (FastGunSwapHolding)
                Post(FastGunSwapLoop);
        }

        // ------------------------------------------------------------------
        // Shuffle Reload
        // ------------------------------------------------------------------
        private void ShuffleReloadAction()
        {
            if (!ShuffleReloadEnabledOk())
                return;
            var slots = BuildActiveSlots();
            foreach (var k in slots)
            {
                Native.SendKeyTap(k);
                Native.SendKeyTap(0x52);                 // r
            }
        }

        private static bool ShuffleReloadEnabledOk()
        {
            return Settings.ShuffleReloadEnabled && !string.IsNullOrEmpty(Settings.ShuffleReloadKey);
        }

        // ------------------------------------------------------------------
        // Global Suspend / Resume
        // ------------------------------------------------------------------
        private void ToggleSuspend()
        {
            // Debounce (AHK parity: modifiers can double-fire on one press).
            long now = Environment.TickCount;
            if (now - Interlocked.Read(ref _lastSuspendToggleTick) < 250)
                return;
            Interlocked.Exchange(ref _lastSuspendToggleTick, now);

            if (GlobalSuspended)
            {
                GlobalSuspended = false;
                ShowFeedback("All macros resumed");
            }
            else
            {
                GlobalSuspended = true;
                if (SprintHeld)
                {
                    SprintHeld = false;
                    Native.SendKeyUp(0xA0);
                }
                if (Frozen)
                {
                    Frozen = false;
                    Native.ResumeProcessByName(TargetProcess);
                }
                FastGunSwapHolding = false;
                string key = string.IsNullOrEmpty(Settings.GlobalSuspendKey) ? "the suspend key" : Settings.GlobalSuspendKey;
                ShowFeedback("ALL MACROS SUSPENDED - press " + key + " to resume");
            }
        }
    }
}