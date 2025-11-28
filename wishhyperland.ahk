#Requires AutoHotkey v2
#SingleInstance Force
#Warn
SetTitleMatchMode "RegEx"
global capsTapStart := 0
global capsTapArmed := false
global capsUsedAsModifier := false

#Include "%A_ScriptDir%\VD.ah2"
; or: #Include <VD>

; Disable CapsLock toggle; use as modifier
; Hold = modifier, quick double-tap = toggle CapsLock
; Caps acts as modifier; double-tap toggles Caps

CapsLock::
{
    global capsTapStart, capsTapArmed, capsUsedAsModifier
    now := A_TickCount

    ; Second tap within window -> toggle explicitly
    if (capsTapArmed && (now - capsTapStart) <= 300) {
        state := GetKeyState("CapsLock", "T") ; true/false
        SetCapsLockState(state ? "Off" : "On")
        capsTapArmed := false
        capsTapStart := 0
        capsUsedAsModifier := false
        return
    }

    ; First tap arms the double-tap
    capsTapArmed := true
    capsTapStart := now
    capsUsedAsModifier := false
    return
}

CapsLock Up::
{
    global capsTapStart, capsTapArmed, capsUsedAsModifier
    ; If used with a combo (e.g., Caps+a), cancel any tap
    if (capsUsedAsModifier) {
        capsTapArmed := false
        capsTapStart := 0
        capsUsedAsModifier := false
        return
    }

    ; Optionally, timeout if no second tap comes soon (prevents stale arm)
    if (capsTapArmed && (A_TickCount - capsTapStart) > 350) {
        capsTapArmed := false
        capsTapStart := 0
    }
    return
}

EnsureDesktopCount(n) {
    count := VD.getCount()
    if (count < n)
        VD.createUntil(n)
}

GoToDesktopNumberEnsured(n) {
    if (n < 1)
        return
    EnsureDesktopCount(n)
    VD.goToDesktopNum(n, true)
}

MoveActiveToDesktopNumberEnsured(n) {
    EnsureDesktopCount(n)
    hwnd := WinGetID("A")
    if hwnd
        VD.MoveWindowToDesktopNum("ahk_id " hwnd, n)
}

DeskNumFromLetter(letter) {
    letter := StrLower(letter)
    code := Ord(letter)
    return (code >= Ord("a") && code <= Ord("z")) ? (code - Ord("a") + 1) : 0
}

MakeHandler(letter) {
    return (*) => HandleCapsLetter(letter)
}

; One handler that decides by Shift state
HandleCapsLetter(letter) {
    global capsUsedAsModifier
    capsUsedAsModifier := true
    n := DeskNumFromLetter(letter)
    if (!n)
        return
    if (GetKeyState("Shift", "P")) {
        ; Caps + Shift + letter: move active window (no switch)
        MoveActiveToDesktopNumberEnsured(n)
    } else {
        ; Caps + letter: switch to that desktop
        GoToDesktopNumberEnsured(n)
    }
}

; Register CapsLock + a..z once; Shift is checked inside the handler
for ltr in StrSplit("abcdefghijklmnopqrstuvwxyz") {
    Hotkey "CapsLock & " ltr, MakeHandler(ltr), "On"
}
; Optional: feedback
; VD.CurrentVirtualDesktopChanged := (old, new) => TrayTip("Virtual Desktop", "Now on desktop " new, 800)


; Return an array of visible, normal top-level window HWNDs (excluding tool windows/etc.)
GetToplevelWindows() {
    winList := []
    for hwnd in WinGetList() {
        try {
            if !WinExist("ahk_id " hwnd)
                continue
            if WinGetMinMax("ahk_id " hwnd) = -1
                continue
            exStyle := DllCall((A_PtrSize=8)?"GetWindowLongPtrW":"GetWindowLongW","Ptr",hwnd,"Int",-20,"Ptr")
            style   := DllCall((A_PtrSize=8)?"GetWindowLongPtrW":"GetWindowLongW","Ptr",hwnd,"Int",-16,"Ptr")
            if !(style & 0x10000000) ; WS_VISIBLE
                continue
            if (exStyle & 0x00000080) ; WS_EX_TOOLWINDOW
                continue
            if (exStyle & 0x08000000) ; WS_EX_NOACTIVATE
                continue
            ; Exclude cloaked (UWP minimized/hidden)
            cloaked := 0
            DllCall("dwmapi\DwmGetWindowAttribute","Ptr",hwnd,"Int",14,"Int*",&cloaked:=0,"Int",4)
            if cloaked
                continue
            winList.Push(hwnd)
        }
    }
    return winList
}

; Get window rect as {l,t,r,b,cx,cy,cx2,cy2} (center coords included)
GetRect(hwnd) {
    rect := Buffer(16, 0)
    if !DllCall("GetWindowRect", "Ptr", hwnd, "Ptr", rect.Ptr)
        return {l:0,t:0,r:0,b:0,cx:0,cy:0,cx2:0,cy2:0}
    l := NumGet(rect, 0, "Int")
    t := NumGet(rect, 4, "Int")
    r := NumGet(rect, 8, "Int")
    b := NumGet(rect, 12, "Int")
    return { l:l, t:t, r:r, b:b, cx:(l + r) // 2, cy:(t + b) // 2, cx2:(r - l), cy2:(b - t) }
}

; Find nearest window in a direction relative to active window center
; dir: "left"|"right"|"up"|"down"
FindNeighbor(dir) {
    active := WinGetID("A")
    if !active
        return 0
    ar := GetRect(active)
    ax := ar.cx, ay := ar.cy

    bestH := 0, bestScore := 1e15
    for hwnd in GetToplevelWindows() {
        if hwnd = active
            continue
        r := GetRect(hwnd)
        ; Direction gating
        if (dir = "left"  && !(r.cx < ax))      || (dir = "right" && !(r.cx > ax))
            continue
        if (dir = "up"    && !(r.cy < ay))      || (dir = "down"  && !(r.cy > ay))
            continue

        ; Prefer same row/column overlap a bit; compute distance with bias
        dx := r.cx - ax, dy := r.cy - ay
        ; Penalize perpendicular offset to favor aligned neighbors
        if (dir="left" || dir="right")
            score := Abs(dx) + Abs(dy) * 0.6
        else
            score := Abs(dy) + Abs(dx) * 0.6

        if (score < bestScore) {
            bestScore := score
            bestH := hwnd
        }
    }
    return bestH
}

; Alt+h/j/k/l to focus neighbor window by position (vim-style)
!h::{
    if (hwnd := FindNeighbor("left"))
        WinActivate "ahk_id " hwnd
}
!l::{
    if (hwnd := FindNeighbor("right"))
        WinActivate "ahk_id " hwnd
}
!k::{
    if (hwnd := FindNeighbor("up"))
        WinActivate "ahk_id " hwnd
}
!j::{
    if (hwnd := FindNeighbor("down"))
        WinActivate "ahk_id " hwnd
}