using System;
using System.IO;
using System.Text;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Settings persistence - same file and keys as the original AHK macro:
    /// %localappdata%\PrisonLifeMacro\settings.ini
    /// </summary>
    public static class Settings
    {
        public static string SettingsDir;
        public static string SettingsFile;

        // General
        public static double CS = 0.123;
        public static double FPS = 60;
        public static bool StartMinimized;

        // Pressure Jump
        public static string PressureJumpKey = "";
        public static bool PressureJumpEnabled;
        public static bool PressureJumpFreeze;

        // Clip
        public static string ClipKey = "";
        public static int ClipDelayMs = 6;
        public static bool ClipEnabled;

        // Lag Switch
        public static string LagSwitchKey = "";
        public static bool LagSwitchEnabled;

        // Freeze
        public static string FreezeKey = "";
        public static string FreezeMode = "Toggle";
        public static bool FreezeEnabled;

        // Rotation
        public static string RotationKey = "";
        public static bool RotationEnabled;

        // Sprint
        public static bool SprintEnabled;

        // Main Gun Slots (global)
        public static int GunSlotCount = 3;
        public static string IncreaseSlotKey = "";
        public static string DecreaseSlotKey = "";

        // Fast Gun Swap
        public static string FastGunSwapKey = "";
        public static string FastGunSwapOnOffKey = "";
        public static string FastGunSwapMode = "Hold";
        public static bool FastGunSwapEnabled;

        // Shuffle Reload
        public static string ShuffleReloadKey = "";
        public static bool ShuffleReloadEnabled;

        // Global Suspend
        public static string GlobalSuspendKey = "";

        // Update detector
        public static string UpdateLastNotified = "";

        public static void InitPaths()
        {
            string la = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            if (string.IsNullOrEmpty(la))
                la = Environment.GetEnvironmentVariable("LOCALAPPDATA");
            if (string.IsNullOrEmpty(la))
                la = Path.Combine(Environment.GetEnvironmentVariable("USERPROFILE") ?? @"C:\", "AppData", "Local");
            SettingsDir = Path.Combine(la, "PrisonLifeMacro");
            SettingsFile = Path.Combine(SettingsDir, "settings.ini");
            Directory.CreateDirectory(SettingsDir);
        }

        private static string IniRead(string section, string key, string def)
        {
            var sb = new StringBuilder(1024);
            GetPrivateProfileString(section, key, def, sb, sb.Capacity, SettingsFile);
            return sb.ToString();
        }

        private static void IniWrite(string section, string key, string value)
        {
            WritePrivateProfileString(section, key, value, SettingsFile);
        }

        public static void Load()
        {
            InitPaths();
            CS = ReadDouble("General", "Sensitivity", 0.123);
            FPS = ReadDouble("General", "FPS", 60);
            StartMinimized = ReadBool("General", "StartMinimized", false);

            PressureJumpKey = Trim(IniRead("PressureJump", "Hotkey", ""));
            PressureJumpEnabled = ReadBool("PressureJump", "Enabled", false);
            PressureJumpFreeze = ReadBool("PressureJump", "Freeze", false);

            ClipKey = Trim(IniRead("Clip", "Hotkey", ""));
            ClipDelayMs = (int)Math.Round(ReadDouble("Clip", "DelayMs", 6));
            if (ClipDelayMs < 0) ClipDelayMs = 0;
            if (ClipDelayMs > 10000) ClipDelayMs = 10000;
            ClipEnabled = ReadBool("Clip", "Enabled", false);

            LagSwitchKey = Trim(IniRead("LagSwitch", "Hotkey", ""));
            LagSwitchEnabled = ReadBool("LagSwitch", "Enabled", false);

            FreezeKey = Trim(IniRead("Freeze", "Hotkey", ""));
            FreezeMode = Trim(IniRead("Freeze", "Mode", "Toggle"));
            FreezeEnabled = ReadBool("Freeze", "Enabled", false);

            RotationKey = Trim(IniRead("Rotation", "Hotkey", ""));
            RotationEnabled = ReadBool("Rotation", "Enabled", false);

            SprintEnabled = ReadBool("Sprint", "Enabled", false);

            GunSlotCount = (int)Math.Round(ReadDouble("MainGunSlots", "Count", 3));
            if (GunSlotCount < 1) GunSlotCount = 1;
            if (GunSlotCount > 10) GunSlotCount = 10;
            IncreaseSlotKey = Trim(IniRead("MainGunSlots", "IncreaseKey", ""));
            DecreaseSlotKey = Trim(IniRead("MainGunSlots", "DecreaseKey", ""));

            FastGunSwapKey = Trim(IniRead("FastGunSwap", "Hotkey", ""));
            FastGunSwapOnOffKey = Trim(IniRead("FastGunSwap", "OnOffHotkey", ""));
            FastGunSwapMode = Trim(IniRead("FastGunSwap", "Mode", "Hold"));
            FastGunSwapEnabled = ReadBool("FastGunSwap", "Enabled", false);

            ShuffleReloadKey = Trim(IniRead("ShuffleReload", "Hotkey", ""));
            ShuffleReloadEnabled = ReadBool("ShuffleReload", "Enabled", false);

            GlobalSuspendKey = Trim(IniRead("Global", "SuspendKey", ""));

            UpdateLastNotified = Trim(IniRead("Update", "LastNotified", ""));

            if (FreezeMode != "Hold") FreezeMode = "Toggle";
            if (FastGunSwapMode != "Toggle") FastGunSwapMode = "Hold";
        }

        public static void Save()
        {
            InitPaths();
            IniWrite("General", "Sensitivity", CS.ToString("0.######"));
            IniWrite("General", "FPS", FPS.ToString("0.####"));
            IniWrite("General", "StartMinimized", StartMinimized ? "1" : "0");

            IniWrite("PressureJump", "Hotkey", PressureJumpKey);
            IniWrite("PressureJump", "Enabled", PressureJumpEnabled ? "1" : "0");
            IniWrite("PressureJump", "Freeze", PressureJumpFreeze ? "1" : "0");

            IniWrite("Clip", "Hotkey", ClipKey);
            IniWrite("Clip", "DelayMs", ClipDelayMs.ToString());
            IniWrite("Clip", "Enabled", ClipEnabled ? "1" : "0");

            IniWrite("LagSwitch", "Hotkey", LagSwitchKey);
            IniWrite("LagSwitch", "Enabled", LagSwitchEnabled ? "1" : "0");

            IniWrite("Freeze", "Hotkey", FreezeKey);
            IniWrite("Freeze", "Mode", FreezeMode);
            IniWrite("Freeze", "Enabled", FreezeEnabled ? "1" : "0");

            IniWrite("Rotation", "Hotkey", RotationKey);
            IniWrite("Rotation", "Enabled", RotationEnabled ? "1" : "0");

            IniWrite("Sprint", "Enabled", SprintEnabled ? "1" : "0");

            IniWrite("MainGunSlots", "Count", GunSlotCount.ToString());
            IniWrite("MainGunSlots", "IncreaseKey", IncreaseSlotKey);
            IniWrite("MainGunSlots", "DecreaseKey", DecreaseSlotKey);

            IniWrite("FastGunSwap", "Hotkey", FastGunSwapKey);
            IniWrite("FastGunSwap", "OnOffHotkey", FastGunSwapOnOffKey);
            IniWrite("FastGunSwap", "Mode", FastGunSwapMode);
            IniWrite("FastGunSwap", "Enabled", FastGunSwapEnabled ? "1" : "0");

            IniWrite("ShuffleReload", "Hotkey", ShuffleReloadKey);
            IniWrite("ShuffleReload", "Enabled", ShuffleReloadEnabled ? "1" : "0");

            IniWrite("Global", "SuspendKey", GlobalSuspendKey);

            IniWrite("Update", "LastNotified", UpdateLastNotified);
        }

        private static double ReadDouble(string section, string key, double def)
        {
            double v;
            return double.TryParse(IniRead(section, key, "").Trim().Replace(',', '.'), out v) ? v : def;
        }

        private static bool ReadBool(string section, string key, bool def)
        {
            string s = Trim(IniRead(section, key, ""));
            if (s == "1" || s.Equals("true", StringComparison.OrdinalIgnoreCase)) return true;
            if (s == "0" || s.Equals("false", StringComparison.OrdinalIgnoreCase)) return false;
            return def;
        }

        private static string Trim(string s)
        {
            return s == null ? "" : s.Trim();
        }

        [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern int GetPrivateProfileString(string lpAppName, string lpKeyName, string lpDefault, StringBuilder lpReturnedString, int nSize, string lpFileName);

        [System.Runtime.InteropServices.DllImport("kernel32.dll", CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
        private static extern bool WritePrivateProfileString(string lpAppName, string lpKeyName, string lpString, string lpFileName);
    }
}