@echo off
rem ===========================================================================
rem  pub.cmd - ASCII-ONLY launcher for pub.ps1 (build the offline retail
rem  installer: Full Native AOT payload + Inno Setup package).
rem
rem  Do not add non-ASCII text to this file. cmd.exe locates batch lines by
rem  byte offset while decoding characters, so a UTF-8 batch file containing
rem  Chinese gets shredded and unrelated commands fail. All human-readable
rem  text lives in pub.ps1, which PowerShell reads correctly as UTF-8.
rem
rem  Manual : pub.cmd
rem           pub.cmd -SkipPublish          reuse the existing AOT payload
rem           pub.cmd -InstallInnoSetup    install Inno Setup 6 via winget
rem           pub.cmd -Platform ARM64
rem  Output : docs\lijinfu\installer\DeskBoxEx_Installer_<version>.exe
rem
rem  Double-click keeps the window open; scripted calls do not.
rem
rem  Exit codes: 0 ok   1 precondition failed   2 publish failed
rem              3 installer compile failed
rem ===========================================================================
setlocal EnableExtensions

set "PUB_PAUSE="
echo "%cmdcmdline%" | findstr /c:"/c \"\"" >nul 2>&1
if not errorlevel 1 set "PUB_PAUSE=1"

set "PUB_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PUB_PS%" set "PUB_PS=powershell.exe"

set "PUB_SCRIPT=%~dp0core\pub.ps1"
if not exist "%PUB_SCRIPT%" (
    echo [FAIL] pub.ps1 was not found at "%~dp0core\pub.ps1".
    if defined PUB_PAUSE pause
    exit /b 1
)

if defined PUB_PAUSE (
    "%PUB_PS%" -NoProfile -ExecutionPolicy Bypass -File "%PUB_SCRIPT%" -Pause %*
) else (
    "%PUB_PS%" -NoProfile -ExecutionPolicy Bypass -File "%PUB_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
