; ==========================================================================
;  Prison Life Macro Suite
;  Pressure Jump + Freeze + Rotation + Sprint + Fast Gun Swap + Shuffle Reload
; ==========================================================================
;  - Roblox Sensitivity, Mouse DPI, and Roblox FPS are GLOBAL settings shared
;    across the macros that need them (Pressure Jump spin calc and Rotation
;    flick-pixel calc both read the same Sensitivity value).
;  - Main Gun Slots (slot count + increase/decrease keybinds) is ALSO a
;    GLOBAL setting, shared between Fast Gun Swap and Shuffle Reload, so
;    both macros always cycle through the exact same set of weapon slots.
;  - All macro hotkeys use the "click, then press any key/button" capture
;    method.
;  - Each macro can be individually enabled/disabled.
;  - Fast Gun Swap: trigger key supports Hold or Toggle mode, plus a
;    separate On/Off key to arm/disarm it without opening the GUI (starts
;    OFF by default).
;    Shoot delay is fixed at 1ms.
;  - Shuffle Reload: personalised trigger key, cycles the gun slots pressing
;    Reload after each one. Reload delay is fixed at 0ms.
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
PressureJumpKey     := ""       ; blank = no keybind set
PressureJumpEnabled := false

; --- Freeze ---
FreezeKey          := ""       ; blank = no keybind set
FreezeMode         := "Toggle"  ; "Toggle" or "Hold"
FreezeEnabled      := false

; --- Rotation ---
RotationKey        := ""       ; blank = no keybind set
RotationEnabled    := false

; --- Sprint ---
; Fixed trigger: Shift (not user-rebindable, per design)
SprintEnabled      := false

; --- Main Gun Slots (GLOBAL - shared between Fast Gun Swap & Shuffle Reload) ---
; Slots are simply the first N number-row keys (1,2,3...9,0) - N is GunSlotCount.
GunSlotCount     := 3           ; how many gun slots are cycled through (1-10)
IncreaseSlotKey  := ""          ; blank = no keybind set
DecreaseSlotKey  := ""          ; blank = no keybind set

; --- Fast Gun Swap ---
FastGunSwapKey        := ""     ; blank = no keybind set (trigger)
FastGunSwapOnOffKey := ""     ; blank = no keybind set (on/off toggle while playing)
FastGunSwapMode       := "Hold" ; "Hold" or "Toggle"
FastGunSwapEnabled    := false
FastGunSwapDelayMs    := 1      ; FIXED - locked to 1ms, not user editable
FastGunSwapOn         := false  ; runtime on/off state - starts OFF, armed via the On/Off key
FastGunSwapHolding    := false  ; runtime state, used by Toggle mode's loop

; --- Shuffle Reload ---
ShuffleReloadKey       := ""    ; blank = no keybind set (trigger)
ShuffleReloadEnabled   := false
ShuffleReloadDelayMs   := 0     ; FIXED - locked to 0ms, not user editable

Frozen        := false
SprintActive  := false
Capturing     := false
CaptureTarget := ""             ; "PJ", "Freeze", "Rotation", "FGS", "FGSOnOff", "SR", "IncSlot", or "DecSlot"
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
ApplySprintHotkey()
ApplyFastGunSwapHotkey()
ApplyFastGunSwapOnOffHotkey()
ApplyShuffleReloadHotkey()
ApplyIncreaseSlotHotkey()
ApplyDecreaseSlotHotkey()
SetTimer, WatchRobloxFocus, 300
return

; ==========================================================================
;                                  GUI
; ==========================================================================

BuildGui() {
    global DPI, CS, FPS, PressureJumpKey, PressureJumpEnabled, FreezeKey, FreezeMode, FreezeEnabled
    global RotationKey, RotationEnabled, StartMinimized
    global SprintEnabled
    global DPIInput, CSInput, FPSInput
    global PJEnabledCB, PJHotkeyDisplay, FreezeEnabledCB, FreezeHotkeyDisplay, ModeDD
    global RotEnabledCB, RotHotkeyDisplay, StartMinCB
    global SprEnabledCB
    global GunSlotCount, IncreaseSlotKey, DecreaseSlotKey
    global GunSlotCountInput, IncSlotHotkeyDisplay, DecSlotHotkeyDisplay
    global FastGunSwapKey, FastGunSwapOnOffKey, FastGunSwapMode, FastGunSwapEnabled
    global FGSEnabledCB, FGSHotkeyDisplay, FGSModeDD, FGSOnOffHotkeyDisplay
    global ShuffleReloadKey, ShuffleReloadEnabled
    global SREnabledCB, SRHotkeyDisplay

    PJChecked       := PressureJumpEnabled ? 1 : 0
    FreezeChecked   := FreezeEnabled ? 1 : 0
    RotChecked      := RotationEnabled ? 1 : 0
    SprChecked      := SprintEnabled ? 1 : 0
    FGSChecked      := FastGunSwapEnabled ? 1 : 0
    SRChecked       := ShuffleReloadEnabled ? 1 : 0
    StartMinChecked := StartMinimized ? 1 : 0
    ModeChoice      := (FreezeMode = "Hold") ? 2 : 1
    FGSModeChoice   := (FastGunSwapMode = "Toggle") ? 2 : 1
    PJKeyDisplay    := (PressureJumpKey = "") ? "(none)" : PressureJumpKey
    FreezeKeyDisplay:= (FreezeKey = "") ? "(none)" : FreezeKey
    RotKeyDisplay   := (RotationKey = "") ? "(none)" : RotationKey
    FGSKeyDisplay   := (FastGunSwapKey = "") ? "(none)" : FastGunSwapKey
    FGSOnOffKeyDisplay := (FastGunSwapOnOffKey = "") ? "(none)" : FastGunSwapOnOffKey
    SRKeyDisplay    := (ShuffleReloadKey = "") ? "(none)" : ShuffleReloadKey
    IncSlotKeyDisplay := (IncreaseSlotKey = "") ? "(none)" : IncreaseSlotKey
    DecSlotKeyDisplay := (DecreaseSlotKey = "") ? "(none)" : DecreaseSlotKey

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
    Gui, Add, Text, x20 y46 w440 c%DimColor% BackgroundTrans, Pressure Jump | Freeze | Rotation | Fast Gun Swap | Shuffle Reload
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

    ; ---- Main Gun Slots (GLOBAL - shared by Fast Gun Swap & Shuffle Reload) ----
    Gui, Add, Text, x20 y167 w110 c%DimColor% BackgroundTrans, Gun Slots:
    Gui, Add, Edit, x130 y164 w40 vGunSlotCountInput cWhite, %GunSlotCount%
    Gui, Add, Text, x180 y167 w70 c%DimColor% BackgroundTrans, Increase:
    Gui, Add, Text, x250 y167 vIncSlotHotkeyDisplay w90 c%AccentColor% BackgroundTrans, %IncSlotKeyDisplay%
    Gui, Add, Button, x350 y161 w130 h22 gStartCaptureIncSlot, Set Increase Key
    Gui, Add, Text, x180 y199 w70 c%DimColor% BackgroundTrans, Decrease:
    Gui, Add, Text, x250 y199 vDecSlotHotkeyDisplay w90 c%AccentColor% BackgroundTrans, %DecSlotKeyDisplay%
    Gui, Add, Button, x350 y193 w130 h22 gStartCaptureDecSlot, Set Decrease Key

    ; ---- Tabs: one per macro ----
    Gui, Add, Tab3, x20 y234 w480 h270 c%TextColor%, Pressure Jump|Freeze|Rotation|Sprint|Fast Gun Swap|Shuffle Reload

    Gui, Tab, 1
    Gui, Add, CheckBox, x40 y272 vPJEnabledCB Checked%PJChecked% c%TextColor%, Enable Pressure Jump
    Gui, Add, Text, x40 y304 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y304 vPJHotkeyDisplay w170 c%AccentColor%, %PJKeyDisplay%
    Gui, Add, Button, x40 y332 w420 gStartCapturePJ, Click, then press key/button for Pressure Jump...

    Gui, Tab, 2
    Gui, Add, CheckBox, x40 y272 vFreezeEnabledCB Checked%FreezeChecked% c%TextColor%, Enable Freeze
    Gui, Add, Text, x40 y304 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y304 vFreezeHotkeyDisplay w170 c%AccentColor%, %FreezeKeyDisplay%
    Gui, Add, Button, x40 y332 w420 gStartCaptureFreeze, Click, then press key/button for Freeze...
    Gui, Add, Text, x40 y372 w80 c%DimColor%, Mode:
    Gui, Add, DropDownList, x120 y369 w340 vModeDD Choose%ModeChoice%, Toggle (press once, again to release)|Hold (frozen only while held)

    Gui, Tab, 3
    Gui, Add, CheckBox, x40 y272 vRotEnabledCB Checked%RotChecked% c%TextColor%, Enable Rotation
    Gui, Add, Text, x40 y304 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y304 vRotHotkeyDisplay w170 c%AccentColor%, %RotKeyDisplay%
    Gui, Add, Button, x40 y332 w420 gStartCaptureRotation, Click, then press key/button for Rotation...

    Gui, Tab, 4
    Gui, Add, CheckBox, x40 y272 vSprEnabledCB Checked%SprChecked% c%TextColor%, Enable Toggle Sprint
    Gui, Add, Text, x40 y304 w420 c%DimColor%, Trigger: Shift (fixed, not rebindable)  -  active only while Roblox is focused
    Gui, Add, Text, x40 y336 w420 c%DimColor%, Tap Shift to toggle sprint on, tap again to toggle it off.

    Gui, Tab, 5
    Gui, Add, CheckBox, x40 y272 vFGSEnabledCB Checked%FGSChecked% c%TextColor%, Enable Fast Gun Swap
    Gui, Add, Text, x40 y302 w90 c%DimColor%, Trigger:
    Gui, Add, Text, x130 y302 vFGSHotkeyDisplay w160 c%AccentColor%, %FGSKeyDisplay%
    Gui, Add, Button, x40 y326 w420 h26 gStartCaptureFGS, Click, then press key/button for Fast Gun Swap Trigger...
    Gui, Add, Text, x40 y362 w80 c%DimColor%, Mode:
    Gui, Add, DropDownList, x120 y359 w340 vFGSModeDD Choose%FGSModeChoice%, Hold (repeat while held)|Toggle (press once to start/stop)
    Gui, Add, Text, x40 y394 w90 c%DimColor%, On/Off Key:
    Gui, Add, Text, x130 y394 vFGSOnOffHotkeyDisplay w160 c%AccentColor%, %FGSOnOffKeyDisplay%
    Gui, Add, Button, x40 y418 w420 h26 gStartCaptureFGSOnOff, Click, then press key/button for Fast Gun Swap On/Off...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y452 w420 c%DimColor%, Shoot delay is fixed at 1ms. Fast Gun Swap starts OFF - press the On/Off key to arm it.
    Gui, Add, Text, x40 y470 w420 c%DimColor%, Slot count and its +/- keys are set under Main Gun Slots above (global).
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab, 6
    Gui, Add, CheckBox, x40 y272 vSREnabledCB Checked%SRChecked% c%TextColor%, Enable Shuffle Reload
    Gui, Add, Text, x40 y302 w90 c%DimColor%, Trigger:
    Gui, Add, Text, x130 y302 vSRHotkeyDisplay w160 c%AccentColor%, %SRKeyDisplay%
    Gui, Add, Button, x40 y326 w420 h26 gStartCaptureSR, Click, then press key/button for Shuffle Reload Trigger...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y362 w420 c%DimColor%, Reload delay is fixed at 0ms.
    Gui, Add, Text, x40 y380 w420 c%DimColor%, Slot count and its +/- keys are set under Main Gun Slots above (global).
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab

    Gui, Add, CheckBox, x20 y514 vStartMinCB Checked%StartMinChecked% c%TextColor%, Start minimized (to tray)

    Gui, Add, Button, x20 y546 w235 h32 gSaveSettings Default, Save
    Gui, Add, Button, x265 y546 w235 h32 gGuiCancel, Hide

    Gui, Margin, 20, 20
    Gui, +MinimizeBox
    Gui, Show, w520 h598, Prison Life Macro Settings
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
    NewDPI       := DPIInput
    NewCS        := CSInput
    NewFPS       := FPSInput
    NewSlotCount := GunSlotCountInput

    if (NewDPI = "" or NewCS = "" or NewFPS = "" or NewDPI + 0 = 0 or NewCS + 0 = 0 or NewFPS + 0 = 0) {
        MsgBox, 48, Invalid Input, Please enter valid non-zero numbers for Roblox Sensitivity, Mouse DPI, and Roblox FPS.
        return
    }
    if (NewSlotCount = "" or NewSlotCount + 0 < 1 or NewSlotCount + 0 > 10) {
        MsgBox, 48, Invalid Input, Gun Slots must be a whole number between 1 and 10.
        return
    }

    DPI          := NewDPI
    CS           := NewCS
    FPS          := NewFPS
    GunSlotCount := Round(NewSlotCount)
    PressureJumpEnabled := PJEnabledCB
    FreezeEnabled       := FreezeEnabledCB
    FreezeMode          := InStr(ModeDD, "Hold") ? "Hold" : "Toggle"
    RotationEnabled     := RotEnabledCB
    SprintEnabled       := SprEnabledCB
    FastGunSwapEnabled  := FGSEnabledCB
    FastGunSwapMode     := InStr(FGSModeDD, "Toggle") ? "Toggle" : "Hold"
    ShuffleReloadEnabled:= SREnabledCB
    StartMinimized      := StartMinCB

    RecalculateX()
    RecalcRotationPixels()
    SaveSettingsToFile()
    ApplyPressureJumpHotkey()
    ApplyFreezeHotkey()
    ApplyRotationHotkey()
    ApplySprintHotkey()
    ApplyFastGunSwapHotkey()
    ApplyFastGunSwapOnOffHotkey()
    ApplyShuffleReloadHotkey()
    ApplyIncreaseSlotHotkey()
    ApplyDecreaseSlotHotkey()

    Warnings := ""
    if (PressureJumpEnabled and PressureJumpKey = "")
        Warnings .= "- Pressure Jump is enabled but has no keybind set.`n"
    if (FreezeEnabled and FreezeKey = "")
        Warnings .= "- Freeze is enabled but has no keybind set.`n"
    if (RotationEnabled and RotationKey = "")
        Warnings .= "- Rotation is enabled but has no keybind set.`n"
    if (FastGunSwapEnabled and FastGunSwapKey = "")
        Warnings .= "- Fast Gun Swap is enabled but has no trigger keybind set.`n"
    if (ShuffleReloadEnabled and ShuffleReloadKey = "")
        Warnings .= "- Shuffle Reload is enabled but has no trigger keybind set.`n"
    if (Warnings != "")
        MsgBox, 48, No Keybind Set, %Warnings%`nThose macros won't trigger until you set a keybind on their tab.

    ToolTip, Settings saved
    SetTimer, RemoveToolTip, -700
return

RemoveToolTip:
    ToolTip
return

RecalculateX() {
    ; NOTE: DPI is intentionally NOT part of this formula. mouse_event/SendInput
    ; movement is a synthetic pixel delta injected directly into the input
    ; stack - it is not affected by the physical mouse's DPI setting (that
    ; only matters for a real mouse converting physical motion into counts).
    ; This mirrors RecalcRotationPixels(), which also only depends on
    ; sensitivity. Previously this multiplied by (BaseDPI / DPI), which
    ; silently over/under-scaled the jump whenever DPI != BaseDPI (e.g. at
    ; 400 DPI it doubled the pixel amount), breaking the macro for anyone
    ; not using exactly 800 DPI.
    global Spin, BaseCS, CS, X
    X := Round((Spin * BaseCS) / CS)
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

StartCaptureFGS:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "FGS"
    GuiControl,, FGSHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindFastGunSwapHotkey()
    BeginKeyListen()
return

StartCaptureFGSOnOff:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "FGSOnOff"
    GuiControl,, FGSOnOffHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindFastGunSwapOnOffHotkey()
    BeginKeyListen()
return

StartCaptureSR:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "SR"
    GuiControl,, SRHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindShuffleReloadHotkey()
    BeginKeyListen()
return

StartCaptureIncSlot:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "IncSlot"
    GuiControl,, IncSlotHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindIncreaseSlotHotkey()
    BeginKeyListen()
return

StartCaptureDecSlot:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "DecSlot"
    GuiControl,, DecSlotHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindDecreaseSlotHotkey()
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
            GuiControl,, PJHotkeyDisplay, % KeyDisplay(PressureJumpKey)
        else if (CaptureTarget = "Freeze")
            GuiControl,, FreezeHotkeyDisplay, % KeyDisplay(FreezeKey)
        else if (CaptureTarget = "Rotation")
            GuiControl,, RotHotkeyDisplay, % KeyDisplay(RotationKey)
        else if (CaptureTarget = "FGS")
            GuiControl,, FGSHotkeyDisplay, % KeyDisplay(FastGunSwapKey)
        else if (CaptureTarget = "FGSOnOff")
            GuiControl,, FGSOnOffHotkeyDisplay, % KeyDisplay(FastGunSwapOnOffKey)
        else if (CaptureTarget = "SR")
            GuiControl,, SRHotkeyDisplay, % KeyDisplay(ShuffleReloadKey)
        else if (CaptureTarget = "IncSlot")
            GuiControl,, IncSlotHotkeyDisplay, % KeyDisplay(IncreaseSlotKey)
        else if (CaptureTarget = "DecSlot")
            GuiControl,, DecSlotHotkeyDisplay, % KeyDisplay(DecreaseSlotKey)
    } else {
        if (CaptureTarget = "PJ") {
            PressureJumpKey := Captured
            GuiControl,, PJHotkeyDisplay, % KeyDisplay(PressureJumpKey)
            ApplyPressureJumpHotkey()
        } else if (CaptureTarget = "Freeze") {
            FreezeKey := Captured
            GuiControl,, FreezeHotkeyDisplay, % KeyDisplay(FreezeKey)
            ApplyFreezeHotkey()
        } else if (CaptureTarget = "Rotation") {
            RotationKey := Captured
            GuiControl,, RotHotkeyDisplay, % KeyDisplay(RotationKey)
            ApplyRotationHotkey()
        } else if (CaptureTarget = "FGS") {
            FastGunSwapKey := Captured
            GuiControl,, FGSHotkeyDisplay, % KeyDisplay(FastGunSwapKey)
            ApplyFastGunSwapHotkey()
        } else if (CaptureTarget = "FGSOnOff") {
            FastGunSwapOnOffKey := Captured
            GuiControl,, FGSOnOffHotkeyDisplay, % KeyDisplay(FastGunSwapOnOffKey)
            ApplyFastGunSwapOnOffHotkey()
        } else if (CaptureTarget = "SR") {
            ShuffleReloadKey := Captured
            GuiControl,, SRHotkeyDisplay, % KeyDisplay(ShuffleReloadKey)
            ApplyShuffleReloadHotkey()
        } else if (CaptureTarget = "IncSlot") {
            IncreaseSlotKey := Captured
            GuiControl,, IncSlotHotkeyDisplay, % KeyDisplay(IncreaseSlotKey)
            ApplyIncreaseSlotHotkey()
        } else if (CaptureTarget = "DecSlot") {
            DecreaseSlotKey := Captured
            GuiControl,, DecSlotHotkeyDisplay, % KeyDisplay(DecreaseSlotKey)
            ApplyDecreaseSlotHotkey()
        }
    }
    CaptureTarget := ""
return

KeyDisplay(k) {
    return (k = "") ? "(none)" : k
}

; ==========================================================================
;                         Pressure Jump hotkey/action
; ==========================================================================

UnbindPressureJumpHotkey() {
    global PressureJumpKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, *%PressureJumpKey%, , Off
    Hotkey, IfWinActive
}

ApplyPressureJumpHotkey() {
    global PressureJumpKey, PressureJumpEnabled, TargetProcess
    UnbindPressureJumpHotkey()
    if (PressureJumpEnabled and PressureJumpKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, *%PressureJumpKey%, PressureJumpAction, On
        Hotkey, IfWinActive
    }
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
    global FreezeKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, *%FreezeKey%, , Off
    try Hotkey, *%FreezeKey% up, , Off
    Hotkey, IfWinActive
}

ApplyFreezeHotkey() {
    global FreezeKey, FreezeMode, FreezeEnabled, TargetProcess
    UnbindFreezeHotkey()
    if (!FreezeEnabled or FreezeKey = "")
        return
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    if (FreezeMode = "Hold") {
        Hotkey, *%FreezeKey%, HoldDown, On
        Hotkey, *%FreezeKey% up, HoldUp, On
    } else {
        Hotkey, *%FreezeKey%, ToggleFreeze, On
    }
    Hotkey, IfWinActive
}

ToggleFreeze:
    Frozen := !Frozen
    if (Frozen) {
        SuspendProcess(TargetProcess)
    } else {
        ResumeProcess(TargetProcess)
    }
return

HoldDown:
    if (!Frozen) {
        Frozen := true
        SuspendProcess(TargetProcess)
    }
return

HoldUp:
    if (Frozen) {
        Frozen := false
        ResumeProcess(TargetProcess)
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
    global RotationKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%RotationKey%, , Off
    Hotkey, IfWinActive
}

ApplyRotationHotkey() {
    global RotationKey, RotationEnabled, TargetProcess
    UnbindRotationHotkey()
    if (RotationEnabled and RotationKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%RotationKey%, RotationAction, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
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
;                        Toggle Sprint hotkey/action
; ==========================================================================
; Only active while Roblox (RobloxPlayerBeta.exe) is the foreground window,
; via "Hotkey, IfWinActive, ..." (a run-time equivalent of #IfWinActive that
; works with the dynamic Hotkey command used throughout this script).
; Plain toggle: tap Shift to turn sprint on, tap again to turn it off.

UnbindSprintHotkey() {
    global TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, *Shift, , Off
    Hotkey, IfWinActive
}

ApplySprintHotkey() {
    global SprintEnabled, SprintActive, TargetProcess
    UnbindSprintHotkey()
    if (SprintEnabled) {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, *Shift, ToggleSprint, On
        Hotkey, IfWinActive
    } else if (SprintActive) {
        ; Sprint got disabled while active - release the held key.
        SendInput, {Shift up}
        SprintActive := false
    }
}

ToggleSprint:
    SprintActive := !SprintActive
    if (SprintActive)
        SendInput, {Shift down}
    else
        SendInput, {Shift up}
return

; ---- Safety net: if Roblox loses focus while sprint is active, release
; Shift so it can't bleed held-shift behavior into other windows.
; (Timer is started once in the auto-execute section at the top of the script.)
WatchRobloxFocus:
    if (SprintActive) {
        IfWinNotActive, ahk_exe %TargetProcess%
        {
            SendInput, {Shift up}
            SprintActive := false
        }
    }
return

; ==========================================================================
;                        Main Gun Slots (shared/global)
; ==========================================================================
; Slots are simply the first GunSlotCount number-row keys: 1,2,3...9,0 (0 is
; the 10th slot). Both Fast Gun Swap and Shuffle Reload cycle through the
; exact same slot list, so there's only one place that needs to be tuned.

BuildActiveSlots() {
    global GunSlotCount
    count := GunSlotCount + 0
    if (count < 1)
        count := 1
    if (count > 10)
        count := 10
    slots := []
    Loop, %count% {
        slots.Push((A_Index = 10) ? "0" : A_Index)
    }
    return slots
}

UnbindIncreaseSlotHotkey() {
    global IncreaseSlotKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%IncreaseSlotKey%, , Off
    Hotkey, IfWinActive
}

ApplyIncreaseSlotHotkey() {
    global IncreaseSlotKey, TargetProcess
    UnbindIncreaseSlotHotkey()
    if (IncreaseSlotKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%IncreaseSlotKey%, IncreaseSlotAction, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
}

UnbindDecreaseSlotHotkey() {
    global DecreaseSlotKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%DecreaseSlotKey%, , Off
    Hotkey, IfWinActive
}

ApplyDecreaseSlotHotkey() {
    global DecreaseSlotKey, TargetProcess
    UnbindDecreaseSlotHotkey()
    if (DecreaseSlotKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%DecreaseSlotKey%, DecreaseSlotAction, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
}

IncreaseSlotAction:
    if (GunSlotCount < 10)
        GunSlotCount += 1
    ShowSlotCountFeedback()
return

DecreaseSlotAction:
    if (GunSlotCount > 1)
        GunSlotCount -= 1
    ShowSlotCountFeedback()
return

ShowSlotCountFeedback() {
    global GunSlotCount
    ; Keep the settings GUI's edit box in sync if it happens to be open.
    try GuiControl,, GunSlotCountInput, %GunSlotCount%
    ToolTip, Main Gun Slots: %GunSlotCount%
    SetTimer, RemoveToolTip, -700
}

; ==========================================================================
;                       Fast Gun Swap hotkey/action
; ==========================================================================
; Trigger key can work in two modes:
;   Hold   - swaps+shoots through the active slots for as long as the key
;            is held down.
;   Toggle - press once to start an uninterrupted swap+shoot loop, press
;            again to stop it.
; A separate On/Off key arms/disarms the whole macro on the fly, without
; opening the settings window. It STARTS OFF - the trigger key does nothing
; until you press the On/Off key to turn it on when you're ready to use it.
; Shoot delay is fixed at 1ms.

UnbindFastGunSwapHotkey() {
    global FastGunSwapKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%FastGunSwapKey%, , Off
    Hotkey, IfWinActive
}

ApplyFastGunSwapHotkey() {
    global FastGunSwapKey, FastGunSwapEnabled, TargetProcess
    UnbindFastGunSwapHotkey()
    if (FastGunSwapEnabled and FastGunSwapKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%FastGunSwapKey%, FastGunSwapAction, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
}

UnbindFastGunSwapOnOffHotkey() {
    global FastGunSwapOnOffKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%FastGunSwapOnOffKey%, , Off
    Hotkey, IfWinActive
}

ApplyFastGunSwapOnOffHotkey() {
    global FastGunSwapOnOffKey, FastGunSwapEnabled, TargetProcess
    UnbindFastGunSwapOnOffHotkey()
    if (FastGunSwapEnabled and FastGunSwapOnOffKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%FastGunSwapOnOffKey%, FastGunSwapOnOffToggle, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
}

FastGunSwapOnOffToggle:
    FastGunSwapOn := !FastGunSwapOn
    if (!FastGunSwapOn)
        FastGunSwapHolding := false   ; stop any in-progress Toggle-mode loop
    ToolTip, % "Fast Gun Swap: " . (FastGunSwapOn ? "ON" : "OFF")
    SetTimer, RemoveToolTip, -700
return

FastGunSwapAction:
    if (!FastGunSwapEnabled or !FastGunSwapOn)
        return

    slots := BuildActiveSlots()
    if (slots.Length() = 0)
        return

    if (FastGunSwapMode = "Hold") {
        while (GetKeyState(FastGunSwapKey, "P")) {
            for _, k in slots {
                if (!GetKeyState(FastGunSwapKey, "P"))
                    break
                SendInput, {Blind}{%k%}
                Sleep, %FastGunSwapDelayMs%
                Click
                Sleep, %FastGunSwapDelayMs%
            }
        }
    } else {
        FastGunSwapHolding := !FastGunSwapHolding
        if (FastGunSwapHolding)
            SetTimer, FastGunSwapLoop, -1
    }
return

FastGunSwapLoop:
    if (!FastGunSwapHolding or !FastGunSwapEnabled or !FastGunSwapOn) {
        FastGunSwapHolding := false
        return
    }

    slots := BuildActiveSlots()
    for _, k in slots {
        if (!FastGunSwapHolding)
            break
        SendInput, {Blind}{%k%}
        Sleep, %FastGunSwapDelayMs%
        Click
        Sleep, %FastGunSwapDelayMs%
    }

    if (FastGunSwapHolding)
        SetTimer, FastGunSwapLoop, -1
return

; ==========================================================================
;                       Shuffle Reload hotkey/action
; ==========================================================================
; Cycles through the active slots, pressing each slot key then Reload.
; Reload delay is fixed at 0ms.

UnbindShuffleReloadHotkey() {
    global ShuffleReloadKey, TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, ~*%ShuffleReloadKey%, , Off
    Hotkey, IfWinActive
}

ApplyShuffleReloadHotkey() {
    global ShuffleReloadKey, ShuffleReloadEnabled, TargetProcess
    UnbindShuffleReloadHotkey()
    if (ShuffleReloadEnabled and ShuffleReloadKey != "") {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, ~*%ShuffleReloadKey%, ShuffleReloadAction, On   ; "~" lets the key/button still pass through to Roblox
        Hotkey, IfWinActive
    }
}

ShuffleReloadAction:
    if (!ShuffleReloadEnabled)
        return

    slots := BuildActiveSlots()
    for _, k in slots {
        SendInput, {Blind}{%k%}
        if (ShuffleReloadDelayMs > 0)
            Sleep, %ShuffleReloadDelayMs%
        SendInput, {Blind}r
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
    global SprintEnabled
    global GunSlotCount, IncreaseSlotKey, DecreaseSlotKey
    global FastGunSwapKey, FastGunSwapOnOffKey, FastGunSwapMode, FastGunSwapEnabled
    global ShuffleReloadKey, ShuffleReloadEnabled

    IfExist, %SettingsFile%
    {
        IniRead, DPI, %SettingsFile%, General, DPI, 800
        IniRead, CS, %SettingsFile%, General, Sensitivity, 0.123
        IniRead, FPS, %SettingsFile%, General, FPS, 60
        IniRead, StartMinimized, %SettingsFile%, General, StartMinimized, 0

        IniRead, PressureJumpKey, %SettingsFile%, PressureJump, Hotkey, %A_Space%
        IniRead, PressureJumpEnabled, %SettingsFile%, PressureJump, Enabled, 0

        IniRead, FreezeKey, %SettingsFile%, Freeze, Hotkey, %A_Space%
        IniRead, FreezeMode, %SettingsFile%, Freeze, Mode, Toggle
        IniRead, FreezeEnabled, %SettingsFile%, Freeze, Enabled, 0

        IniRead, RotationKey, %SettingsFile%, Rotation, Hotkey, %A_Space%
        IniRead, RotationEnabled, %SettingsFile%, Rotation, Enabled, 0

        IniRead, SprintEnabled, %SettingsFile%, Sprint, Enabled, 0

        IniRead, GunSlotCount, %SettingsFile%, MainGunSlots, Count, 3
        IniRead, IncreaseSlotKey, %SettingsFile%, MainGunSlots, IncreaseKey, %A_Space%
        IniRead, DecreaseSlotKey, %SettingsFile%, MainGunSlots, DecreaseKey, %A_Space%

        IniRead, FastGunSwapKey, %SettingsFile%, FastGunSwap, Hotkey, %A_Space%
        IniRead, FastGunSwapOnOffKey, %SettingsFile%, FastGunSwap, OnOffHotkey, %A_Space%
        IniRead, FastGunSwapMode, %SettingsFile%, FastGunSwap, Mode, Hold
        IniRead, FastGunSwapEnabled, %SettingsFile%, FastGunSwap, Enabled, 0

        IniRead, ShuffleReloadKey, %SettingsFile%, ShuffleReload, Hotkey, %A_Space%
        IniRead, ShuffleReloadEnabled, %SettingsFile%, ShuffleReload, Enabled, 0
    }
    PressureJumpKey       := Trim(PressureJumpKey)
    FreezeKey             := Trim(FreezeKey)
    RotationKey           := Trim(RotationKey)
    IncreaseSlotKey       := Trim(IncreaseSlotKey)
    DecreaseSlotKey       := Trim(DecreaseSlotKey)
    FastGunSwapKey        := Trim(FastGunSwapKey)
    FastGunSwapOnOffKey := Trim(FastGunSwapOnOffKey)
    ShuffleReloadKey      := Trim(ShuffleReloadKey)
    PressureJumpEnabled := (PressureJumpEnabled = 1 || PressureJumpEnabled = "true")
    FreezeEnabled       := (FreezeEnabled = 1 || FreezeEnabled = "true")
    RotationEnabled     := (RotationEnabled = 1 || RotationEnabled = "true")
    SprintEnabled       := (SprintEnabled = 1 || SprintEnabled = "true")
    FastGunSwapEnabled  := (FastGunSwapEnabled = 1 || FastGunSwapEnabled = "true")
    ShuffleReloadEnabled:= (ShuffleReloadEnabled = 1 || ShuffleReloadEnabled = "true")
    StartMinimized      := (StartMinimized = 1 || StartMinimized = "true")

    GunSlotCount := GunSlotCount + 0
    if (GunSlotCount < 1)
        GunSlotCount := 1
    if (GunSlotCount > 10)
        GunSlotCount := 10
    if (FastGunSwapMode != "Hold" and FastGunSwapMode != "Toggle")
        FastGunSwapMode := "Hold"
}

SaveSettingsToFile() {
    global SettingsFile, DPI, CS, FPS, StartMinimized
    global PressureJumpKey, PressureJumpEnabled
    global FreezeKey, FreezeMode, FreezeEnabled
    global RotationKey, RotationEnabled
    global SprintEnabled
    global GunSlotCount, IncreaseSlotKey, DecreaseSlotKey
    global FastGunSwapKey, FastGunSwapOnOffKey, FastGunSwapMode, FastGunSwapEnabled
    global ShuffleReloadKey, ShuffleReloadEnabled

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

    IniWrite, % (SprintEnabled ? 1 : 0), %SettingsFile%, Sprint, Enabled

    IniWrite, %GunSlotCount%, %SettingsFile%, MainGunSlots, Count
    IniWrite, %IncreaseSlotKey%, %SettingsFile%, MainGunSlots, IncreaseKey
    IniWrite, %DecreaseSlotKey%, %SettingsFile%, MainGunSlots, DecreaseKey

    IniWrite, %FastGunSwapKey%, %SettingsFile%, FastGunSwap, Hotkey
    IniWrite, %FastGunSwapOnOffKey%, %SettingsFile%, FastGunSwap, OnOffHotkey
    IniWrite, %FastGunSwapMode%, %SettingsFile%, FastGunSwap, Mode
    IniWrite, % (FastGunSwapEnabled ? 1 : 0), %SettingsFile%, FastGunSwap, Enabled

    IniWrite, %ShuffleReloadKey%, %SettingsFile%, ShuffleReload, Hotkey
    IniWrite, % (ShuffleReloadEnabled ? 1 : 0), %SettingsFile%, ShuffleReload, Enabled
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
