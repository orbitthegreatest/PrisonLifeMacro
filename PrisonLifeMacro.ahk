; ==========================================================================
;  Prison Life Macro Suite  -  Pressure Jump + Freeze + Rotation, combined
; ==========================================================================
;  - Roblox Sensitivity, Mouse DPI, and Roblox FPS are now GLOBAL settings
;    shared across the macros that need them (Pressure Jump spin calc and
;    Rotation flick-pixel calc both read the same Sensitivity value).
;  - All three macro hotkeys use the "click, then press any key/button"
;    capture method.
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
Spin      := 5000      ; Pressure Jump spin constant - only touch if it feels off
BaseDPI   := 800        ; reference DPI the spin constant was tuned for
BaseCS    := 0.36        ; reference sensitivity the spin constant was tuned for

; Rotation macro - only the trigger keybind, Roblox Sensitivity (global,
; shared with Pressure Jump) and Roblox FPS are user-facing. Everything
; else mirrors the original RotationMacro.ahk defaults and stays fixed.
RotationJumpKeyName  := "Space"
RotationCamFix       := false   ; affects the 720 vs 1000 constant below
RotationFlickDegrees := 179
RotationWallhopLength:= 19       ; ms, fixed
RotationBonusDelay   := 0        ; ms, fixed
RotationLeftFlick    := false
RotationJumpDuring   := false
RotationFlickBack    := false

; ------------------------- Settings location -------------------------
SettingsDir  := A_LocalAppData . "\PrisonLifeMacro"
SettingsFile := SettingsDir . "\settings.ini"
IfNotExist, %SettingsDir%
    FileCreateDir, %SettingsDir%

; ------------------------- Defaults / state -------------------------
; --- Global (shared) ---
DPI                := 800
CS                 := 0.123     ; Roblox sensitivity - shared by Pressure Jump + Rotation
FPS                := 60        ; Roblox FPS - stored/reference, same as original RotationMacro field
StartMinimized     := false

; --- Pressure Jump ---
PressureJumpKey     := "Q"
PressureJumpEnabled := true

; --- Freeze ---
FreezeKey          := "F7"
FreezeMode         := "Toggle"  ; "Toggle" or "Hold"
FreezeEnabled      := true

; --- Rotation ---
RotationKey        := "F"
RotationEnabled    := true

Frozen        := false
Capturing     := false
CaptureTarget := ""             ; "PJ", "Freeze", or "Rotation"
CaptureList   := []
X             := 0              ; Pressure Jump circular-motion pixel amount
RotX          := 0              ; Rotation flick pixel amount

LoadSettings()
RecalculateX()
RecalcRotationPixels()
BuildTray()
BuildGui()
if (StartMinimized) {
    Gui, Hide
    TrayTip, Prison Life Macro Suite, Running minimized. Right-click the tray icon to open settings., 3
}
ApplyPressureJumpHotkey()
ApplyFreezeHotkey()
ApplyRotationHotkey()
return

; ==========================================================================
;                                  GUI
; ==========================================================================

BuildGui() {
    global DPI, CS, FPS, PressureJumpKey, PressureJumpEnabled, FreezeKey, FreezeMode, FreezeEnabled
    global RotationKey, RotationEnabled, StartMinimized
    global DPIInput, CSInput, FPSInput
    global PJEnabledCB, PJHotkeyDisplay, FreezeEnabledCB, FreezeHotkeyDisplay, ModeDD
    global RotEnabledCB, RotHotkeyDisplay, StartMinCB

    PJChecked       := PressureJumpEnabled ? 1 : 0
    FreezeChecked   := FreezeEnabled ? 1 : 0
    RotChecked      := RotationEnabled ? 1 : 0
    StartMinChecked := StartMinimized ? 1 : 0
    ModeChoice      := (FreezeMode = "Hold") ? 2 : 1

    ; ---- Dark "Prison Life" theme ----
    ; Background: near-black charcoal. Accent: cell-block orange/red.
    AccentColor := "FF7A1A"
    DimColor    := "9A9A9A"
    TextColor   := "E8E8E8"

    Gui, +LastFound
    Gui, Color, 141414, 1E1E1E
    Gui, Font, s10, Segoe UI

    ; ---- Header banner ----
    Gui, Font, s16 Bold, Segoe UI
    Gui, Add, Text, x20 y18 w400 c%AccentColor% BackgroundTrans, PRISON LIFE MACRO SUITE
    Gui, Font, s9 Norm, Segoe UI
    Gui, Add, Text, x20 y46 w400 c%DimColor% BackgroundTrans, Pressure Jump  |  Freeze  |  Rotation
    Gui, Add, Progress, x20 y72 w480 h4 Range0-100 c%AccentColor% Background141414, 100

    ; ---- Global settings ----
    Gui, Font, s10 Bold, Segoe UI
    Gui, Add, Text, x20 y88 w200 c%TextColor% BackgroundTrans, GLOBAL SETTINGS
    Gui, Font, s10 Norm, Segoe UI
    Gui, Add, Text, x20 y114 w140 c%DimColor% BackgroundTrans, Roblox Sensitivity:
    Gui, Add, Edit, x180 y111 w90 vCSInput cWhite, %CS%
    Gui, Add, Text, x290 y114 w70 c%DimColor% BackgroundTrans, Mouse DPI:
    Gui, Add, Edit, x365 y111 w95 vDPIInput cWhite, %DPI%
    Gui, Add, Text, x20 y144 w140 c%DimColor% BackgroundTrans, Roblox FPS:
    Gui, Add, Edit, x180 y141 w90 vFPSInput cWhite, %FPS%

    ; ---- Tabs: one per macro ----
    Gui, Add, Tab3, x20 y178 w480 h248 c%TextColor%, Pressure Jump|Freeze|Rotation

    Gui, Tab, 1
    Gui, Add, CheckBox, x40 y216 vPJEnabledCB Checked%PJChecked% c%TextColor%, Enable Pressure Jump
    Gui, Add, Text, x40 y248 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y248 vPJHotkeyDisplay w170 c%AccentColor%, %PressureJumpKey%
    Gui, Add, Button, x40 y276 w420 gStartCapturePJ, Click, then press key/button for Pressure Jump...

    Gui, Tab, 2
    Gui, Add, CheckBox, x40 y216 vFreezeEnabledCB Checked%FreezeChecked% c%TextColor%, Enable Freeze
    Gui, Add, Text, x40 y248 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y248 vFreezeHotkeyDisplay w170 c%AccentColor%, %FreezeKey%
    Gui, Add, Button, x40 y276 w420 gStartCaptureFreeze, Click, then press key/button for Freeze...
    Gui, Add, Text, x40 y316 w80 c%DimColor%, Mode:
    Gui, Add, DropDownList, x120 y313 w340 vModeDD Choose%ModeChoice%, Toggle (press once, again to release)|Hold (frozen only while held)

    Gui, Tab, 3
    Gui, Add, CheckBox, x40 y216 vRotEnabledCB Checked%RotChecked% c%TextColor%, Enable Rotation
    Gui, Add, Text, x40 y248 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y248 vRotHotkeyDisplay w170 c%AccentColor%, %RotationKey%
    Gui, Add, Button, x40 y276 w420 gStartCaptureRotation, Click, then press key/button for Rotation...

    Gui, Tab

    Gui, Add, CheckBox, x20 y436 vStartMinCB Checked%StartMinChecked% c%TextColor%, Start minimized (to tray)

    Gui, Add, Button, x20 y468 w235 h32 gSaveSettings Default, Save
    Gui, Add, Button, x265 y468 w235 h32 gGuiCancel, Hide

    Gui, Margin, 20, 20
    Gui, +MinimizeBox
    Gui, Show, w520 h522, Prison Life Macro Settings
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
    NewFPS := FPSInput

    if (NewDPI = "" or NewCS = "" or NewFPS = "" or NewDPI + 0 = 0 or NewCS + 0 = 0 or NewFPS + 0 = 0) {
        MsgBox, 48, Invalid Input, Please enter valid non-zero numbers for Roblox Sensitivity, Mouse DPI, and Roblox FPS.
        return
    }

    DPI := NewDPI
    CS  := NewCS
    FPS := NewFPS
    PressureJumpEnabled := PJEnabledCB
    FreezeEnabled       := FreezeEnabledCB
    FreezeMode          := InStr(ModeDD, "Hold") ? "Hold" : "Toggle"
    RotationEnabled     := RotEnabledCB
    StartMinimized      := StartMinCB

    RecalculateX()
    RecalcRotationPixels()
    SaveSettingsToFile()
    ApplyPressureJumpHotkey()
    ApplyFreezeHotkey()
    ApplyRotationHotkey()

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

RecalcRotationPixels() {
    ; pixels = degrees * (CamFix ? 1000 : 720) / (360 * sensitivity)
    ; Uses the same global Roblox Sensitivity (CS) as Pressure Jump.
    global CS, RotX, RotationFlickDegrees, RotationCamFix
    sens := CS + 0
    if (sens <= 0)
        sens := 0.01
    base := RotationCamFix ? 1000 : 720
    RotX := Round(RotationFlickDegrees * base / (360 * sens))
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

StartCaptureRotation:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "Rotation"
    GuiControl,, RotHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindRotationHotkey()
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
        else if (CaptureTarget = "Freeze")
            GuiControl,, FreezeHotkeyDisplay, %FreezeKey%
        else if (CaptureTarget = "Rotation")
            GuiControl,, RotHotkeyDisplay, %RotationKey%
    } else {
        if (CaptureTarget = "PJ") {
            PressureJumpKey := Captured
            GuiControl,, PJHotkeyDisplay, %PressureJumpKey%
            ApplyPressureJumpHotkey()
        } else if (CaptureTarget = "Freeze") {
            FreezeKey := Captured
            GuiControl,, FreezeHotkeyDisplay, %FreezeKey%
            ApplyFreezeHotkey()
        } else if (CaptureTarget = "Rotation") {
            RotationKey := Captured
            GuiControl,, RotHotkeyDisplay, %RotationKey%
            ApplyRotationHotkey()
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
;                       Rotation (wallhop) hotkey/action
; ==========================================================================
; Ported from RotationMacro.ahk (originally AutoHotkey v2) into this v1
; suite. Flicks the camera by a pixel amount derived from a fixed 179°
; flick angle and the global Roblox Sensitivity, then (per the fixed,
; non-GUI defaults carried over from the original script) does not
; flick back or hold jump unless those internal flags are changed.

UnbindRotationHotkey() {
    global RotationKey
    try Hotkey, ~*%RotationKey%, , Off
}

ApplyRotationHotkey() {
    global RotationKey, RotationEnabled
    UnbindRotationHotkey()
    if (RotationEnabled)
        Hotkey, ~*%RotationKey%, RotationAction, On   ; "~" lets the key/button still pass through to Roblox
}

RotationAction:
    RecalcRotationPixels()

    px        := RotX
    delay     := RotationWallhopLength
    bonus     := RotationBonusDelay
    left      := RotationLeftFlick
    doJump    := RotationJumpDuring
    flickBack := RotationFlickBack
    jumpKey   := RotationJumpKeyName

    dx := left ? -px : px

    ; Initial flick
    DllCall("mouse_event", "UInt", 0x0001, "Int", dx, "Int", 0, "UInt", 0, "UPtr", 0)

    if (flickBack) {
        if (bonus > 0 and bonus < delay) {
            Sleep, %bonus%
            if (doJump)
                SendInput, {%jumpKey% down}
            remain := delay - bonus
            Sleep, %remain%
        } else {
            if (doJump)
                SendInput, {%jumpKey% down}
            Sleep, %delay%
        }
        ; Flick back (same direction/magnitude as the original code's dy pass)
        DllCall("mouse_event", "UInt", 0x0001, "Int", dx, "Int", 0, "UInt", 0, "UPtr", 0)
    } else if (doJump) {
        SendInput, {%jumpKey% down}
    }

    if (doJump) {
        remaining := 100 - delay
        if (remaining > 0)
            Sleep, %remaining%
        SendInput, {%jumpKey% up}
    }
return

; ==========================================================================
;                          Settings persistence
; ==========================================================================

LoadSettings() {
    global SettingsFile, DPI, CS, FPS, StartMinimized
    global PressureJumpKey, PressureJumpEnabled
    global FreezeKey, FreezeMode, FreezeEnabled
    global RotationKey, RotationEnabled

    IfExist, %SettingsFile%
    {
        IniRead, DPI, %SettingsFile%, General, DPI, 800
        IniRead, CS, %SettingsFile%, General, Sensitivity, 0.123
        IniRead, FPS, %SettingsFile%, General, FPS, 60
        IniRead, StartMinimized, %SettingsFile%, General, StartMinimized, 0

        IniRead, PressureJumpKey, %SettingsFile%, PressureJump, Hotkey, Q
        IniRead, PressureJumpEnabled, %SettingsFile%, PressureJump, Enabled, 1

        IniRead, FreezeKey, %SettingsFile%, Freeze, Hotkey, F7
        IniRead, FreezeMode, %SettingsFile%, Freeze, Mode, Toggle
        IniRead, FreezeEnabled, %SettingsFile%, Freeze, Enabled, 1

        IniRead, RotationKey, %SettingsFile%, Rotation, Hotkey, F
        IniRead, RotationEnabled, %SettingsFile%, Rotation, Enabled, 1
    }
    PressureJumpEnabled := (PressureJumpEnabled = 1 || PressureJumpEnabled = "true")
    FreezeEnabled       := (FreezeEnabled = 1 || FreezeEnabled = "true")
    RotationEnabled     := (RotationEnabled = 1 || RotationEnabled = "true")
    StartMinimized      := (StartMinimized = 1 || StartMinimized = "true")
}

SaveSettingsToFile() {
    global SettingsFile, DPI, CS, FPS, StartMinimized
    global PressureJumpKey, PressureJumpEnabled
    global FreezeKey, FreezeMode, FreezeEnabled
    global RotationKey, RotationEnabled

    IniWrite, %DPI%, %SettingsFile%, General, DPI
    IniWrite, %CS%, %SettingsFile%, General, Sensitivity
    IniWrite, %FPS%, %SettingsFile%, General, FPS
    IniWrite, % (StartMinimized ? 1 : 0), %SettingsFile%, General, StartMinimized

    IniWrite, %PressureJumpKey%, %SettingsFile%, PressureJump, Hotkey
    IniWrite, % (PressureJumpEnabled ? 1 : 0), %SettingsFile%, PressureJump, Enabled

    IniWrite, %FreezeKey%, %SettingsFile%, Freeze, Hotkey
    IniWrite, %FreezeMode%, %SettingsFile%, Freeze, Mode
    IniWrite, % (FreezeEnabled ? 1 : 0), %SettingsFile%, Freeze, Enabled

    IniWrite, %RotationKey%, %SettingsFile%, Rotation, Hotkey
    IniWrite, % (RotationEnabled ? 1 : 0), %SettingsFile%, Rotation, Enabled
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
