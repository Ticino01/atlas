

#NoEnv
#SingleInstance Force
SendMode Input
SetWorkingDir %A_ScriptDir%

; Tray-Icon setzen
Menu, Tray, Icon, %A_ScriptDir%\atlas.ico
Menu, Tray, Tip, Atlas - Universal Search

AtlasScript := "C:\school\M122 and M431 Projekt\atlas-ui.ps1"
IndexScript := "C:\school\M122 and M431 Projekt\index-all.ps1"

^!Space::
    Run, powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%AtlasScript%"
return

^!r::
    Run, powershell.exe -WindowStyle Hidden -ExecutionPolicy Bypass -File "%IndexScript%"
    TrayTip, Atlas, Re-Indexierung gestartet..., 3
return
