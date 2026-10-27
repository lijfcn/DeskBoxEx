@echo off
rem ===========================================================================
rem  pull.cmd - ASCII-ONLY launcher for pull.ps1 (merge upstream author code).
rem
rem  Do not add non-ASCII text to this file. cmd.exe locates batch lines by
rem  byte offset while decoding characters, so a UTF-8 batch file containing
rem  Chinese gets shredded: lines lose their leading characters and unrelated
rem  commands fail with "'l.cmd' is not recognized". All human-readable text
rem  lives in pull.ps1, which PowerShell reads correctly as UTF-8.
rem
rem  Manual : pull.cmd --dry-run
rem  SKILL  : cmd /c ".github\skills\deskbox-ex-skill\scripts\pull.cmd --dry-run"
rem  Layout : pull.cmd (ASCII launcher)  ->  core\pull.ps1 (real logic, UTF-8 BOM)
rem  Double-click keeps the window open; scripted calls do not.
rem
rem  Exit codes: 0 ok / up-to-date   1 precondition failed
rem              2 merge conflict    3 merge failed (non-conflict)
rem ===========================================================================
setlocal EnableExtensions

set "PULL_PAUSE="
echo "%cmdcmdline%" | findstr /c:"/c \"\"" >nul 2>&1
if not errorlevel 1 set "PULL_PAUSE=1"

set "PULL_PS=%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe"
if not exist "%PULL_PS%" set "PULL_PS=powershell.exe"

set "PULL_SCRIPT=%~dp0core\pull.ps1"
if not exist "%PULL_SCRIPT%" (
    echo [FAIL] pull.ps1 was not found at "%~dp0core\pull.ps1".
    if defined PULL_PAUSE pause
    exit /b 1
)

if defined PULL_PAUSE (
    "%PULL_PS%" -NoProfile -ExecutionPolicy Bypass -File "%PULL_SCRIPT%" --pause %*
) else (
    "%PULL_PS%" -NoProfile -ExecutionPolicy Bypass -File "%PULL_SCRIPT%" %*
)
exit /b %ERRORLEVEL%
