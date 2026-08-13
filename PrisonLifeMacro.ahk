; ==========================================================================
;  Prison Life Macro Suite
;  Pressure Jump + Freeze + Rotation + Sprint + Fast Gun Swap + Shuffle Reload
;  + Global Suspend (suspend/resume ALL macros with one key)
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
;  - Sprint: fixed Shift toggle - tap once to hold Shift (sprint), tap again
;    to release (stop sprint). Repeats forever. Only Shift itself is ever
;    sent - no numbers, no symbols - so the number-row weapon/item slots and
;    the chat are never disturbed while toggling sprint.
;  - Global Suspend: personalisable keybind (set in the GUI) that suspends
;    all macros at once; press it again to resume. Works from any window.
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
; A_LocalAppData can come back blank in some environments (e.g. certain
; elevated/service contexts where the user profile isn't fully loaded).
; When that happens, "" . "\PrisonLifeMacro" collapses to "\PrisonLifeMacro",
; which AHK resolves against the current drive root (C:\PrisonLifeMacro) -
; NOT the intended %localappdata%\PrisonLifeMacro. Fall back through the
; LOCALAPPDATA env var, then rebuild it from %USERPROFILE% as a last resort.
ResolvedLocalAppData := A_LocalAppData
if (ResolvedLocalAppData = "") {
    EnvGet, ResolvedLocalAppData, LOCALAPPDATA
}
if (ResolvedLocalAppData = "") {
    EnvGet, FallbackUserProfile, USERPROFILE
    ResolvedLocalAppData := FallbackUserProfile . "\AppData\Local"
}

SettingsDir  := ResolvedLocalAppData . "\PrisonLifeMacro"
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
; Fixed trigger: Shift (not user-rebindable, per design). Pure toggle:
; tap once = hold Shift (sprint), tap again = release (stop), repeats.
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

; --- Global Suspend (all macros) ---
GlobalSuspendKey    := ""     ; blank = no keybind set
GlobalSuspended     := false  ; true while ALL macros are suspended
LastSuspendToggle   := 0      ; tick of the last suspend toggle (debounce)

Frozen        := false
SprintHeld    := false  ; true while the sprint toggle is holding Shift down (released by next tap, disable, suspend, or focus loss)
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
ApplyAllMacros()
ApplyGlobalSuspendHotkey()
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
    global GlobalSuspendKey, GSuspendHotkeyDisplay
    global FastGunSwapKey, FastGunSwapOnOffKey, FastGunSwapMode, FastGunSwapEnabled
    global FGSEnabledCB, FGSHotkeyDisplay, FGSModeDD, FGSOnOffHotkeyDisplay
    global ShuffleReloadKey, ShuffleReloadEnabled
    global SREnabledCB, SRHotkeyDisplay
    global GuiHwnd
    global EdgeTop, EdgeBot, EdgeLef, EdgeRig

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
    GSuspendKeyDisplay := (GlobalSuspendKey = "") ? "(none)" : GlobalSuspendKey

    ; ---- Dark "Prison Life" theme ----
    ; Background: near-black charcoal. Accent: cell-block orange/red.
    AccentColor := "FF7A1A"
    AccentSoft  := "FFA75C"
    DimColor    := "9A9A9A"
    TextColor   := "E8E8E8"

    Gui, +LastFound
    GuiHwnd := WinExist()          ; stored for the custom title bar drag (WM_NCHITTEST)
    Gui, Color, 141414, 1E1E1E
    ; No OS title bar: the header doubles as a drag handle, and the two
    ; traffic-light dots (red = close, yellow = minimize to tray) replace the
    ; standard window buttons.
    Gui, -Caption
    OnMessage(0x0084, "WM_NCHITTEST")
    Gui, Font, s10 Norm, Segoe UI

    ; ---- Header: logo + title banner ----
    IfExist, %A_ScriptDir%\PrisonLifeMacro.ico
    {
        Gui, Add, Picture, x22 y20 w84 h84 Icon1, %A_ScriptDir%\PrisonLifeMacro.ico
    }
    Gui, Font, s17 Bold, Segoe UI
    Gui, Add, Text, x122 y22 w560 c%AccentColor% BackgroundTrans, PRISON LIFE MACRO SUITE
    Gui, Font, s9 Norm, Segoe UI
    Gui, Add, Text, x122 y56 w560 c%TextColor% BackgroundTrans, Pressure Jump  |  Freeze  |  Rotation  |  Sprint  |  Fast Gun Swap  |  Shuffle Reload
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x122 y78 w560 c%DimColor% BackgroundTrans, Shift-tap sprint toggle   -   Global suspend key   -   One-click keybind captures
    ; Accent divider under the header
    Gui, Add, Progress, x20 y110 w660 h4 Range0-100 c%AccentColor% Background141414, 100

    ; ---- Traffic-light window buttons (top-right corner) ----
    ; Red dot: completely close the macro suite. Yellow dot: minimize to tray.
    DotClose := CreateDotBitmap(18, 0x0000FF)   ; red
    DotMin   := CreateDotBitmap(18, 0x00D4FF)   ; yellow
    ; Yellow dot (left): minimize to tray. Red dot (right, far corner): close.
    ; (the dot Picture controls are added AFTER the border strips so they stay on top)

    ; ---- GLOBAL SETTINGS panel ----
    Gui, Font, s10 Bold, Segoe UI
    Gui, Add, GroupBox, x20 y124 w660 h112 c%DimColor%, GLOBAL SETTINGS
    Gui, Font, s10 Norm, Segoe UI
    Gui, Add, Text, x40 y150 w80 c%DimColor% BackgroundTrans, Sensitivity:
    Gui, Add, Edit, x130 y147 w125 vCSInput cWhite, %CS%
    Gui, Add, Text, x285 y150 w80 c%DimColor% BackgroundTrans, Mouse DPI:
    Gui, Add, Edit, x375 y147 w125 vDPIInput cWhite, %DPI%
    Gui, Add, Text, x530 y150 w80 c%DimColor% BackgroundTrans, Roblox FPS:
    Gui, Add, Edit, x615 y147 w55 vFPSInput cWhite, %FPS%
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y182 w620 c%DimColor% BackgroundTrans, Shared by Pressure Jump and Rotation - sensitivity drives the spin/flick pixel math. DPI and FPS are stored for reference.
    Gui, Font, s10 Norm, Segoe UI

    ; ---- MAIN GUN SLOTS panel ----
    Gui, Font, s10 Bold, Segoe UI
    Gui, Add, GroupBox, x20 y248 w660 h104 c%DimColor%, MAIN GUN SLOTS  (shared by Fast Gun Swap & Shuffle Reload)
    Gui, Font, s10 Norm, Segoe UI
    Gui, Add, Text, x40 y272 w110 c%DimColor% BackgroundTrans, Gun Slots:
    Gui, Add, Edit, x160 y269 w50 vGunSlotCountInput cWhite, %GunSlotCount%
    Gui, Add, Text, x250 y272 w60 c%DimColor% BackgroundTrans, Increase:
    Gui, Add, Text, x315 y272 vIncSlotHotkeyDisplay w120 c%AccentColor% BackgroundTrans, %IncSlotKeyDisplay%
    Gui, Add, Button, x455 y266 w180 h22 gStartCaptureIncSlot, Set Increase Key
    Gui, Add, Text, x250 y302 w60 c%DimColor% BackgroundTrans, Decrease:
    Gui, Add, Text, x315 y302 vDecSlotHotkeyDisplay w120 c%AccentColor% BackgroundTrans, %DecSlotKeyDisplay%
    Gui, Add, Button, x455 y296 w180 h22 gStartCaptureDecSlot, Set Decrease Key
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y326 w620 c%DimColor% BackgroundTrans, Slots are the first N number-row keys (1-9, 0 = 10th slot). Both macros cycle the exact same slot list.
    Gui, Font, s10 Norm, Segoe UI

    ; ---- GLOBAL SUSPEND panel ----
    Gui, Font, s10 Bold, Segoe UI
    Gui, Add, GroupBox, x20 y360 w660 h104 c%DimColor%, GLOBAL SUSPEND / RESUME
    Gui, Font, s10 Norm, Segoe UI
    Gui, Add, Text, x40 y386 w110 c%DimColor% BackgroundTrans, Suspend Key:
    Gui, Add, Text, x160 y386 vGSuspendHotkeyDisplay w140 c%AccentColor% BackgroundTrans, %GSuspendKeyDisplay%
    Gui, Add, Button, x455 y380 w180 h22 gStartCaptureGSuspend, Set Suspend Key
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y412 w620 c%DimColor% BackgroundTrans, Press once to suspend ALL macros, press again to resume. Works from any window - even while sprinting.
    Gui, Add, Text, x40 y430 w620 c%DimColor% BackgroundTrans, Held sprint Shift and Freeze are released and gun-swap loops stop. Keys pass through to the game while suspended.
    Gui, Font, s10 Norm, Segoe UI

    ; ---- Tabs: one per macro ----
    Gui, Add, Tab3, x20 y472 w660 h280 c%TextColor%, Pressure Jump|Freeze|Rotation|Sprint|Fast Gun Swap|Shuffle Reload

    Gui, Tab, 1
    Gui, Add, CheckBox, x40 y500 vPJEnabledCB Checked%PJChecked% c%TextColor%, Enable Pressure Jump
    Gui, Add, Text, x40 y532 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y532 vPJHotkeyDisplay w180 c%AccentColor%, %PJKeyDisplay%
    Gui, Add, Button, x40 y560 w600 gStartCapturePJ, Click, then press key/button for Pressure Jump...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y598 w600 c%DimColor%, Hold-to-run jump. Spins the camera using the shared Sensitivity value.
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab, 2
    Gui, Add, CheckBox, x40 y500 vFreezeEnabledCB Checked%FreezeChecked% c%TextColor%, Enable Freeze
    Gui, Add, Text, x40 y532 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y532 vFreezeHotkeyDisplay w180 c%AccentColor%, %FreezeKeyDisplay%
    Gui, Add, Button, x40 y560 w600 gStartCaptureFreeze, Click, then press key/button for Freeze...
    Gui, Add, Text, x40 y600 w80 c%DimColor%, Mode:
    Gui, Add, DropDownList, x120 y596 w520 vModeDD Choose%ModeChoice%, Toggle (press once, again to release)|Hold (frozen only while held)

    Gui, Tab, 3
    Gui, Add, CheckBox, x40 y500 vRotEnabledCB Checked%RotChecked% c%TextColor%, Enable Rotation
    Gui, Add, Text, x40 y532 w80 c%DimColor%, Keybind:
    Gui, Add, Text, x120 y532 vRotHotkeyDisplay w180 c%AccentColor%, %RotKeyDisplay%
    Gui, Add, Button, x40 y560 w600 gStartCaptureRotation, Click, then press key/button for Rotation...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y598 w600 c%DimColor%, Wallhop flick. Camera flick pixel amount comes from the shared Sensitivity.
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab, 4
    Gui, Add, CheckBox, x40 y500 vSprEnabledCB Checked%SprChecked% c%TextColor%, Enable Toggle Sprint
    Gui, Add, Text, x40 y532 w600 c%DimColor%, Trigger: Shift (fixed, not rebindable)  -  active only while Roblox is focused
    Gui, Add, Text, x40 y562 w600 c%DimColor%, Tap Shift: hold Shift (sprint). Tap again: release Shift (stop). Repeats forever.
    Gui, Add, Text, x40 y588 w600 c%DimColor%, Only Shift itself is pressed - number/item slot keys and symbols are never touched.

    Gui, Tab, 5
    Gui, Add, CheckBox, x40 y500 vFGSEnabledCB Checked%FGSChecked% c%TextColor%, Enable Fast Gun Swap
    Gui, Add, Text, x40 y530 w90 c%DimColor%, Trigger:
    Gui, Add, Text, x130 y530 vFGSHotkeyDisplay w180 c%AccentColor%, %FGSKeyDisplay%
    Gui, Add, Button, x320 y528 w320 h26 gStartCaptureFGS, Click, then press key/button for Fast Gun Swap Trigger...
    Gui, Add, Text, x40 y566 w80 c%DimColor%, Mode:
    Gui, Add, DropDownList, x120 y562 w520 vFGSModeDD Choose%FGSModeChoice%, Hold (repeat while held)|Toggle (press once to start/stop)
    Gui, Add, Text, x40 y600 w90 c%DimColor%, On/Off Key:
    Gui, Add, Text, x130 y600 vFGSOnOffHotkeyDisplay w180 c%AccentColor%, %FGSOnOffKeyDisplay%
    Gui, Add, Button, x320 y598 w320 h26 gStartCaptureFGSOnOff, Click, then press key/button for Fast Gun Swap On/Off...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y636 w600 c%DimColor%, Shoot delay is fixed at 1ms. Fast Gun Swap starts OFF - press the On/Off key to arm it.
    Gui, Add, Text, x40 y654 w600 c%DimColor%, Slot count and its +/- keys are set under Main Gun Slots above (global).
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab, 6
    Gui, Add, CheckBox, x40 y500 vSREnabledCB Checked%SRChecked% c%TextColor%, Enable Shuffle Reload
    Gui, Add, Text, x40 y530 w90 c%DimColor%, Trigger:
    Gui, Add, Text, x130 y530 vSRHotkeyDisplay w180 c%AccentColor%, %SRKeyDisplay%
    Gui, Add, Button, x320 y528 w320 h26 gStartCaptureSR, Click, then press key/button for Shuffle Reload Trigger...
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x40 y572 w600 c%DimColor%, Reload delay is fixed at 0ms.
    Gui, Add, Text, x40 y590 w600 c%DimColor%, Slot count and its +/- keys are set under Main Gun Slots above (global).
    Gui, Font, s10 Norm, Segoe UI

    Gui, Tab

    Gui, Add, CheckBox, x20 y784 vStartMinCB Checked%StartMinChecked% c%TextColor%, Start minimized (to tray)
    Gui, Font, s8 Norm, Segoe UI
    Gui, Add, Text, x240 y786 w440 c%DimColor% BackgroundTrans, Target: RobloxPlayerBeta.exe   -   Settings: %localappdata%\PrisonLifeMacro\settings.ini
    Gui, Font, s10 Norm, Segoe UI

    Gui, Add, Button, x20 y816 w320 h34 gSaveSettings Default, Save Settings
    Gui, Add, Button, x360 y816 w320 h34 gGuiCancel, Hide to Tray

    ; ---- 1px white outline + rounded corners ----
    ; The top/bottom strips are 9px tall so they can carry the white corner
    ; arcs that follow the rounded window region; everything else in the
    ; strips is the GUI background color so they blend in.
    EdgeTop := CreateRoundedEdgeBitmap(700, 9, 0xFFFFFF, "top")
    EdgeBot := CreateRoundedEdgeBitmap(700, 9, 0xFFFFFF, "bottom")
    EdgeLef := CreateSolidBitmap(1, 866, 0xFFFFFF)
    EdgeRig := CreateSolidBitmap(1, 866, 0xFFFFFF)
    Gui, Add, Picture, x0 y0 w700 h9 vEdgeTop, HBITMAP:*%EdgeTop%
    Gui, Add, Picture, x0 y857 w700 h9 vEdgeBot, HBITMAP:*%EdgeBot%
    Gui, Add, Picture, x0 y0 w1 h866 vEdgeLef, HBITMAP:*%EdgeLef%
    Gui, Add, Picture, x699 y0 w1 h866 vEdgeRig, HBITMAP:*%EdgeRig%

    ; Traffic-light window buttons - added after the strips so they sit on top.
    Gui, Add, Picture, x646 y10 w18 h18 gDotHide, HBITMAP:*%DotMin%
    Gui, Add, Picture, x670 y10 w18 h18 gDotExit, HBITMAP:*%DotClose%

    Gui, Margin, 20, 20
    Gui, Show, w700 h866, Prison Life Macro Settings
    WinSet, Region, 0-0 W701 H867 R16-16, ahk_id %GuiHwnd%
}

; ==========================================================================
;                    Custom title bar (traffic-light dots)
; ==========================================================================

CreateDotBitmap(d, colorBGR) {
    ; Creates a square bitmap filled with the GUI background color and a
    ; filled circle of the given color - used for the red/yellow window dots.
    hbm := DllCall("CreateBitmap", "Int", d, "Int", d, "UInt", 1, "UInt", 32, "Ptr", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    hbmOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm)
    hpen := DllCall("CreatePen", "Int", 5, "Int", 0, "UInt", 0, "Ptr")   ; PS_NULL - no outline
    hpenOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hpen)
    hbr := DllCall("CreateSolidBrush", "UInt", 0x141414, "Ptr")          ; GUI background
    hbrOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbr)
    DllCall("Rectangle", "Ptr", hdc, "Int", 0, "Int", 0, "Int", d, "Int", d)
    DllCall("DeleteObject", "Ptr", hbr)
    hbr := DllCall("CreateSolidBrush", "UInt", colorBGR, "Ptr")
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbr)
    DllCall("Ellipse", "Ptr", hdc, "Int", 1, "Int", 1, "Int", d - 1, "Int", d - 1)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbrOld)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hpenOld)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbmOld)
    DllCall("DeleteObject", "Ptr", hbr)
    DllCall("DeleteObject", "Ptr", hpen)
    DllCall("DeleteDC", "Ptr", hdc)
    return hbm
}

CreateSolidBitmap(w, h, colorBGR) {
    ; Creates a solid-color bitmap - used for the 1px white window outline.
    hbm := DllCall("CreateBitmap", "Int", w, "Int", h, "UInt", 1, "UInt", 32, "Ptr", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    hbmOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm)
    hbr := DllCall("CreateSolidBrush", "UInt", colorBGR, "Ptr")
    hbrOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbr)
    DllCall("PatBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", 0x00F00021)   ; PATCOPY
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbrOld)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbmOld)
    DllCall("DeleteObject", "Ptr", hbr)
    DllCall("DeleteDC", "Ptr", hdc)
    return hbm
}

CreateRoundedEdgeBitmap(w, h, colorBGR, side) {
    ; 1px outline along a window edge INCLUDING the rounded-corner arcs, so
    ; the white border follows the curve of the window region. AHK's
    ; "R16-16" region option creates a 16px corner ellipse, i.e. radius 8,
    ; so the arcs are drawn with r = 8. All other pixels are the GUI
    ; background (0x141414) so the strip blends in.
    ; side = "top" or "bottom" (the left/right edges stay straight 1px strips).
    r := 8
    if (side = "top") {
        yEdge := 0
        cy1 := r, cy2 := r     ; corner circle centers
    } else {
        yEdge := h - 1
        cy1 := 0, cy2 := 0     ; bottom strip starts at window bottom minus r
    }
    hbm := DllCall("CreateBitmap", "Int", w, "Int", h, "UInt", 1, "UInt", 32, "Ptr", 0, "Ptr")
    hdc := DllCall("CreateCompatibleDC", "Ptr", 0, "Ptr")
    hbmOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbm)
    hbr := DllCall("CreateSolidBrush", "UInt", 0x141414, "Ptr")          ; GUI background
    hbrOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hbr)
    DllCall("PatBlt", "Ptr", hdc, "Int", 0, "Int", 0, "Int", w, "Int", h, "UInt", 0x00F00021)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbrOld)
    DllCall("DeleteObject", "Ptr", hbr)
    ; straight edge between the two corner circles
    hpen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", colorBGR, "Ptr")   ; PS_SOLID 1px
    hpenOld := DllCall("SelectObject", "Ptr", hdc, "Ptr", hpen)
    DllCall("MoveToEx", "Ptr", hdc, "Int", r, "Int", yEdge, "Ptr", 0)
    DllCall("LineTo", "Ptr", hdc, "Int", w - 1 - r, "Int", yEdge)
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hpenOld)
    DllCall("DeleteObject", "Ptr", hpen)
    ; corner arcs: paint the pixels whose centers lie on the r8 boundary
    ; band (49..66), matching the window region's own rasterization
    Loop, 9 {
        yy := A_Index - 1
        Loop, 9 {
            xx := A_Index - 1
            dx1 := xx + 0.5 - r
            dy1 := yy + 0.5 - cy1
            d2 := dx1 * dx1 + dy1 * dy1
            if (d2 >= 49 && d2 <= 66)
                DllCall("SetPixelV", "Ptr", hdc, "Int", xx, "Int", yy, "UInt", colorBGR)
            dx2 := r - xx + 0.5
            d2 := dx2 * dx2 + dy1 * dy1
            if (d2 >= 49 && d2 <= 66)
                DllCall("SetPixelV", "Ptr", hdc, "Int", w - 1 - xx, "Int", yy, "UInt", colorBGR)
        }
    }
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hbmOld)
    DllCall("DeleteDC", "Ptr", hdc)
    return hbm
}

WM_NCHITTEST(wParam, lParam) {
    ; Since the OS title bar is removed, the header area acts as the drag
    ; handle. The two dot buttons are excluded so their g-labels still fire.
    global GuiHwnd
    x := lParam & 0xFFFF
    y := lParam >> 16
    WinGetPos, wx, wy, , , ahk_id %GuiHwnd%
    cx := x - wx
    cy := y - wy
    if (cx >= 646 and cx <= 688 and cy >= 10 and cy <= 28)
        return 1    ; HTCLIENT - let the dot picture receive the click
    if (cy < 110)
        return 2    ; HTCAPTION - drag the window from the header
    return 1        ; HTCLIENT everywhere else
}

DotExit:
    ; Red dot - completely close the whole macro suite.
    DllCall("Winmm\timeEndPeriod", "UInt", 1)
    ExitApp
return

DotHide:
    ; Yellow dot - hide the settings window to the tray.
    Gui, Hide
return

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
    ; If all macros are currently suspended, keep them suspended after saving.
    if (GlobalSuspended)
        SuspendAllMacros()
    else
        ApplyAllMacros()

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

StartCaptureGSuspend:
    if (Capturing)
        return
    Capturing := true
    CaptureTarget := "GSuspend"
    GuiControl,, GSuspendHotkeyDisplay, Press a key or click a mouse button... (Esc cancels)
    UnbindGlobalSuspendHotkey()
    BeginKeyListen()
return

BeginKeyListen() {
    global CaptureList, GlobalSuspendKey
    CaptureList := BuildKeyList()
    ; Temporarily unbind the suspend key so it can't fire mid-capture.
    try Hotkey, *%GlobalSuspendKey%, , Off
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
        else if (CaptureTarget = "GSuspend")
            GuiControl,, GSuspendHotkeyDisplay, % KeyDisplay(GlobalSuspendKey)
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
        } else if (CaptureTarget = "GSuspend") {
            GlobalSuspendKey := Captured
            GuiControl,, GSuspendHotkeyDisplay, % KeyDisplay(GlobalSuspendKey)
            ApplyGlobalSuspendHotkey()
        }
    }
    CaptureTarget := ""
    ; Re-bind the suspend key (BeginKeyListen unbinds it for every capture).
    ApplyGlobalSuspendHotkey()
    ; If all macros are suspended, re-unbind anything a captured key just
    ; re-applied, so the suspension stays in effect.
    if (GlobalSuspended)
        SuspendAllMacros()
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
; Pure toggle on every Shift tap:
;   tap #1: sends {Shift down} - Roblox starts sprinting
;   tap #2: sends {Shift up}   - Roblox stops sprinting
;   ...and so on, alternating forever.
; The physical Shift key is consumed by the hotkey (no "*" prefix), so the
; game only ever sees the synthetic events this macro sends. Nothing else is
; pressed - no numbers, no symbols - so the number-row weapon/item slot keys
; (1-0) and the chat are never disturbed while toggling sprint.

UnbindSprintHotkey() {
    global TargetProcess
    Hotkey, IfWinActive, ahk_exe %TargetProcess%
    try Hotkey, Shift, , Off
    Hotkey, IfWinActive
}

ApplySprintHotkey() {
    global SprintEnabled, SprintHeld, TargetProcess
    UnbindSprintHotkey()
    if (SprintEnabled) {
        Hotkey, IfWinActive, ahk_exe %TargetProcess%
        Hotkey, Shift, ToggleSprint, On   ; no "*" - the physical key is blocked so the game only gets our toggle events
        Hotkey, IfWinActive
    } else if (SprintHeld) {
        ; Sprint got disabled mid-toggle - release the held key.
        SendInput, {Shift up}
        SprintHeld := false
    }
}

ToggleSprint:
    if (SprintHeld) {
        SendInput, {Shift up}
        SprintHeld := false
    } else {
        SendInput, {Shift down}
        SprintHeld := true
    }
return

; ---- Safety net: if Roblox loses focus while mid-hold, release Shift so it
; can't bleed held-shift behavior into other windows.
; (Timer is started once in the auto-execute section at the top of the script.)
WatchRobloxFocus:
    if (SprintHeld) {
        IfWinNotActive, ahk_exe %TargetProcess%
        {
            SendInput, {Shift up}
            SprintHeld := false
        }
    }
return

; ==========================================================================
;                  Global Suspend / Resume (all macros)
; ==========================================================================
; A personalisable hotkey (set in the GUI) that suspends or resumes every
; macro at once. While suspended all macro hotkeys are unbound, so the keys
; pass through to the game normally (e.g. you can still hold Shift to sprint
; by hand). Anything being held at suspend time (Shift, Freeze, a gun-swap
; loop) is released/stopped first. The suspend key itself is never unbound,
; so it always works - even mid-suspension. Works from any window.

UnbindGlobalSuspendHotkey() {
    global GlobalSuspendKey
    try Hotkey, *%GlobalSuspendKey%, , Off
}

ApplyGlobalSuspendHotkey() {
    global GlobalSuspendKey
    UnbindGlobalSuspendHotkey()
    ; "*" wildcard: the hotkey must fire even while Shift (sprint) or any
    ; other modifier is held - a plain modifier-only hotkey like LAlt would
    ; be treated as "Shift+Alt" while sprinting and get swallowed.
    if (GlobalSuspendKey != "")
        Hotkey, *%GlobalSuspendKey%, ToggleGlobalSuspend, On
}

ApplyAllMacros() {
    ApplyPressureJumpHotkey()
    ApplyFreezeHotkey()
    ApplyRotationHotkey()
    ApplySprintHotkey()
    ApplyFastGunSwapHotkey()
    ApplyFastGunSwapOnOffHotkey()
    ApplyShuffleReloadHotkey()
    ApplyIncreaseSlotHotkey()
    ApplyDecreaseSlotHotkey()
}

SuspendAllMacros() {
    global GlobalSuspended, SprintHeld, Frozen, FastGunSwapHolding, TargetProcess
    GlobalSuspended := true
    if (SprintHeld) {
        SendInput, {Shift up}
        SprintHeld := false
    }
    if (Frozen) {
        Frozen := false
        ResumeProcess(TargetProcess)
    }
    FastGunSwapHolding := false
    UnbindPressureJumpHotkey()
    UnbindFreezeHotkey()
    UnbindRotationHotkey()
    UnbindSprintHotkey()
    UnbindFastGunSwapHotkey()
    UnbindFastGunSwapOnOffHotkey()
    UnbindShuffleReloadHotkey()
    UnbindIncreaseSlotHotkey()
    UnbindDecreaseSlotHotkey()
}

ToggleGlobalSuspend:
    ; Wait for the physical key release first: modifier-key hotkeys need the
    ; key to be fully up before the next press can be registered cleanly.
    KeyWait, %GlobalSuspendKey%
    ; Debounce: a modifier hotkey can occasionally double-fire on one press.
    if (A_TickCount - LastSuspendToggle < 250)
        return
    LastSuspendToggle := A_TickCount
    if (GlobalSuspended) {
        ApplyAllMacros()
        GlobalSuspended := false
    } else {
        SuspendAllMacros()
    }
    if (GlobalSuspended)
        ToolTip, ALL MACROS SUSPENDED - press %GlobalSuspendKey% to resume
    else
        ToolTip, All macros resumed
    SetTimer, RemoveToolTip, -1500
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
    global GlobalSuspendKey

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

        IniRead, GlobalSuspendKey, %SettingsFile%, Global, SuspendKey, %A_Space%
    }
    PressureJumpKey       := Trim(PressureJumpKey)
    FreezeKey             := Trim(FreezeKey)
    RotationKey           := Trim(RotationKey)
    IncreaseSlotKey       := Trim(IncreaseSlotKey)
    DecreaseSlotKey       := Trim(DecreaseSlotKey)
    FastGunSwapKey        := Trim(FastGunSwapKey)
    FastGunSwapOnOffKey := Trim(FastGunSwapOnOffKey)
    ShuffleReloadKey      := Trim(ShuffleReloadKey)
    GlobalSuspendKey      := Trim(GlobalSuspendKey)
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
    global GlobalSuspendKey

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

    IniWrite, %GlobalSuspendKey%, %SettingsFile%, Global, SuspendKey
}

; ==========================================================================
;                              Tray icon
; ==========================================================================

BuildTray() {
    Menu, Tray, NoStandard
    try Menu, Tray, Icon, %A_ScriptDir%\PrisonLifeMacro.ico
    Menu, Tray, Add, Open Settings, TrayShowSettings
    Menu, Tray, Add, Suspend/Resume All Macros, ToggleGlobalSuspend
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
