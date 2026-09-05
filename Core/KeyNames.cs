using System;
using System.Collections.Generic;

namespace PrisonLifeMacro.Core
{
    /// <summary>
    /// Maps between AHK-style key names (as stored in the settings file and
    /// shown in the GUI) and Windows VK codes. Mouse keys/wheels use pseudo-VK
    /// codes above 0x8000 so they can live in the same routing pipeline.
    /// </summary>
    public static class KeyNames
    {
        // Pseudo-VK codes for wheel events (they have no real VK).
        public const int WheelUpVk = 0x8001;
        public const int WheelDownVk = 0x8002;
        public const int WheelLeftVk = 0x8003;
        public const int WheelRightVk = 0x8004;

        public const int NumpadEnterVk = 0x0D;   // same VK as Enter; distinguished by the extended flag at capture time

        private static readonly Dictionary<string, int> NameToVkMap = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase)
        {
            { "LButton", 0x01 }, { "RButton", 0x02 }, { "MButton", 0x04 },
            { "XButton1", 0x05 }, { "XButton2", 0x06 },
            { "Backspace", 0x08 }, { "Tab", 0x09 }, { "Enter", 0x0D },
            { "Pause", 0x13 }, { "CapsLock", 0x14 },
            { "Escape", 0x1B }, { "Space", 0x20 }, { "PgUp", 0x21 }, { "PgDn", 0x22 },
            { "End", 0x23 }, { "Home", 0x24 }, { "Left", 0x25 }, { "Up", 0x26 },
            { "Right", 0x27 }, { "Down", 0x28 }, { "PrintScreen", 0x2C },
            { "Insert", 0x2D }, { "Delete", 0x2E },
            { "0", 0x30 }, { "1", 0x31 }, { "2", 0x32 }, { "3", 0x33 }, { "4", 0x34 },
            { "5", 0x35 }, { "6", 0x36 }, { "7", 0x37 }, { "8", 0x38 }, { "9", 0x39 },
            { "A", 0x41 }, { "B", 0x42 }, { "C", 0x43 }, { "D", 0x44 }, { "E", 0x45 },
            { "F", 0x46 }, { "G", 0x47 }, { "H", 0x48 }, { "I", 0x49 }, { "J", 0x4A },
            { "K", 0x4B }, { "L", 0x4C }, { "M", 0x4D }, { "N", 0x4E }, { "O", 0x4F },
            { "P", 0x50 }, { "Q", 0x51 }, { "R", 0x52 }, { "S", 0x53 }, { "T", 0x54 },
            { "U", 0x55 }, { "V", 0x56 }, { "W", 0x57 }, { "X", 0x58 }, { "Y", 0x59 },
            { "Z", 0x5A }, { "LWin", 0x5B }, { "RWin", 0x5C }, { "AppsKey", 0x5D },
            { "Numpad0", 0x60 }, { "Numpad1", 0x61 }, { "Numpad2", 0x62 }, { "Numpad3", 0x63 },
            { "Numpad4", 0x64 }, { "Numpad5", 0x65 }, { "Numpad6", 0x66 }, { "Numpad7", 0x67 },
            { "Numpad8", 0x68 }, { "Numpad9", 0x69 }, { "NumpadMult", 0x6A },
            { "NumpadAdd", 0x6B }, { "NumpadSub", 0x6D }, { "NumpadDot", 0x6E },
            { "NumpadDiv", 0x6F },
            { "F1", 0x70 }, { "F2", 0x71 }, { "F3", 0x72 }, { "F4", 0x73 }, { "F5", 0x74 },
            { "F6", 0x75 }, { "F7", 0x76 }, { "F8", 0x77 }, { "F9", 0x78 }, { "F10", 0x79 },
            { "F11", 0x7A }, { "F12", 0x7B }, { "F13", 0x7C }, { "F14", 0x7D }, { "F15", 0x7E },
            { "F16", 0x7F }, { "F17", 0x80 }, { "F18", 0x81 }, { "F19", 0x82 }, { "F20", 0x83 },
            { "F21", 0x84 }, { "F22", 0x85 }, { "F23", 0x86 }, { "F24", 0x87 },
            { "NumLock", 0x90 }, { "ScrollLock", 0x91 },
            { "LShift", 0xA0 }, { "RShift", 0xA1 }, { "LCtrl", 0xA2 }, { "RCtrl", 0xA3 },
            { "LAlt", 0xA4 }, { "RAlt", 0xA5 },
            { "Volume_Mute", 0xAD }, { "Volume_Down", 0xAE }, { "Volume_Up", 0xAF },
            { "Media_Next", 0xB0 }, { "Media_Prev", 0xB1 }, { "Media_Stop", 0xB2 },
            { "Media_Play_Pause", 0xB3 },
            { ";", 0xBA }, { "=", 0xBB }, { ",", 0xBC }, { "-", 0xBD }, { ".", 0xBE },
            { "/", 0xBF }, { "`", 0xC0 }, { "[", 0xDB }, { "\\", 0xDC }, { "]", 0xDD },
            { "'", 0xDE },
            { "WheelUp", WheelUpVk }, { "WheelDown", WheelDownVk },
            { "WheelLeft", WheelLeftVk }, { "WheelRight", WheelRightVk },
            { "NumpadEnter", NumpadEnterVk },
        };

        private static readonly Dictionary<int, string> VkToNameMap = BuildReverse();

        private static Dictionary<int, string> BuildReverse()
        {
            var d = new Dictionary<int, string>();
            foreach (var kv in NameToVkMap)
                d[kv.Value] = kv.Key;
            d[0x0D] = "Enter";   // plain Enter unless the extended flag says otherwise
            return d;
        }

        public static int NameToVk(string name)
        {
            if (string.IsNullOrEmpty(name))
                return 0;
            int vk;
            return NameToVkMap.TryGetValue(name.Trim(), out vk) ? vk : 0;
        }

        /// <summary>Display name for a captured VK. isExtended distinguishes NumpadEnter from Enter.</summary>
        public static string VkToName(int vk, bool isExtended)
        {
            if (vk == 0x0D && isExtended)
                return "NumpadEnter";
            string name;
            return VkToNameMap.TryGetValue(vk, out name) ? name : null;
        }

        public static bool IsMouseButton(int vk)
        {
            return vk == 0x01 || vk == 0x02 || vk == 0x04 || vk == 0x05 || vk == 0x06;
        }

        public static bool IsWheel(int vk)
        {
            return vk >= WheelUpVk && vk <= WheelRightVk;
        }

        /// <summary>The full list of capturable keys (AHK parity).</summary>
        public static IEnumerable<int> AllKeys()
        {
            var seen = new HashSet<int>();
            foreach (var kv in NameToVkMap)
            {
                if (seen.Add(kv.Value))
                    yield return kv.Value;
            }
        }
    }
}