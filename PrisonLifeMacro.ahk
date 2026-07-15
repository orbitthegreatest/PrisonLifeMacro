; ==========================================================================
;  Prison Life Macro Suite  -  Pressure Jump + Freeze, combined
; ==========================================================================
;  - Roblox Sensitivity / DPI configure the Pressure Jump spin calculation.
;  - Both macro hotkeys are set with the "click, then press any key" capture
;    method (same UX as the original freeze_macro_gui.ahk).
;  - Each macro can be individually enabled/disabled.
;  - Target process is fixed to RobloxPlayerBeta.exe and is not user editable.
;  - Settings are stored at: %localappdata%\PrisonLifeMacro\settings.ini
; ==========================================================================

#SingleInstance Force
#Persistent
#NoEnv
SendMode Input
SetWorkingDir %A_ScriptDir%
SetBatchLines, -1
Process, Priority,, High

DllCall("Winmm\timeBeginPeriod", "UInt", 1)

; ------------------------- Fixed constants -------------------------
TargetProcess := "RobloxPlayerBeta.exe"   ; NOT user configurable
Spin      := 5000     ; only touch if the spin feels too slow/fast
BaseDPI   := 800       ; reference DPI the spin constant was tuned for
BaseCS    := 0.36      ; reference sensitivity the spin constant was tuned for

; ------------------------- Settings location -------------------------
SettingsDir  := A_LocalAppData . "\PrisonLifeMacro"
SettingsFile := SettingsDir . "\settings.ini"
IfNotExist, %SettingsDir%
    FileCreateDir, %SettingsDir%

; ------------------------- Defaults / state -------------------------
DPI                := 800
CS                 := 0.123     ; Roblox sensitivity
PressureJumpKey    := "Q"
PressureJumpEnabled:= true
FreezeKey          := "F7"
FreezeMode         := "Toggle"  ; "Toggle" or "Hold"
FreezeEnabled      := true
StartMinimized     := false

Frozen        := false
Capturing     := false
CaptureTarget := ""             ; "PJ" or "Freeze"
CaptureList   := []
X             := 0

LoadSettings()
RecalculateX()
BuildTray()
BuildGui()
if (StartMinimized) {
    Gui, Hide
    TrayTip, Prison Life Macro Suite, Running minimized. Right-click the tray icon to open settings., 3
}
ApplyPressureJumpHotkey()
ApplyFreezeHotkey()
return

; ==========================================================================
;                                  GUI
; ==========================================================================

BuildGui() {
    global DPI, CS, PressureJumpKey, PressureJumpEnabled, FreezeKey, FreezeMode, FreezeEnabled, StartMinimized
    global DPIInput, CSInput, PJEnabledCB, PJHotkeyDisplay, FreezeEnabledCB, FreezeHotkeyDisplay, ModeDD, StartMinCB

    PJChecked     := PressureJumpEnabled ? 1 : 0
    FreezeChecked := FreezeEnabled ? 1 : 0
    StartMinChecked := StartMinimized ? 1 : 0
    ModeChoice    := (FreezeMode = "Hold") ? 2 : 1

    Gui, Font, s10, Segoe UI
    Gui, Add, Text, x20 y18 w150, Roblox Sensitivity:
    Gui, Add, Edit, x180 y15 w100 vCSInput, %CS%

    Gui, Add, Text, x20 y50 w150, Mouse DPI:
    Gui, Add, Edit, x180 y47 w100 vDPIInput, %DPI%

    Gui, Add, Text, x20 y90 w260, Pressure Jump Macro:
    Gui, Add, CheckBox, x20 y113 vPJEnabledCB Checked%PJChecked%, Enable
    Gui, Add, Text, x110 y113 vPJHotkeyDisplay w170 cBlue, %PressureJumpKey%
    Gui, Add, Button, x20 y138 w260 gStartCapturePJ, Click, then press key/button for Pressure Jump...

    Gui, Add, Text, x20 y180 w260, Freeze Macro:
    Gui, Add, CheckBox, x20 y203 vFreezeEnabledCB Checked%FreezeChecked%, Enable
    Gui, Add, Text, x110 y203 vFreezeHotkeyDisplay w170 cBlue, %FreezeKey%
    Gui, Add, Button, x20 y228 w260 gStartCaptureFreeze, Click, then press key/button for Freeze...

    Gui, Add, Text, x20 y270 w80, Mode:
    Gui, Add, DropDownList, x100 y267 w180 vModeDD Choose%ModeChoice%, Toggle (press once, again to release)|Hold (frozen only while held)

    Gui, Add, CheckBox, x20 y308 vStartMinCB Checked%StartMinChecked%, Start minimized (to tray)

    Gui, Add, Button, x20 y343 w125 h30 gSaveSettings Default, Save
    Gui, Add, Button, x155 y343 w125 h30 gGuiCancel, Hide

    Gui, Margin, 20, 20
    Gui, +MinimizeBox
    Gui, Show, w300 h395, Prison Life Macro Settings
}

GuiSize:
    ; A_EventInfo = 1 means the window was just minimized via the title bar "-" button.
    ; Treat that the same as "Hide to tray" instead of leaving a taskbar/minimized window.
    if (A_EventInfo = 1)
        Gui, Hide
return

GuiClose:
    ; The title bar "X" button (or Alt+F4) fully exits the whole macro suite.
    DllCall("Winmm\timeEndPeriod", "UInt", 1)
    ExitApp

GuiCancel:
GuiEscape:
    Gui, Hide
return

; ==========================================================================
;                          Settings save / validate
; ==========================================================================

SaveSettings:
    Gui, Submit, NoHide
    NewDPI := DPIInput
    NewCS  := CSInput

    if (NewDPI = "" or NewCS = "" or NewDPI + 0 = 0 or NewCS + 0 = 0) {
        MsgBox, 48, Invalid Input, Please enter valid non-zero numbers for DPI and Roblox Sensitivity.
        return
    }

    DPI := NewDPI
    CS  := NewCS
    PressureJumpEnabled := PJEnabledCB
    FreezeEnabled       := FreezeEnabledCB
    FreezeMode          := InStr(ModeDD, "Hold") ? "Hold" : "Toggle"
    StartMinimized      := StartMinCB

    RecalculateX()
    SaveSettingsToFile()
    ApplyPressureJumpHotkey()
    ApplyFreezeHotkey()

    ToolTip, Settings saved
    SetTimer, RemoveToolTip, -700
return

RemoveToolTip:
    ToolTip
return

RecalculateX() {
    global Spin, BaseDPI, BaseCS, DPI, CS, X
    X := Round((Spin * BaseDPI * BaseCS) / (DPI * CS))
}

; ==========================================================================
;                       Key/button capture (shared)
; ==========================================================================

BuildKeyList() {
    list := []
    Loop, 26
        list.Push(Chr(64 + A_Index))            ; A-Z
    Loop, 10
        list.Push(A_Index - 1)                   ; 0-9
    Loop, 24
        list.Push("F" . A_Index)                 ; F1-F24
    Loop, 10
        list.Push("Numpad" . (A_Index - 1))      ; Numpad0-9

    extras := ["NumpadDot", "NumpadEnter", "NumpadAdd", "NumpadSub", "NumpadMult", "NumpadDiv"
             , "Up", "Down", "Left", "Right", "Home", "End", "PgUp", "PgDn", "Insert", "Delete"
             , "Backspace", "Tab", "CapsLock", "Space", "Enter", "Escape", "ScrollLock", "NumLock"
             , "PrintScreen", "Pause", "AppsKey"
             , "LShift", "RShift", "LCtrl", "RCtrl", "LAlt", "RAlt", "LWin", "RWin"
             , "-", "=", "[", "]", "\", ";", "'", ",", ".", "/", "``"
             , "LButton", "RButton", "MButton", "XButton1", "XButton2"
             , "WheelUp", "WheelDown", "WheelLeft", "WheelRight"
             , "Volume_Mute", "Volume_Up", "Volume_Down"
             , "Media_Play_Pause", "Media_Next", "Media_Prev", "Media_Stop"]

    for _, k in extras
        list.Push(k)
    return list
}

StartCapturePJ:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "PJ"
    GuiControl,, PJHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindPressureJumpHotkey()
    BeginKeyListen()
return

StartCaptureFreeze:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "Freeze"
    GuiControl,, FreezeHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindFreezeHotkey()
    BeginKeyListen()
return

BeginKeyListen() {
    global CaptureList
    CaptureList := BuildKeyList()
    for _, k in CaptureList
        try Hotkey, *%k%, CaptureKeyPressed, On
}

CaptureKeyPressed:
    Captured := A_ThisHotkey
    StringReplace, Captured, Captured, *, , All   ; strip the leading "*" AHK reports back

    for _, k in CaptureList
        try Hotkey, *%k%, , Off

    Capturing := false

    if (Captured = "Escape") {
        if (CaptureTarget = "PJ")
            GuiControl,, PJHotkeyDisplay, %PressureJumpKey%
        else
            GuiControl,, FreezeHotkeyDisplay, %FreezeKey%
    } else {
        if (CaptureTarget = "PJ") {
            PressureJumpKey := Captured
            GuiControl,, PJHotkeyDisplay, %PressureJumpKey%
            ApplyPressureJumpHotkey()
        } else {
            FreezeKey := Captured
            GuiControl,, FreezeHotkeyDisplay, %FreezeKey%
            ApplyFreezeHotkey()
        }
    }
    CaptureTarget := ""
return

; ==========================================================================
;                         Pressure Jump hotkey/action
; ==========================================================================

UnbindPressureJumpHotkey() {
    global PressureJumpKey
    try Hotkey, *%PressureJumpKey%, , Off
}

ApplyPressureJumpHotkey() {
    global PressureJumpKey, PressureJumpEnabled
    UnbindPressureJumpHotkey()
    if (PressureJumpEnabled)
        Hotkey, *%PressureJumpKey%, PressureJumpAction, On
}

PressureJumpAction:
    SendInput, c
    DllCall("Sleep", "UInt", 6)

    SendInput, {Space down}
    DllCall("Sleep", "UInt", 50)
    SendInput, {Space up}

    DllCall("Sleep", "UInt", 4)

    start := A_TickCount
    Loop {
        if (A_TickCount - start > 200)
            break
        DllCall("mouse_event", "UInt", 0x0001, "Int", X, "Int", 0, "UInt", 0, "UPtr", 0)
        DllCall("Sleep", "UInt", 4)
    }
return

; ==========================================================================
;                            Freeze hotkey/action
; ==========================================================================

UnbindFreezeHotkey() {
    global FreezeKey
    try Hotkey, *%FreezeKey%, , Off
    try Hotkey, *%FreezeKey% up, , Off
}

ApplyFreezeHotkey() {
    global FreezeKey, FreezeMode, FreezeEnabled
    UnbindFreezeHotkey()
    if (!FreezeEnabled)
        return
    if (FreezeMode = "Hold") {
        Hotkey, *%FreezeKey%, HoldDown, On
        Hotkey, *%FreezeKey% up, HoldUp, On
    } else {
        Hotkey, *%FreezeKey%, ToggleFreeze, On
    }
}

ToggleFreeze:
    Frozen := !Frozen
    if (Frozen) {
        SuspendProcess(TargetProcess)
        ToolTip, Frozen
    } else {
        ResumeProcess(TargetProcess)
        ToolTip, Unfrozen
    }
    SetTimer, RemoveToolTip, -700
return

HoldDown:
    if (!Frozen) {
        Frozen := true
        SuspendProcess(TargetProcess)
        ToolTip, Frozen (holding)
    }
return

HoldUp:
    if (Frozen) {
        Frozen := false
        ResumeProcess(TargetProcess)
        ToolTip, Unfrozen
        SetTimer, RemoveToolTip, -700
    }
return

; ------------------------- Process suspend/resume -------------------------

SuspendProcess(ProcessName) {
    Process, Exist, %ProcessName%
    PID := ErrorLevel
    if (!PID)
        return
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", PID, "Ptr")
    DllCall("ntdll.dll\NtSuspendProcess", "Ptr", hProcess)
    DllCall("CloseHandle", "Ptr", hProcess)
}

ResumeProcess(ProcessName) {
    Process, Exist, %ProcessName%
    PID := ErrorLevel
    if (!PID)
        return
    hProcess := DllCall("OpenProcess", "UInt", 0x1F0FFF, "Int", 0, "UInt", PID, "Ptr")
    DllCall("ntdll.dll\NtResumeProcess", "Ptr", hProcess)
    DllCall("CloseHandle", "Ptr", hProcess)
}

; ==========================================================================
;                          Settings persistence
; ==========================================================================

LoadSettings() {
    global SettingsFile, DPI, CS, PressureJumpKey, PressureJumpEnabled
    global FreezeKey, FreezeMode, FreezeEnabled, StartMinimized

    IfExist, %SettingsFile%
    {
        IniRead, DPI, %SettingsFile%, PressureJump, DPI, 800
        IniRead, CS, %SettingsFile%, PressureJump, Sensitivity, 0.123
        IniRead, PressureJumpKey, %SettingsFile%, PressureJump, Hotkey, Q
        IniRead, PressureJumpEnabled, %SettingsFile%, PressureJump, Enabled, 1

        IniRead, FreezeKey, %SettingsFile%, Freeze, Hotkey, F7
        IniRead, FreezeMode, %SettingsFile%, Freeze, Mode, Toggle
        IniRead, FreezeEnabled, %SettingsFile%, Freeze, Enabled, 1

        IniRead, StartMinimized, %SettingsFile%, General, StartMinimized, 0
    }
    PressureJumpEnabled := (PressureJumpEnabled = 1 || PressureJumpEnabled = "true")
    FreezeEnabled       := (FreezeEnabled = 1 || FreezeEnabled = "true")
    StartMinimized      := (StartMinimized = 1 || StartMinimized = "true")
}

SaveSettingsToFile() {
    global SettingsFile, DPI, CS, PressureJumpKey, PressureJumpEnabled
    global FreezeKey, FreezeMode, FreezeEnabled, StartMinimized

    IniWrite, %DPI%, %SettingsFile%, PressureJump, DPI
    IniWrite, %CS%, %SettingsFile%, PressureJump, Sensitivity
    IniWrite, %PressureJumpKey%, %SettingsFile%, PressureJump, Hotkey
    IniWrite, % (PressureJumpEnabled ? 1 : 0), %SettingsFile%, PressureJump, Enabled

    IniWrite, %FreezeKey%, %SettingsFile%, Freeze, Hotkey
    IniWrite, %FreezeMode%, %SettingsFile%, Freeze, Mode
    IniWrite, % (FreezeEnabled ? 1 : 0), %SettingsFile%, Freeze, Enabled

    IniWrite, % (StartMinimized ? 1 : 0), %SettingsFile%, General, StartMinimized
}

; ==========================================================================
;                              Tray icon
; ==========================================================================

BuildTray() {
    Menu, Tray, NoStandard
    Menu, Tray, Add, Open Settings, TrayShowSettings
    Menu, Tray, Add
    Menu, Tray, Add, Exit, TrayExit
    Menu, Tray, Default, Open Settings
    Menu, Tray, Tip, Prison Life Macro Suite
}

TrayShowSettings:
    Gui, Show,, Prison Life Macro Settings
return

TrayExit:
    DllCall("Winmm\timeEndPeriod", "UInt", 1)
    ExitApp
return
