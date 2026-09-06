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
        private const bool RotationFlickBack = true;
        private const int RotationFlickBackDelayMs = 200;

        // Pressure Jump. The freeze branch uses the Speedglitch-style spin from
        // Spencer-Macro-Utilities: per-move pixel is sensitivity-driven and it alternates
        // +pix / -pix once per Roblox frame (see RecalculatePixels / FrameDelayMs).

        // Shuffle Reload (fixed): r, 35ms, slot, 4ms, r, 4ms, slot, 4ms, r...
        private const int ShuffleReloadInitialDelayMs = 35;
        private const int ShuffleReloadKeyDelayMs = 4;

        // Safety: drop new actions when the queue backs up (injected-event flood).
        private const int MaxPendingActions = 64;
        private int _pendingActions;

        // Runtime state (read/written from hook + action threads)
        public volatile bool GlobalSuspended;
        public volatile bool FastGunSwapOn;
        public volatile bool FastGunSwapHolding;
        public volatile bool SprintHeld;
        private volatile bool _wasProcessFocused;
        public volatile bool Frozen;
        public volatile bool Capturing;
        public volatile bool SmartCrouchActive;
        public volatile bool AutoComboOn;
        public volatile bool AutoComboHolding;
        public string CaptureTarget;

        private int _smartCrouchPressCount;

        public readonly LagSwitch LagSwitch;

        public int X = 7200;
        public int RotX = 2977;
        public int PJumpPix = 959;  // Freeze branch: Speedglitch per-move pixel (360/sens)

        private readonly BlockingCollection<Action> _actions = new BlockingCollection<Action>();
        private readonly Thread _actionThread;
        private readonly Dictionary<int, bool> _prevDown = new Dictionary<int, bool>();
        private readonly object _prevLock = new object();
        private readonly HashSet<int> _physDown = new HashSet<int>();
        private readonly object _physLock = new object();
        private Timer _focusTimer;
        private long _lastSuspendToggleTick;

        public event Action<string> Feedback;
        public event Action<string> Captured;

        public MacroEngine()
        {
            LagSwitch = new LagSwitch();
            _actionThread = new Thread(() =>
            {
                foreach (var a in _actions.GetConsumingEnumerable())
                {
                    Interlocked.Decrement(ref _pendingActions);
                    try { a(); } catch { }
                }
            })
            { IsBackground = true, Name = "MacroActionThread" };
            _actionThread.Start();

            _focusTimer = new Timer(_ => WatchFocus(), null, 300, 300);
            RecalculatePixels();
            if (Settings.SprintEnabled && Settings.SprintMode == "Always")
                PostDelayed(AlwaysSprintLoop, 300);
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
                Native.SendKeyUp(0x10);
            }
            FastGunSwapHolding = false;
            AutoComboHolding = false;
            LagSwitch.Stop();
            lock (_physLock) _physDown.Clear();
            _actions.CompleteAdding();
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern uint GetDpiForSystem();

        private static double GetDpiScale()
        {
            try { return GetDpiForSystem() / 96.0; }
            catch { return 1.0; }
        }

        public void RecalculatePixels()
        {
            double cs = Settings.CS > 0 ? Settings.CS : 0.01;
            double dpi = GetDpiScale();
            X = (int)Math.Round((Spin * BaseCS) / cs * dpi);
            RotX = (int)Math.Round(RotationFlickDegrees * 720.0 / (360.0 * cs) * dpi);
            // Speedglitch parity (Spencer-Macro-Utilities app_ui.cpp):
            //   speedBase = 360;  Pix = Round((360 / sens) * (359/360) * (359/360))
            PJumpPix = (int)Math.Round((360.0 / cs) * (359.0 / 360.0) * (359.0 / 360.0) * dpi);
        }

        // Speedglitch parity (macro_runtime.cpp FrameDelaysForFps): one Roblox frame in ms.
        private static int FrameDelayMs()
        {
            double fps = Settings.FPS > 0 ? Settings.FPS : 1.0;
            return Math.Max(1, (int)(1000.0 / fps));
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
            // Track the physical state of real keys/buttons (wheel pseudo-VKs excluded).
            // Injected input never reaches this point (the hook skips it), so this set
            // is a reliable "is the user physically holding it" flag for Hold-mode loops.
            if (vk < KeyNames.WheelUpVk)
            {
                lock (_physLock)
                {
                    if (down) _physDown.Add(vk);
                    else _physDown.Remove(vk);
                }
            }

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

            // ---- Clip (consumed) ----
            if (Settings.ClipEnabled && !string.IsNullOrEmpty(Settings.ClipKey) &&
                vk == KeyNames.NameToVk(Settings.ClipKey))
            {
                if (down && !repeat) Post(ClipAction);
                return true;
            }

            // ---- Lag Switch (consumed) ----
            if (Settings.LagSwitchEnabled && !string.IsNullOrEmpty(Settings.LagSwitchKey) &&
                vk == KeyNames.NameToVk(Settings.LagSwitchKey))
            {
                if (down && !repeat) Post(LagSwitchToggle);
                return true;
            }

            // ---- Rotation (pass-through) ----
            if (Settings.RotationEnabled && !string.IsNullOrEmpty(Settings.RotationKey) &&
                vk == KeyNames.NameToVk(Settings.RotationKey))
            {
                if (down && !repeat) Post(RotationAction);
                return false;
            }

            // ---- Sprint (Shift, consumed only when Toggle or Always) ----
            if (Settings.SprintEnabled && (vk == 0xA0 || vk == 0xA1))
            {
                if (Settings.SprintMode == "Toggle")
                {
                    if (down && !repeat) Post(ToggleSprint);
                    return true;
                }
                else if (Settings.SprintMode == "Always")
                {
                    return true; // block shift in Always mode
                }
                // Default mode: pass shift through to game
            }

            // ---- Always Sprint: re-engage on WASD press (covers respawn) ----
            if (Settings.SprintEnabled && Settings.SprintMode == "Always" && down && !repeat &&
                (vk == 0x57 || vk == 0x41 || vk == 0x53 || vk == 0x44) && vk != 0x43) // W A S D, not C
            {
                Native.SendKeyUp(0x10);
                Native.SendKeyDown(0x10);
            }

            // ---- Crouch detection: release sprint so crouch registers ----
            if (Settings.SprintEnabled && Settings.SprintMode == "Always" && vk == 0x43 && down && !repeat)
            {
                if (SprintHeld)
                {
                    Post(CrouchAndReEngageAction);
                    return true;
                }
            }

            // ---- Smart Crouch (C key, consumed) ----
            if (Settings.SmartCrouchEnabled && vk == 0x43) // C key
            {
                if (down && !repeat) Post(SmartCrouchAction);
                return true;
            }

            // ---- Auto Combo (consumed) ----
            if (Settings.AutoComboEnabled && !string.IsNullOrEmpty(Settings.AutoComboSuspendKey) &&
                vk == KeyNames.NameToVk(Settings.AutoComboSuspendKey))
            {
                if (down && !repeat) Post(AutoComboSuspendToggle);
                return true;
            }

            // ---- Fast Gun Swap (pass-through, trigger locked to LButton) ----
            if (Settings.FastGunSwapEnabled && vk == 0x01) // LButton
            {
                if (Settings.FastGunSwapMode == "Hold")
                {
                    if (down && !repeat) Post(() => FastGunSwapHoldStart("LButton"));
                }
                else
                {
                    if (down && !repeat) Post(FastGunSwapToggle);
                }
            }

            // ---- Auto Combo LButton (pass-through) ----
            if (Settings.AutoComboEnabled && vk == 0x01) // LButton
            {
                if (Settings.AutoComboClickMode == "Hold")
                {
                    if (down && !repeat) Post(() => AutoComboHoldStart());
                    if (up) Post(AutoComboHoldStop);
                }
                else
                {
                    if (down && !repeat) Post(AutoComboToggle);
                }
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

        public bool IsPhysDown(int vk)
        {
            lock (_physLock) return _physDown.Contains(vk);
        }

        private void Post(Action a)
        {
            int n = Interlocked.Increment(ref _pendingActions);
            if (n > MaxPendingActions)
            {
                Interlocked.Decrement(ref _pendingActions);
                return;
            }
            try { _actions.Add(a); }
            catch { Interlocked.Decrement(ref _pendingActions); }
        }

        private void ShowFeedback(string text, int ms = 800)
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
            bool freeze = Settings.PressureJumpFreeze;
            if (freeze)
            {
                // AHK PressureJumpV2 logic (with freeze): c, space tap (Space down 20ms /
                // space up), freeze ~200ms at the same point the AHK holds middle-mouse,
                // 14ms breath, then the speedglitch-style alternating spin.
                Native.SendKeyTap(0x43);                       // c
                Native.SendKeyDown(0x20);                      // Space down
                Thread.Sleep(20);                              // AHK: Sleep(20) when frozen
                Native.SendKeyUp(0x20);                        // Space up

                bool frozenHere = false;
                if (!Frozen)
                {
                    frozenHere = true;
                    Frozen = true;
                    Native.SuspendProcessByName(TargetProcess);
                }
                Thread.Sleep(200);                             // freeze duration (0.2s)
                if (frozenHere)
                {
                    Frozen = false;
                    Native.ResumeProcessByName(TargetProcess);
                }

                Thread.Sleep(14);                              // AHK: Sleep(14) before the spin
                // Speedglitch-style spin (Spencer-Macro-Utilities): alternate +pix / -pix
                // once per Roblox frame (1000 / FPS ms). Pix is sensitivity-driven.
                int delay = FrameDelayMs();
                long spinStart = Environment.TickCount;
                while (Environment.TickCount - spinStart <= 200)
                {
                    Native.MoveMouse(PJumpPix, 0);
                    Thread.Sleep(delay);
                    Native.MoveMouse(-PJumpPix, 0);
                    Thread.Sleep(delay);
                }
            }
            else
            {
                // Original macro logic (no freeze) with the same speedglitch-style spin
                // as the freeze branch: alternate +pix / -pix once per Roblox frame.
                Native.SendKeyTap(0x43);                       // c
                Thread.Sleep(6);
                Native.SendKeyDown(0x20);                      // Space down
                Thread.Sleep(50);
                Native.SendKeyUp(0x20);                        // Space up
                Thread.Sleep(4);

                int delay = FrameDelayMs();
                long start = Environment.TickCount;
                while (Environment.TickCount - start <= 200)
                {
                    Native.MoveMouse(PJumpPix, 0);
                    Thread.Sleep(delay);
                    Native.MoveMouse(-PJumpPix, 0);
                    Thread.Sleep(delay);
                }
            }

            // Force sprint re-engagement: the crouch/uncrouch cycle cancels
            // sprint internally in the game.  Release + re-press Shift so the
            // game sees a fresh keydown and resumes sprinting.
            if (Settings.SprintEnabled && Settings.SprintMode == "Always")
            {
                Native.SendKeyUp(0x10);
                Thread.Sleep(10);
                Native.SendKeyDown(0x10);
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
        // Clip (ported from Clip.ahk: c, delay, freeze, unfreeze, hold W)
        // ------------------------------------------------------------------
        private void ClipAction()
        {
            int delay = Settings.ClipDelayMs;
            if (delay < 0) delay = 0;

            // Release Shift so the game registers C as crouch (sprint overrides
            // crouch when Shift is held).
            bool wasSprintHeld = SprintHeld;
            if (wasSprintHeld) Native.SendKeyUp(0x10);

            Native.SendKeyDown(0x57);                    // w down - hold for the whole macro
            try
            {
                Native.SendKeyTap(0x43);                 // c
                Thread.Sleep(delay);                     // personalisable, can break the macro if wrong
                Native.SuspendProcessByName(TargetProcess);   // MButton down = freeze
                Thread.Sleep(750);
                Native.ResumeProcessByName(TargetProcess);    // MButton up = unfreeze
            }
            finally
            {
                Native.SendKeyUp(0x57);                  // w up at the very end
            }

            // Re-engage sprint if Always mode is active.
            if (wasSprintHeld && Settings.SprintEnabled && Settings.SprintMode == "Always")
            {
                Native.SendKeyDown(0x10);
            }
        }

        // ------------------------------------------------------------------
        // Lag Switch (toggle activated only while Roblox is focused)
        // ------------------------------------------------------------------
        private void LagSwitchToggle()
        {
            LagSwitch.SetActive(!LagSwitch.Active);
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
                Thread.Sleep(RotationFlickBackDelayMs);
                Native.MoveMouse(-dx, 0);
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
                Native.SendKeyUp(0x10);
            }
            else
            {
                SprintHeld = true;
                Native.SendKeyDown(0x10);
            }
        }


        private void AlwaysSprintLoop()
        {
            if (!Settings.SprintEnabled || Settings.SprintMode != "Always" || GlobalSuspended)
            {
                PostDelayed(AlwaysSprintLoop, 50);
                return;
            }
            bool focused = Native.IsProcessFocused(TargetProcess);
            if (focused)
            {
                if (!SprintHeld || !_wasProcessFocused)
                {
                    Native.SendKeyUp(0x10);
                    Thread.Sleep(10);
                    SprintHeld = true;
                    Native.SendKeyDown(0x10);
                }
            }
            else
            {
                if (SprintHeld)
                {
                    SprintHeld = false;
                    Native.SendKeyUp(0x10);
                }
            }
            _wasProcessFocused = focused;
            PostDelayed(AlwaysSprintLoop, 50);
        }

        private void PostDelayed(Action a, int ms)
        {
            var t = new Timer(_ => { Post(a); }, null, ms, Timeout.Infinite);
        }

        private void ReEngageSprint()
        {
            if (!Settings.SprintEnabled || Settings.SprintMode != "Always") return;
            Native.SendKeyUp(0x10);
            Thread.Sleep(10);
            SprintHeld = true;
            Native.SendKeyDown(0x10);
        }

        private void CrouchAndReEngageAction()
        {
            Native.SendKeyUp(0x10);
            Native.SendKeyTap(0x43);
            Thread.Sleep(10);
            if (Settings.SprintEnabled && Settings.SprintMode == "Always")
                Native.SendKeyDown(0x10);
        }

        private void WatchFocus()
        {
            // AlwaysSprintLoop is the sole authority on SprintHeld / Shift key
            // state.  Nothing to do here.
        }

        // ------------------------------------------------------------------
        // Smart Crouch (release shift, press c, re-hold shift, reload on odd presses)
        // ------------------------------------------------------------------
        private void SmartCrouchAction()
        {
            _smartCrouchPressCount++;
            bool shouldReload = (_smartCrouchPressCount % 2) == 1;

            if (shouldReload)
            {
                List<int> slots = BuildActiveSlots();
                // Build: r1r2r3...rN + last slot again
                int count = slots.Count;
                int[] sequence = new int[count * 2 + 2];
                for (int i = 0; i < count; i++)
                {
                    sequence[i * 2] = 0x52;
                    sequence[i * 2 + 1] = slots[i];
                }
                sequence[count * 2] = 0x52;
                sequence[count * 2 + 1] = slots[count - 1];
                Native.SendKeyTapSequence(sequence);
                Thread.Sleep(140);
            }

            Native.SendKeyUp(0x10); // LShift up
            Native.SendKeyTap(0x43); // c
            Thread.Sleep(10);
            if (Settings.SprintEnabled && (Settings.SprintMode == "Toggle" && SprintHeld || Settings.SprintMode == "Always"))
                Native.SendKeyDown(0x10); // LShift down
        }

        // ------------------------------------------------------------------
        // Auto Combo
        // ------------------------------------------------------------------
        private void AutoComboSuspendToggle()
        {
            AutoComboOn = !AutoComboOn;
            if (!AutoComboOn)
                AutoComboHolding = false;
            ShowFeedback("Auto Combo: " + (AutoComboOn ? "ON" : "OFF"), 600);
        }

        private void AutoComboToggle()
        {
            if (!AutoComboOn)
                return;
            AutoComboHolding = !AutoComboHolding;
            if (AutoComboHolding)
                Post(AutoComboLoop);
        }

        private void AutoComboHoldStart()
        {
            if (!AutoComboOn || AutoComboHolding)
                return;
            AutoComboHolding = true;
            Post(AutoComboLoop);
        }

        private void AutoComboHoldStop()
        {
            AutoComboHolding = false;
        }

        private void AutoComboLoop()
        {
            if (!AutoComboHolding || !Settings.AutoComboEnabled || !AutoComboOn || GlobalSuspended)
            {
                AutoComboHolding = false;
                return;
            }

            long cycleStart = Environment.TickCount;

            // --- Slot 2 (shotgun): tap 2, wait 60ms, click hold 70ms ---
            Native.SendKeyTap(0x32);
            Thread.Sleep(60);
            Native.MouseDown(0x01);
            Thread.Sleep(70);
            Native.MouseUp(0x01);

            if (!AutoComboHolding) { AutoComboHolding = false; return; }

            // --- Slot 1 (m4a1): tap 1, wait 25ms, click hold ---
            Native.SendKeyTap(0x31);
            Thread.Sleep(25);
            Native.MouseDown(0x01);
            long holdStart = Environment.TickCount;
            int holdTarget = 555;
            while (Environment.TickCount - holdStart < holdTarget)
            {
                if (!AutoComboHolding) { Native.MouseUp(0x01); AutoComboHolding = false; return; }
                Thread.Sleep(1);
            }
            Native.MouseUp(0x01);

            // --- Wait remaining of 555ms cycle ---
            int cycleElapsed = (int)(Environment.TickCount - cycleStart);
            int remaining = 555 - cycleElapsed;
            while (remaining > 0)
            {
                if (!AutoComboHolding) { AutoComboHolding = false; return; }
                int chunk = remaining > 10 ? 10 : remaining;
                Thread.Sleep(chunk);
                remaining -= chunk;
            }

            Thread.Sleep(30);

            if (AutoComboHolding)
                Post(AutoComboLoop);
            else
                AutoComboHolding = false;
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
            ShowFeedback("Main Gun Slots: " + n, 600);
        }

        // ------------------------------------------------------------------
        // Fast Gun Swap
        // ------------------------------------------------------------------
        private void FastGunSwapOnOffToggle()
        {
            FastGunSwapOn = !FastGunSwapOn;
            if (!FastGunSwapOn)
                FastGunSwapHolding = false;
            ShowFeedback("Fast Gun Swap: " + (FastGunSwapOn ? "ON" : "OFF"), 600);
        }

        private void FastGunSwapHoldStart(string keyName)
        {
            int keyVk = KeyNames.NameToVk(keyName);
            if (keyVk == 0 || !FastGunSwapOn)
                return;
            var slots = BuildActiveSlots();
            if (slots.Count == 0)
                return;
            while (IsPhysDown(keyVk))
            {
                if (!Settings.FastGunSwapEnabled || !FastGunSwapOn || GlobalSuspended)
                    break;
                foreach (var k in slots)
                {
                    if (!IsPhysDown(keyVk))
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

            Native.SendKeyTap(0x52);                 // r - reload the current weapon first
            Thread.Sleep(ShuffleReloadInitialDelayMs);

            foreach (var k in slots)
            {
                Native.SendKeyTap(k);
                Thread.Sleep(ShuffleReloadKeyDelayMs);
                Native.SendKeyTap(0x52);             // r
                Thread.Sleep(ShuffleReloadKeyDelayMs);
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
                if (Settings.SprintEnabled && Settings.SprintMode == "Always")
                    PostDelayed(AlwaysSprintLoop, 50);
                ShowFeedback("All macros resumed", 600);
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
                AutoComboHolding = false;
                LagSwitch.SetActive(false);
                string key = string.IsNullOrEmpty(Settings.GlobalSuspendKey) ? "the suspend key" : Settings.GlobalSuspendKey;
                ShowFeedback("ALL MACROS SUSPENDED - press " + key + " to resume", 600);
            }
        }
    }
}