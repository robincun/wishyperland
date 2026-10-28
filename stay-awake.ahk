#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; ================== Settings ==================
IdleThreshold := 3 * 60 * 1000   ; only nudge the mouse after 3 min without real input
CheckInterval := 30 * 1000       ; how often to check (30 s)
; ==============================================

Active := true

; Hooks are needed so A_TimeIdlePhysical ignores the script's own mouse moves
InstallKeybdHook()
InstallMouseHook()

; Tray menu
A_IconTip := "Stay Awake: ON  (Ctrl+Alt+J to toggle)"
A_TrayMenu.Insert("1&", "Toggle Stay Awake", (*) => ToggleActive())
A_TrayMenu.Insert("2&")

KeepAwake(true)
SetTimer(Tick, CheckInterval)
OnExit((*) => KeepAwake(false))

TrayTip("Stay Awake is ON", "Ctrl+Alt+J to pause/resume", 1)

; Ctrl+Alt+J toggles on/off
^!j:: ToggleActive()

Tick() {
    if !Active
        return

    KeepAwake(true)   ; refresh the "don't sleep" request

    ; Only jiggle when you're actually away, so it never interferes with your work
    if (A_TimeIdlePhysical >= IdleThreshold) {
        MouseMove(1, 0, 0, "R")
        Sleep(50)
        MouseMove(-1, 0, 0, "R")
    }
}

ToggleActive() {
    global Active
    Active := !Active
    KeepAwake(Active)
    state := Active ? "ON" : "OFF"
    A_IconTip := "Stay Awake: " state "  (Ctrl+Alt+J to toggle)"
    TrayTip("Stay Awake is " state, " ", 1)
}

; Tells Windows not to sleep or turn off the display while the script runs
KeepAwake(on) {
    ES_CONTINUOUS       := 0x80000000
    ES_SYSTEM_REQUIRED  := 0x00000001
    ES_DISPLAY_REQUIRED := 0x00000002
    flags := on ? (ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED) : ES_CONTINUOUS
    DllCall("SetThreadExecutionState", "UInt", flags)
}
