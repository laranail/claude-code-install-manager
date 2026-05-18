@echo off
setlocal EnableDelayedExpansion EnableExtensions

REM ============================================================================
REM  claude-code-install-manager.cmd
REM
REM  Claude Code Install Manager — install, update, repair, and diagnose
REM  Claude Code on Windows. Works around upstream installer limitations:
REM  multi-location install drift, PATH not propagating, WinGet/native
REM  collisions, Desktop App alias hijack, and SYSTEM-profile leftovers
REM  from accidental elevated installs.
REM
REM  Subcommands:
REM    install    Install Claude Code and configure PATH
REM    update     Re-run installer to update to latest
REM    uninstall  Remove Claude Code and clean PATH
REM    repair     Fix PATH for an existing install (no reinstall)
REM    doctor     Diagnose install, PATH, version, and conflicts
REM    path       Show install location and PATH status
REM    version    Print installed version
REM    where      Show where 'claude' resolves from
REM    help       Show usage
REM
REM  Flags (must come AFTER the subcommand):
REM    --force         Proceed despite warnings; reinstall if already present
REM    --quiet         Minimal output
REM    --verbose       Extra debug output
REM    --download-only Download installer to disk and show SHA256; do not run
REM    --yes           Auto-confirm prompts
REM
REM  Run as your normal user, not Administrator. Claude Code is per-user.
REM ============================================================================

REM ============================================================================
REM  Wrapper: detect double-click invocation, dispatch the main flow, then
REM  pause if the user double-clicked the script so they can read the output
REM  before the console window closes. Set CCT_NO_PAUSE=1 to skip the pause.
REM ============================================================================
set "_CCT_INTERACTIVE=0"
if not defined CCT_NO_PAUSE (
    set "_CMDLN=!cmdcmdline!"
    if /i not "!_CMDLN!"=="!_CMDLN:%~nx0=!" set "_CCT_INTERACTIVE=1"
)

call :CCTRunMain %*
set "_CCT_EXIT=!errorlevel!"

if "!_CCT_INTERACTIVE!"=="1" (
    echo.
    if "!_CCT_EXIT!"=="0" (
        echo --- Done. Press any key to close this window. ---
    ) else (
        echo --- Script exited with code !_CCT_EXIT!. Press any key to close.
        echo     For diagnostics, run:  %~n0 doctor
    )
    pause >nul
)
exit /b !_CCT_EXIT!


REM ============================================================================
REM  MAIN
REM ============================================================================
:CCTRunMain

REM ---- Constants -------------------------------------------------------------
set "SCRIPT_NAME=claude-code-install-manager"
set "SCRIPT_DISPLAY=Claude Code Install Manager"
set "SCRIPT_VERSION=0.1.0"
set "INSTALLER_URL=https://claude.ai/install.ps1"

REM ---- Defaults --------------------------------------------------------------
set "FLAG_FORCE=0"
set "FLAG_QUIET=0"
set "FLAG_VERBOSE=0"
set "FLAG_DOWNLOAD_ONLY=0"
set "FLAG_YES=0"
set "EXIT_CODE=0"

REM Color stubs so :LogErr / :LogInfo work before :InitColors fills them in.
set "CLR_OFF="
set "CLR_BOLD="
set "CLR_DIM="
set "CLR_OK="
set "CLR_WARN="
set "CLR_ERR="
set "CLR_INFO="

REM ---- Parse subcommand ------------------------------------------------------
set "SUBCMD=%~1"
if "%SUBCMD%"=="" set "SUBCMD=install"
shift /1

REM ---- Parse flags -----------------------------------------------------------
:ParseFlags
if "%~1"=="" goto :FlagsDone
if /i "%~1"=="--force"         (set "FLAG_FORCE=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="/force"          (set "FLAG_FORCE=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="-f"              (set "FLAG_FORCE=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="--quiet"         (set "FLAG_QUIET=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="-q"              (set "FLAG_QUIET=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="--verbose"       (set "FLAG_VERBOSE=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="-v"              (set "FLAG_VERBOSE=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="--download-only" (set "FLAG_DOWNLOAD_ONLY=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="--yes"           (set "FLAG_YES=1" & shift /1 & goto :ParseFlags)
if /i "%~1"=="-y"              (set "FLAG_YES=1" & shift /1 & goto :ParseFlags)
call :LogErr "Unknown flag: %~1"
echo Run "%SCRIPT_NAME% help" for usage.
exit /b 2
:FlagsDone

REM ---- Verify PowerShell is available (required for everything else) --------
where powershell.exe >nul 2>&1
if errorlevel 1 (
    echo [X] powershell.exe not found on PATH. This wrapper requires PowerShell 5.1+. 1>&2
    exit /b 1
)

REM ---- Initialize ANSI colors (works on Windows 10+ cmd) ---------------------
call :InitColors

REM ---- Dispatch --------------------------------------------------------------
if /i "%SUBCMD%"=="install"   goto :CmdInstall
if /i "%SUBCMD%"=="update"    goto :CmdUpdate
if /i "%SUBCMD%"=="upgrade"   goto :CmdUpdate
if /i "%SUBCMD%"=="uninstall" goto :CmdUninstall
if /i "%SUBCMD%"=="remove"    goto :CmdUninstall
if /i "%SUBCMD%"=="repair"                  goto :CmdRepair
if /i "%SUBCMD%"=="fix"                     goto :CmdRepair
if /i "%SUBCMD%"=="repair-system"           goto :CmdRepairSystem
if /i "%SUBCMD%"=="--repair-system-profile" goto :CmdRepairSystem
if /i "%SUBCMD%"=="disable-desktop-alias"   goto :CmdDisableAlias
if /i "%SUBCMD%"=="fix-alias"               goto :CmdDisableAlias
if /i "%SUBCMD%"=="doctor"                  goto :CmdDoctor
if /i "%SUBCMD%"=="check"                   goto :CmdDoctor
if /i "%SUBCMD%"=="path"      goto :CmdPath
if /i "%SUBCMD%"=="version"   goto :CmdVersion
if /i "%SUBCMD%"=="--version" goto :CmdVersion
if /i "%SUBCMD%"=="-V"        goto :CmdVersion
if /i "%SUBCMD%"=="where"     goto :CmdWhere
if /i "%SUBCMD%"=="which"     goto :CmdWhere
if /i "%SUBCMD%"=="help"      goto :CmdHelp
if /i "%SUBCMD%"=="--help"    goto :CmdHelp
if /i "%SUBCMD%"=="-h"        goto :CmdHelp
if /i "%SUBCMD%"=="/?"        goto :CmdHelp

call :LogErr "Unknown subcommand: %SUBCMD%"
echo Run "%SCRIPT_NAME% help" for usage.
exit /b 2


REM ============================================================================
REM  SUBCOMMAND: install
REM ============================================================================
:CmdInstall
call :Header "Install Claude Code"
call :CheckAdmin || exit /b 1

REM Check for an existing install
call :FindClaude
if defined CLAUDE_EXE (
    call :LogInfo "Existing install detected at: !CLAUDE_EXE!"
    if "!FLAG_FORCE!"=="0" (
        call :LogInfo "Skipping installer. Running repair flow instead."
        call :LogInfo "Use --force to reinstall from scratch."
        goto :DoRepair
    )
    call :LogInfo "--force set; reinstalling."
)

call :RunInstaller || exit /b !errorlevel!
if "!FLAG_DOWNLOAD_ONLY!"=="1" exit /b 0

call :FindClaude
if not defined CLAUDE_EXE (
    call :LogErr "Installer ran but claude.exe was not found in any known location."
    call :LogErr "Try: %SCRIPT_NAME% doctor"
    exit /b 1
)
call :LogOk "Installed: !CLAUDE_EXE!"

goto :DoRepair


REM ============================================================================
REM  SUBCOMMAND: update
REM ============================================================================
:CmdUpdate
call :Header "Update Claude Code"
call :CheckAdmin || exit /b 1

call :FindClaude
if not defined CLAUDE_EXE (
    call :LogWarn "Claude Code is not currently installed."
    call :LogInfo "Running install instead."
    goto :CmdInstall
)

call :LogInfo "Current install: !CLAUDE_EXE!"
call :GetCurrentVersion
if defined CURRENT_VERSION call :LogInfo "Current version: !CURRENT_VERSION!"

call :RunInstaller || exit /b !errorlevel!
if "!FLAG_DOWNLOAD_ONLY!"=="1" exit /b 0

call :FindClaude
call :GetCurrentVersion
if defined CURRENT_VERSION call :LogOk "Updated version: !CURRENT_VERSION!"

goto :DoRepair


REM ============================================================================
REM  SUBCOMMAND: uninstall
REM ============================================================================
:CmdUninstall
call :Header "Uninstall Claude Code"

call :FindClaude
if not defined CLAUDE_EXE (
    call :LogWarn "Claude Code does not appear to be installed."
    call :LogInfo "Will still attempt to clean PATH in case of leftover entries."
)

if defined CLAUDE_EXE call :LogInfo "Found install at: !CLAUDE_EXE! (kind: !CLAUDE_INSTALL_KIND!)"

REM Refuse to delete a WinGet-managed install: doing so would leave WinGet's
REM package database pointing at a missing folder and the user without a clean
REM way to reinstall via winget. Direct them at the package manager instead.
if /i "!CLAUDE_INSTALL_KIND!"=="winget" (
    call :LogErr "This install is managed by WinGet."
    call :LogErr "Removing it by hand would corrupt WinGet's package state."
    call :LogErr "Uninstall via WinGet instead:"
    call :LogErr "    winget uninstall Anthropic.ClaudeCode"
    call :LogErr "Then re-run '%SCRIPT_NAME% uninstall' if you also want PATH cleaned."
    exit /b 1
)

if "!FLAG_YES!"=="0" (
    set /p CONFIRM="Proceed with uninstall? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        call :LogInfo "Aborted."
        exit /b 0
    )
)

REM Remove the install directory
if defined CLAUDE_EXE (
    call :GetClaudeDir "!CLAUDE_EXE!"
    call :Spin "Removing !CLAUDE_DIR!" "Remove-Item -LiteralPath '!CLAUDE_DIR!' -Recurse -Force -ErrorAction Stop"
    if exist "!CLAUDE_DIR!" (
        call :LogWarn "Some files could not be removed. They may be in use."
        call :LogWarn "Close any running 'claude' processes and re-run."
    )
)

REM Clean User PATH of all known claude locations
call :LogInfo "Cleaning User PATH..."
call :RemoveFromPath || exit /b 1
call :LogOk "User PATH cleaned."

REM Refresh current session
call :RefreshSessionPath
call :LogOk "Uninstall complete."
echo.
echo Note: Configuration files in %%USERPROFILE%%\.claude\ have been preserved.
echo Delete that directory manually if you want a full wipe.
exit /b 0


REM ============================================================================
REM  SUBCOMMAND: repair
REM ============================================================================
:CmdRepair
call :Header "Repair Claude Code PATH"
call :FindClaude
if not defined CLAUDE_EXE (
    call :LogErr "Claude Code is not installed. Nothing to repair."
    call :LogInfo "Run: %SCRIPT_NAME% install"
    exit /b 1
)
call :LogInfo "Install: !CLAUDE_EXE!"

:DoRepair
call :GetClaudeDir "!CLAUDE_EXE!"
call :LogInfo "Install directory: !CLAUDE_DIR!"
call :AddToPath "!CLAUDE_DIR!" || exit /b 1
call :RefreshSessionPath
call :VerifyInstall
goto :Summary


REM ============================================================================
REM  SUBCOMMAND: repair-system  (alias: --repair-system-profile)
REM
REM  Removes Claude Code leftovers under the SYSTEM account's profile, created
REM  by an accidental admin-elevated install. Re-launches itself elevated if
REM  needed (UAC prompt). Defense-in-depth: refuses to touch any path that
REM  does not start with %SystemRoot%\System32\config\systemprofile\.
REM ============================================================================
:CmdRepairSystem
call :Header "Repair SYSTEM-profile leftover"
set "SYS_PROFILE=%SystemRoot%\System32\config\systemprofile"
call :LogInfo "This removes Claude Code files left under the SYSTEM account"
call :LogInfo "after someone ran the installer as Administrator. Affected paths:"
call :LogInfo "  !SYS_PROFILE!\.local\bin\claude.exe"
call :LogInfo "  !SYS_PROFILE!\AppData\Local\Programs\claude\"
call :LogInfo "  !SYS_PROFILE!\AppData\Roaming\npm\claude.cmd"
echo.

REM Are we elevated?
net session >nul 2>&1
if not !errorlevel!==0 (
    call :LogWarn "Not running as Administrator."
    call :LogInfo "Cleaning the SYSTEM profile requires elevation."
    if "!FLAG_YES!"=="0" (
        set /p CONFIRM="Re-launch with UAC prompt? (y/N): "
        if /i not "!CONFIRM!"=="y" (
            call :LogInfo "Aborted."
            exit /b 0
        )
    )
    call :LogInfo "Requesting elevation..."
    REM Re-launch self elevated with --yes so the elevated window does not stall on prompts.
    powershell -NoProfile -ExecutionPolicy Bypass -Command ^
        "try { Start-Process -FilePath '%~f0' -ArgumentList 'repair-system','--yes' -Verb RunAs -ErrorAction Stop; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
    if errorlevel 1 (
        call :LogErr "Failed to launch elevated session ^(user declined UAC?^)."
        call :LogErr "Open an Administrator cmd window and run:"
        call :LogErr "    %~nx0 repair-system --yes"
        exit /b 1
    )
    call :LogInfo "An elevated window has been launched. Watch it for results."
    exit /b 0
)

call :LogOk "Running with Administrator privileges."
echo.

if "!FLAG_YES!"=="0" (
    set /p CONFIRM="Proceed with cleanup? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        call :LogInfo "Aborted."
        exit /b 0
    )
)

set "REPAIR_OK=0"
set "REPAIR_BAD=0"

call :_SystemProfileClean "!SYS_PROFILE!\.local\bin\claude.exe"
call :_SystemProfileClean "!SYS_PROFILE!\AppData\Local\Programs\claude"
call :_SystemProfileClean "!SYS_PROFILE!\AppData\Roaming\npm\claude.cmd"

echo.
if "!REPAIR_OK!"=="0" (
    if "!REPAIR_BAD!"=="0" (
        call :LogInfo "No SYSTEM-profile leftovers found. Nothing to clean."
        exit /b 0
    )
    call :LogErr "Failed to clean !REPAIR_BAD! item^(s^)."
    exit /b 1
)
call :LogOk "Cleaned !REPAIR_OK! item^(s^) under !SYS_PROFILE!."
if not "!REPAIR_BAD!"=="0" call :LogWarn "Could not clean !REPAIR_BAD! item^(s^)."
exit /b 0

REM Helper for :CmdRepairSystem. Validates that the path is under SYS_PROFILE
REM before deleting, then removes it (rmdir for dirs, del for files).
:_SystemProfileClean
set "_TARGET=%~1"
if not exist "!_TARGET!" goto :EOF
REM Hard safety check: refuse to touch anything outside the SYSTEM profile.
echo !_TARGET!| findstr /i /b /c:"!SYS_PROFILE!\" >nul
if errorlevel 1 (
    call :LogErr "REFUSING (outside SYSTEM profile): !_TARGET!"
    set /a REPAIR_BAD+=1
    goto :EOF
)
call :Spin "Removing !_TARGET!" "Remove-Item -LiteralPath '!_TARGET!' -Recurse -Force -ErrorAction Stop"
if exist "!_TARGET!" (
    call :LogErr "Failed (in use, or ACL blocked): !_TARGET!"
    set /a REPAIR_BAD+=1
) else (
    set /a REPAIR_OK+=1
)
goto :EOF


REM ============================================================================
REM  SUBCOMMAND: disable-desktop-alias  (alias: fix-alias)
REM
REM  Removes the Claude Desktop App's Windows App Execution Alias so it stops
REM  shadowing the Claude Code CLI on PATH. Tries Remove-Item first; falls
REM  back to takeown+icacls+del (which needs admin). Windows may regenerate
REM  the alias on the next Claude Desktop App update — the Settings toggle
REM  (Apps > Advanced app settings > App execution aliases) is the only
REM  sticky fix, and we print that path in both success and failure cases.
REM ============================================================================
:CmdDisableAlias
call :Header "Disable Claude Desktop App execution alias"
set "ALIAS_PATH=%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe"
call :LogInfo "Target: !ALIAS_PATH!"
call :LogInfo "Removing this alias prevents Claude Desktop App from intercepting"
call :LogInfo "'claude' on the command line. Windows may regenerate it on the"
call :LogInfo "next desktop-app update; for a sticky fix also disable it via:"
call :LogInfo "  Settings ^> Apps ^> Advanced app settings ^> App execution aliases"
echo.

if not exist "!ALIAS_PATH!" (
    call :LogInfo "Alias not present. Nothing to do."
    exit /b 0
)

if "!FLAG_YES!"=="0" (
    set /p CONFIRM="Proceed with removal? (y/N): "
    if /i not "!CONFIRM!"=="y" (
        call :LogInfo "Aborted."
        exit /b 0
    )
)

REM First attempt: PowerShell Remove-Item (works in many cases without admin).
call :LogInfo "Attempting Remove-Item..."
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { Remove-Item -LiteralPath ([Environment]::GetFolderPath('LocalApplicationData') + '\Microsoft\WindowsApps\Claude.exe') -Force -ErrorAction Stop; exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"

if not exist "!ALIAS_PATH!" (
    call :LogOk "Alias removed."
    call :LogInfo "Tip: also toggle Claude OFF under Settings ^> Apps ^> Advanced"
    call :LogInfo "app settings ^> App execution aliases, so the next desktop-app"
    call :LogInfo "update does not restore it."
    exit /b 0
)

REM Second attempt: takeown + icacls + del (needs admin).
call :LogWarn "Remove-Item could not delete the alias."
call :LogInfo "Falling back to takeown + icacls + del (requires Administrator)."

net session >nul 2>&1
if not !errorlevel!==0 (
    call :LogErr "Not elevated. Re-run as Administrator:"
    call :LogErr "    %~nx0 disable-desktop-alias --yes"
    call :LogErr "Or use the Settings UI:"
    call :LogErr "    Settings ^> Apps ^> Advanced app settings ^> App execution aliases"
    exit /b 1
)

takeown /f "!ALIAS_PATH!" >nul 2>&1
icacls "!ALIAS_PATH!" /grant "%USERNAME%":F >nul 2>&1
del /f /q "!ALIAS_PATH!" 2>nul

if exist "!ALIAS_PATH!" (
    call :LogErr "Could not remove the alias even with elevation."
    call :LogErr "This usually means the alias is a reparse point owned by AppX."
    call :LogErr "Use the Settings UI:"
    call :LogErr "    Settings ^> Apps ^> Advanced app settings ^> App execution aliases"
    exit /b 1
)
call :LogOk "Alias removed via elevated cleanup."
call :LogInfo "Reminder: toggle Claude OFF in App execution aliases (Settings) so"
call :LogInfo "the next desktop-app update does not restore it."
exit /b 0


REM ============================================================================
REM  SUBCOMMAND: doctor
REM ============================================================================
:CmdDoctor
call :Header "Claude Code Doctor"

REM 1. Environment
call :LogStep "Environment"
echo     OS:           %OS%
ver | findstr /i "version" >nul && for /f "tokens=*" %%V in ('ver') do echo     Windows:      %%V
echo     User:         %USERNAME%
echo     Profile:      %USERPROFILE%

REM 2. PowerShell availability
call :LogStep "PowerShell"
where powershell >nul 2>&1
if errorlevel 1 (
    call :LogErr "powershell.exe not found on PATH. Cannot continue."
    exit /b 1
)
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "$PSVersionTable.PSVersion.ToString()"`) do echo     Version:      %%P

REM 3. Admin status
call :LogStep "Privilege level"
net session >nul 2>&1
if !errorlevel!==0 (
    echo     [!] Running as Administrator ^(not recommended for per-user install^)
) else (
    echo     OK Running as standard user
)

REM 4. Locate claude.exe
call :LogStep "Install location"
call :FindClaude
if defined CLAUDE_EXE (
    echo     Found:        !CLAUDE_EXE!
    call :GetClaudeDir "!CLAUDE_EXE!"
    echo     Directory:    !CLAUDE_DIR!
) else (
    echo     [X] claude.exe not found in any known location
)

REM 5. Version
call :LogStep "Version"
if defined CLAUDE_EXE (
    "!CLAUDE_EXE!" --version 2>nul
    if errorlevel 1 echo     [X] Binary exists but failed to run
) else (
    echo     -
)

REM 6. PATH status
call :LogStep "PATH status"
if defined CLAUDE_DIR (
    call :PathContains "!CLAUDE_DIR!" User
    if "!PATH_CONTAINS!"=="1" (
        echo     User PATH:    contains install directory
    ) else (
        echo     User PATH:    DOES NOT contain install directory
    )
    call :PathContains "!CLAUDE_DIR!" Machine
    if "!PATH_CONTAINS!"=="1" echo     Machine PATH: contains install directory ^(unusual^)
)

REM 7. Resolution from current session
call :LogStep "Command resolution"
where claude 2>nul
if errorlevel 1 echo     [X] 'claude' does not resolve in this session

REM 8. Conflicting installs
call :LogStep "Conflicts"
set "CONFLICT_COUNT=0"
for %%C in (
    "%USERPROFILE%\.local\bin\claude.exe"
    "%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe"
    "%LOCALAPPDATA%\Programs\claude\claude.exe"
    "%LOCALAPPDATA%\Programs\claude\bin\claude.exe"
    "%APPDATA%\npm\claude.cmd"
) do (
    if exist %%~C (
        echo     Found: %%~C
        set /a CONFLICT_COUNT+=1
    )
)
if !CONFLICT_COUNT! GTR 1 (
    echo     [!] Multiple Claude Code installs detected. The one resolved by PATH wins.
    echo         Native installer and WinGet install to different locations and do not
    echo         deduplicate. See GitHub issue anthropics/claude-code#31980.
) else if !CONFLICT_COUNT!==1 (
    echo     OK Single Claude Code install detected
) else (
    echo     No Claude Code installs detected
)

REM 9. Claude Desktop App execution alias (NOT the CLI; hijacks the 'claude' command)
call :LogStep "Desktop App alias check"
set "DESKTOP_ALIAS=%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe"
if exist "!DESKTOP_ALIAS!" (
    echo     [!] Found: !DESKTOP_ALIAS!
    echo         This is the Claude Desktop App's execution alias, NOT Claude Code.
    echo         When PATH resolves 'claude', the alias may win and launch the desktop
    echo         app instead of the CLI. See GitHub issue anthropics/claude-code#25075.
    echo         Disable in: Settings ^> Apps ^> Advanced app settings ^> App execution aliases.
) else (
    echo     OK No Claude Desktop App alias present
)

REM 10. PowerShell execution policy
call :LogStep "PowerShell execution policy"
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "(Get-ExecutionPolicy -Scope CurrentUser).ToString() + '/' + (Get-ExecutionPolicy -Scope LocalMachine).ToString()" 2^>nul`) do echo     CurrentUser/LocalMachine: %%P
for /f "usebackq tokens=*" %%P in (`powershell -NoProfile -Command "(Get-ExecutionPolicy -Scope MachinePolicy).ToString() + '/' + (Get-ExecutionPolicy -Scope UserPolicy).ToString()" 2^>nul`) do (
    if /i not "%%P"=="Undefined/Undefined" (
        echo     [!] MachinePolicy/UserPolicy: %%P
        echo         A Group Policy is enforcing an execution policy. Set-ExecutionPolicy
        echo         cannot override it. If the installer fails with a policy error, your
        echo         IT team owns this setting.
    )
)

REM 11. Git Bash detection (Claude Code uses this for its shell tool on Windows)
call :LogStep "Git Bash"
if defined CLAUDE_CODE_GIT_BASH_PATH (
    echo     CLAUDE_CODE_GIT_BASH_PATH: !CLAUDE_CODE_GIT_BASH_PATH!
    if exist "!CLAUDE_CODE_GIT_BASH_PATH!" (
        echo     OK bash.exe exists at that path
    ) else (
        echo     [X] bash.exe NOT found at that path
    )
) else (
    where bash.exe >nul 2>&1
    if !errorlevel!==0 (
        for /f "usebackq delims=" %%B in (`where bash.exe 2^>nul`) do echo     bash.exe on PATH: %%B
        echo     CLAUDE_CODE_GIT_BASH_PATH is not set ^(Claude Code may auto-detect^)
    ) else (
        echo     [!] bash.exe not on PATH and CLAUDE_CODE_GIT_BASH_PATH not set.
        echo         Claude Code's Bash tool needs Git Bash on Windows. Install Git for
        echo         Windows, or set CLAUDE_CODE_GIT_BASH_PATH to your bash.exe.
    )
)

REM 12. Config directory
call :LogStep "Config"
if exist "%USERPROFILE%\.claude" (
    echo     Config dir:   %USERPROFILE%\.claude
) else (
    echo     Config dir:   not present
)

echo.
echo Doctor complete.
exit /b 0


REM ============================================================================
REM  SUBCOMMAND: path
REM ============================================================================
:CmdPath
call :FindClaude
if not defined CLAUDE_EXE (
    call :LogErr "Claude Code is not installed."
    call :LogInfo "Searched all known locations. Run '%SCRIPT_NAME% install' to set it up."
    exit /b 1
)
call :GetClaudeDir "!CLAUDE_EXE!"
echo Executable:  !CLAUDE_EXE!
echo Directory:   !CLAUDE_DIR!
echo Install kind: !CLAUDE_INSTALL_KIND!
echo.

REM PATH presence in both scopes
call :PathContains "!CLAUDE_DIR!" User
if "!PATH_CONTAINS!"=="1" (
    echo User PATH:    contains install directory
) else (
    echo User PATH:    DOES NOT contain install directory ^(run: %SCRIPT_NAME% repair^)
)
call :PathContains "!CLAUDE_DIR!" Machine
if "!PATH_CONTAINS!"=="1" echo Machine PATH: also contains install directory ^(unusual^)
echo.

REM Resolution from current session
echo PATH resolves 'claude' to:
where claude 2>nul
if errorlevel 1 echo   ^(not on PATH in this session^)
echo.

REM Desktop App alias check — flag if PATH would resolve to it instead of the CLI
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe" (
    echo [!] Claude Desktop App execution alias exists:
    echo     %LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe
    echo     Disable it via Settings ^> Apps ^> Advanced app settings ^>
    echo     App execution aliases if 'claude' launches the desktop app.
    echo.
)

REM List every install path we know about, marking the active one
echo All detected installs ^(active marked *^):
call :_ListIfExists "%USERPROFILE%\.local\bin\claude.exe"              native
call :_ListIfExists "%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe" winget
call :_ListIfExists "%LOCALAPPDATA%\Programs\claude\claude.exe"        legacy-native
call :_ListIfExists "%LOCALAPPDATA%\Programs\claude\bin\claude.exe"    legacy-native
call :_ListIfExists "%APPDATA%\npm\claude.cmd"                         npm
exit /b 0

:_ListIfExists
if not exist "%~1" goto :EOF
if /i "%~1"=="!CLAUDE_EXE!" (
    echo   * [%~2] %~1
) else (
    echo     [%~2] %~1
)
goto :EOF


REM ============================================================================
REM  SUBCOMMAND: version
REM ============================================================================
:CmdVersion
echo %SCRIPT_DISPLAY% %SCRIPT_VERSION%  ^(%SCRIPT_NAME%^)
call :FindClaude
if defined CLAUDE_EXE (
    "!CLAUDE_EXE!" --version 2>nul
) else (
    echo Claude Code: not installed
)
exit /b 0


REM ============================================================================
REM  SUBCOMMAND: where
REM ============================================================================
:CmdWhere
where claude 2>nul
if errorlevel 1 (
    call :FindClaude
    if defined CLAUDE_EXE (
        echo Not on PATH, but installed at: !CLAUDE_EXE!
        echo Run: %SCRIPT_NAME% repair
        exit /b 1
    )
    echo Claude Code is not installed.
    exit /b 1
)
exit /b 0


REM ============================================================================
REM  SUBCOMMAND: help
REM ============================================================================
:CmdHelp
echo %SCRIPT_DISPLAY% %SCRIPT_VERSION%  ^(%SCRIPT_NAME%^)
echo.
echo Install, update, repair, and diagnose Claude Code on Windows. Handles
echo install-location drift, PATH not propagating, WinGet/native collisions,
echo the Claude Desktop App alias hijack, and SYSTEM-profile leftovers.
echo.
echo Usage:
echo   %SCRIPT_NAME% ^<subcommand^> [flags]
echo.
echo Subcommands:
echo   install                 Install Claude Code and configure PATH ^(default^)
echo   update                  Update to the latest version
echo   uninstall               Remove Claude Code and clean PATH
echo   repair                  Fix PATH for an existing install
echo   doctor                  Diagnose install, PATH, and conflicts
echo   path                    Show install location and PATH state
echo   version                 Show wrapper and Claude Code versions
echo   where                   Show where 'claude' resolves from
echo   help                    Show this message
echo.
echo Repair / cleanup:
echo   repair-system           Clean Claude leftovers under the SYSTEM profile
echo                           ^(requires admin; re-prompts via UAC^)
echo   disable-desktop-alias   Remove the Claude Desktop App execution alias
echo                           that shadows the CLI on PATH
echo.
echo Flags:
echo   --force, -f             Proceed despite warnings; reinstall if present
echo   --yes, -y               Auto-confirm prompts
echo   --quiet, -q             Minimal output
echo   --verbose, -v           Extra debug output
echo   --download-only         Download installer and show SHA256; do not run
echo.
echo Environment:
echo   CCT_NO_PAUSE            If set, skip "Press any key" pause on exit
echo   CCT_NO_SPIN             If set, suppress spinner on long operations
echo.
echo Examples:
echo   %SCRIPT_NAME% install
echo   %SCRIPT_NAME% install --force
echo   %SCRIPT_NAME% update
echo   %SCRIPT_NAME% doctor
echo   %SCRIPT_NAME% uninstall --yes
echo   %SCRIPT_NAME% repair-system            ^(prompts for UAC if not elevated^)
echo   %SCRIPT_NAME% disable-desktop-alias    ^(removes the Claude.exe alias^)
echo.
echo Run as your normal user. Claude Code is a per-user installation. The
echo only subcommands that need Administrator privileges are repair-system,
echo and the fallback path of disable-desktop-alias when the user-mode delete
echo fails. The wrapper warns and aborts if you launch other subcommands as
echo admin ^(Claude Code installed elevated lands under the SYSTEM profile^).
exit /b 0


REM ============================================================================
REM  HELPERS
REM ============================================================================

REM ----------------------------------------------------------------------------
REM  :FindClaude
REM  Searches known Claude Code install locations for claude.exe / claude.cmd.
REM  Sets CLAUDE_EXE to the first match. Order matters: the current native
REM  installer is checked first, then WinGet's shim, then older native paths,
REM  then npm.
REM
REM  Note: %LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe is deliberately
REM  EXCLUDED — that is the Claude Desktop App's execution alias, NOT the
REM  Claude Code CLI. See :CmdDoctor for the alias-hijack check.
REM ----------------------------------------------------------------------------
:FindClaude
set "CLAUDE_EXE="
set "CLAUDE_INSTALL_KIND="
call :_FindCandidate "%USERPROFILE%\.local\bin\claude.exe"               native        && goto :EOF
call :_FindCandidate "%LOCALAPPDATA%\Microsoft\WinGet\Links\claude.exe"  winget        && goto :EOF
call :_FindCandidate "%LOCALAPPDATA%\Programs\claude\claude.exe"         legacy-native && goto :EOF
call :_FindCandidate "%LOCALAPPDATA%\Programs\claude\bin\claude.exe"     legacy-native && goto :EOF
call :_FindCandidate "%APPDATA%\npm\claude.cmd"                          npm           && goto :EOF
REM Last resort: check what's currently on PATH (but skip the Desktop App alias).
for /f "usebackq delims=" %%F in (`where claude 2^>nul`) do (
    if not defined CLAUDE_EXE (
        echo %%F | findstr /i /c:"\WindowsApps\Claude.exe" >nul
        if errorlevel 1 (
            set "CLAUDE_EXE=%%F"
            set "CLAUDE_INSTALL_KIND=path-resolved"
        )
    )
)
goto :EOF

:_FindCandidate
if not exist "%~1" exit /b 1
set "CLAUDE_EXE=%~1"
set "CLAUDE_INSTALL_KIND=%~2"
exit /b 0

REM ----------------------------------------------------------------------------
REM  :GetClaudeDir <path-to-exe>
REM  Sets CLAUDE_DIR to the directory portion, without trailing backslash.
REM ----------------------------------------------------------------------------
:GetClaudeDir
set "CLAUDE_DIR=%~dp1"
if "!CLAUDE_DIR:~-1!"=="\" set "CLAUDE_DIR=!CLAUDE_DIR:~0,-1!"
goto :EOF

REM ----------------------------------------------------------------------------
REM  :GetCurrentVersion
REM  Sets CURRENT_VERSION by running claude.exe --version.
REM ----------------------------------------------------------------------------
:GetCurrentVersion
set "CURRENT_VERSION="
if not defined CLAUDE_EXE goto :EOF
for /f "usebackq tokens=*" %%V in (`"!CLAUDE_EXE!" --version 2^>nul`) do set "CURRENT_VERSION=%%V"
goto :EOF

REM ----------------------------------------------------------------------------
REM  :PathContains <dir> <scope>
REM  Sets PATH_CONTAINS=1 if scope ("User" or "Machine") PATH contains <dir>.
REM  Comparison is case-insensitive and ignores trailing backslashes.
REM  Path is passed via env var to avoid quoting issues in PowerShell.
REM ----------------------------------------------------------------------------
:PathContains
set "PATH_CONTAINS=0"
set "CCT_DIR=%~1"
set "CCT_SCOPE=%~2"
for /f "usebackq tokens=*" %%R in (`powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$d=$env:CCT_DIR.TrimEnd('\').ToLower();$p=[Environment]::GetEnvironmentVariable('Path',$env:CCT_SCOPE);if(-not $p){'0';exit};$found=($p -split ';' ^| ? {$_} ^| %% {$_.TrimEnd('\').ToLower()}) -contains $d;if($found){'1'}else{'0'}"`) do set "PATH_CONTAINS=%%R"
set "CCT_DIR="
set "CCT_SCOPE="
goto :EOF

REM ----------------------------------------------------------------------------
REM  :AddToPath <dir>
REM  Adds <dir> to the User PATH if not already present.
REM  Preserves the original registry value type (REG_EXPAND_SZ vs REG_SZ).
REM  Idempotent.
REM ----------------------------------------------------------------------------
:AddToPath
set "CCT_DIR=%~1"
call :LogInfo "Updating User PATH..."

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$d = $env:CCT_DIR.TrimEnd('\');" ^
    "$key = 'HKCU:\Environment';" ^
    "$item = Get-ItemProperty -Path $key -Name Path -ErrorAction SilentlyContinue;" ^
    "$current = if ($item) { $item.Path } else { '' };" ^
    "$entries = $current -split ';' ^| Where-Object { $_ } ^| ForEach-Object { $_.TrimEnd('\') };" ^
    "if (($entries ^| ForEach-Object { $_.ToLower() }) -contains $d.ToLower()) {" ^
    "    Write-Host '    Already present.';" ^
    "    exit 0;" ^
    "}" ^
    "$new = if ($current) { \"$current;$d\" } else { $d };" ^
    "$kind = 'ExpandString'; try { $kind = (Get-Item $key).GetValueKind('Path') } catch { };" ^
    "Set-ItemProperty -Path $key -Name Path -Value $new -Type $kind;" ^
    "Write-Host '    Added.';" ^
    "$sig = '[DllImport(\"user32.dll\", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);';" ^
    "$type = Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace CCT -PassThru;" ^
    "[UIntPtr]$result = [UIntPtr]::Zero;" ^
    "[void]$type::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result);" ^
    "exit 0"

set "CCT_ERR=!errorlevel!"
set "CCT_DIR="
if not "!CCT_ERR!"=="0" (
    call :LogErr "Failed to update User PATH ^(exit !CCT_ERR!^)."
    call :LogErr "Group policy may block HKCU writes, or PowerShell may be restricted."
    call :LogErr "For diagnostics, run: %SCRIPT_NAME% doctor"
    exit /b 1
)
goto :EOF

REM ----------------------------------------------------------------------------
REM  :RemoveFromPath
REM  Removes any known claude install directories from User PATH.
REM ----------------------------------------------------------------------------
:RemoveFromPath
set "CCT_TARGETS=%USERPROFILE%\.local\bin;%LOCALAPPDATA%\Programs\claude;%LOCALAPPDATA%\Programs\claude\bin"

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$targets = $env:CCT_TARGETS -split ';' ^| ForEach-Object { $_.TrimEnd('\').ToLower() };" ^
    "$key = 'HKCU:\Environment';" ^
    "$item = Get-ItemProperty -Path $key -Name Path -ErrorAction SilentlyContinue;" ^
    "if (-not $item) { Write-Host '    User PATH is empty.'; exit 0 };" ^
    "$current = $item.Path;" ^
    "$kept = $current -split ';' ^| Where-Object { $_ } ^| Where-Object { ($targets -notcontains $_.TrimEnd('\').ToLower()) };" ^
    "$new = $kept -join ';';" ^
    "if ($new -eq $current) { Write-Host '    No matching entries.'; exit 0 };" ^
    "$kind = 'ExpandString'; try { $kind = (Get-Item $key).GetValueKind('Path') } catch { };" ^
    "if ($new) { Set-ItemProperty -Path $key -Name Path -Value $new -Type $kind } else { Remove-ItemProperty -Path $key -Name Path };" ^
    "Write-Host '    Cleaned.';" ^
    "$sig = '[DllImport(\"user32.dll\", SetLastError=true)] public static extern IntPtr SendMessageTimeout(IntPtr hWnd, uint Msg, UIntPtr wParam, string lParam, uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);';" ^
    "$type = Add-Type -MemberDefinition $sig -Name NativeMethods -Namespace CCT2 -PassThru;" ^
    "[UIntPtr]$result = [UIntPtr]::Zero;" ^
    "[void]$type::SendMessageTimeout([IntPtr]0xffff, 0x1a, [UIntPtr]::Zero, 'Environment', 2, 5000, [ref]$result);" ^
    "exit 0"

set "CCT_ERR=!errorlevel!"
set "CCT_TARGETS="
if not "!CCT_ERR!"=="0" (
    call :LogErr "Failed to clean User PATH ^(exit !CCT_ERR!^)."
    call :LogErr "You may have to remove old PATH entries manually:"
    call :LogErr "  System Properties ^> Environment Variables ^> User ^> Path"
    exit /b 1
)
goto :EOF

REM ----------------------------------------------------------------------------
REM  :RefreshSessionPath
REM  Rebuilds the current cmd session PATH from registry values.
REM  Note: capped by cmd's variable length limit (~8191 chars).
REM ----------------------------------------------------------------------------
:RefreshSessionPath
call :LogInfo "Refreshing session PATH..."
set "NEW_PATH="
for /f "usebackq delims=" %%P in (`powershell -NoProfile -Command ^
    "$m=[Environment]::GetEnvironmentVariable('Path','Machine');$u=[Environment]::GetEnvironmentVariable('Path','User');if($m -and $u){\"$m;$u\"} elseif($m){$m} else{$u}"`) do set "NEW_PATH=%%P"

if not defined NEW_PATH (
    call :LogWarn "Could not read combined PATH from registry."
    goto :EOF
)
set "PATH=!NEW_PATH!"
set "NEW_PATH="
call :LogOk "Session PATH refreshed."
goto :EOF

REM ----------------------------------------------------------------------------
REM  :CheckAdmin
REM  Warns if running elevated. Exits 1 if user declines to continue.
REM ----------------------------------------------------------------------------
:CheckAdmin
net session >nul 2>&1
if not !errorlevel!==0 goto :EOF
call :LogWarn "Running as Administrator."
call :LogWarn "Claude Code is a per-user tool. Admin installs may land in"
call :LogWarn "C:\Windows\System32\config\systemprofile or similar."
if "!FLAG_YES!"=="1" goto :EOF
if "!FLAG_FORCE!"=="1" goto :EOF
set /p CONFIRM="Continue anyway? (y/N): "
if /i not "!CONFIRM!"=="y" (
    call :LogInfo "Aborted. Re-run as your normal user."
    exit /b 1
)
goto :EOF

REM ----------------------------------------------------------------------------
REM  :RunInstaller
REM  Downloads and runs the official installer.
REM  With --download-only, saves to %TEMP% and prints SHA256 instead.
REM ----------------------------------------------------------------------------
:RunInstaller
REM Always download to a temp file first, then act on it. This separation lets
REM us show a real-time spinner during the network fetch (the only phase whose
REM duration is dominated by something other than the installer's own output)
REM without burying the installer's own status messages under a spinner.
set "INSTALLER_PATH=%TEMP%\claude-installer-%RANDOM%-%RANDOM%.ps1"
set "_CCT_URL=%INSTALLER_URL%"
set "_CCT_OUT=!INSTALLER_PATH!"

call :Spin "Downloading installer from %INSTALLER_URL%" ^
    "Invoke-WebRequest -Uri $env:_CCT_URL -OutFile $env:_CCT_OUT -UseBasicParsing -ErrorAction Stop"
set "_CCT_ERR=!errorlevel!"
set "_CCT_URL="
set "_CCT_OUT="
if not "!_CCT_ERR!"=="0" (
    call :LogErr "Download failed."
    call :LogErr "  - Check network / proxy ^(set HTTPS_PROXY if behind a corporate proxy^)"
    call :LogErr "  - TLS inspection on the proxy may block claude.ai"
    call :LogErr "  - Retry with: %SCRIPT_NAME% install --download-only"
    set "INSTALLER_PATH="
    exit /b 1
)

REM Hash the downloaded file so the user can compare against a known-good value.
for /f "usebackq tokens=*" %%H in (`powershell -NoProfile -Command "(Get-FileHash -LiteralPath $env:INSTALLER_PATH -Algorithm SHA256).Hash" 2^>nul`) do set "INSTALLER_SHA=%%H"
if defined INSTALLER_SHA call :LogInfo "Installer SHA256: !INSTALLER_SHA!"

if "!FLAG_DOWNLOAD_ONLY!"=="1" (
    call :LogOk "Saved to: !INSTALLER_PATH!"
    call :LogInfo "Inspect the script, then run it manually with:"
    echo         powershell -ExecutionPolicy Bypass -File "!INSTALLER_PATH!"
    REM Deliberately do NOT delete INSTALLER_PATH — the user is about to read it.
    set "INSTALLER_PATH="
    set "INSTALLER_SHA="
    goto :EOF
)

REM Run the downloaded installer. Do NOT wrap this in :Spin — the installer
REM writes its own progress to stdout and we want the user to see that live.
call :LogInfo "Running installer..."
set "_CCT_RUN_START=!TIME!"
powershell -NoProfile -ExecutionPolicy Bypass -File "!INSTALLER_PATH!"
set "_CCT_RUN_ERR=!errorlevel!"

REM Best-effort cleanup of the temp script.
del /f /q "!INSTALLER_PATH!" 2>nul
set "INSTALLER_PATH="
set "INSTALLER_SHA="

if not "!_CCT_RUN_ERR!"=="0" (
    call :LogErr "Installer failed (exit !_CCT_RUN_ERR!). Possible causes:"
    call :LogErr "  - PowerShell execution policy locked by group policy"
    call :LogErr "  - Insufficient permissions for per-user install"
    call :LogErr "  - Antivirus blocked the installer or its writes"
    call :LogErr "Try: %SCRIPT_NAME% install --download-only"
    exit /b 1
)
call :LogOk "Installer finished."
goto :EOF

REM ----------------------------------------------------------------------------
REM  :VerifyInstall
REM  Confirms claude.exe runs and resolves from PATH.
REM ----------------------------------------------------------------------------
:VerifyInstall
call :LogInfo "Verifying..."
if not defined CLAUDE_EXE (
    call :LogErr "No claude.exe to verify."
    exit /b 1
)
"!CLAUDE_EXE!" --version >nul 2>&1
if errorlevel 1 (
    call :LogErr "claude.exe is present at !CLAUDE_EXE! but failed to run."
    call :LogErr "The binary may be corrupted or blocked by antivirus."
    call :LogErr "Try: %SCRIPT_NAME% install --force"
    exit /b 1
)
call :LogOk "Binary runs."
where claude >nul 2>&1
if !errorlevel!==0 (
    call :LogOk "'claude' resolves from PATH."
    REM Confirm PATH resolves to the install we just verified — not the Desktop App alias.
    for /f "usebackq delims=" %%R in (`where claude 2^>nul`) do (
        echo %%R | findstr /i /c:"\WindowsApps\Claude.exe" >nul
        if not errorlevel 1 (
            call :LogWarn "'claude' on PATH resolves to the Claude Desktop App alias:"
            call :LogWarn "  %%R"
            call :LogWarn "This is NOT Claude Code. Running 'claude' may launch the desktop app."
            call :LogWarn "Disable the alias: Settings ^> Apps ^> Advanced app settings ^>"
            call :LogWarn "  App execution aliases. Then open a new terminal."
        )
    )
) else (
    call :LogWarn "'claude' not on PATH in this session."
    call :LogWarn "Open a new terminal and it should work."
)
if exist "%LOCALAPPDATA%\Microsoft\WindowsApps\Claude.exe" (
    call :LogWarn "Heads up: Claude Desktop App alias is present and may shadow the CLI"
    call :LogWarn "on PATH (anthropics/claude-code#25075). Run '%SCRIPT_NAME% doctor' if 'claude'"
    call :LogWarn "launches the wrong thing."
)
goto :EOF

REM ----------------------------------------------------------------------------
REM  :Summary
REM  Final status block.
REM ----------------------------------------------------------------------------
:Summary
echo.
echo %CLR_OK%Done.%CLR_OFF%
echo.
if defined CLAUDE_DIR echo Install: !CLAUDE_DIR!
echo.
echo Next steps:
echo   - Already-open terminals ^(VS Code, Windows Terminal tabs^) cache PATH
echo     at launch. Close and reopen them.
echo   - Try: claude --help
echo   - For diagnostics: %SCRIPT_NAME% doctor
echo.
exit /b 0


REM ============================================================================
REM  PROGRESS / SPINNER
REM ============================================================================

REM ----------------------------------------------------------------------------
REM  :Spin "<label>" "<powershell expression>"
REM
REM  Runs the given PowerShell expression in a child runspace inside the same
REM  PS host process. While it runs, an overwriting spinner (1 frame every
REM  ~120 ms) prints the label and elapsed time mm:ss using a carriage return
REM  to keep everything on one line. When the inner expression finishes, the
REM  spinner line is replaced by a final OK/FAIL status with the total time.
REM
REM  Behaviors:
REM    * Output (stdout) of the inner expression is buffered, then printed
REM      AFTER the spinner clears. This avoids the spinner line being torn
REM      apart by interleaved Write-Host output.
REM    * Exceptions are caught; the helper still returns control with
REM      errorlevel set to 1 on any failure.
REM    * If FLAG_QUIET=1 or CCT_NO_SPIN is defined, the spinner is skipped
REM      entirely and the expression runs in a normal one-shot PS invocation.
REM    * The PS expression is passed via the _SPIN_CMD environment variable
REM      to avoid having to escape quotes through cmd's parser.
REM
REM  Returns: 0 on success, 1 on inner-expression failure.
REM ----------------------------------------------------------------------------
:Spin
set "_SPIN_LBL=%~1"
set "_SPIN_CMD=%~2"
if "!FLAG_QUIET!"=="1" goto :_SpinPlain
if defined CCT_NO_SPIN goto :_SpinPlain

powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "$cr=[char]13;" ^
    "$rs=[runspacefactory]::CreateRunspace();$rs.Open();" ^
    "$p=[powershell]::Create();$p.Runspace=$rs;" ^
    "[void]$p.AddScript($env:_SPIN_CMD);" ^
    "$h=$p.BeginInvoke();" ^
    "$t0=Get-Date;$f='|/-\'.ToCharArray();$i=0;" ^
    "while(-not $h.IsCompleted){" ^
        "$e=(Get-Date)-$t0;" ^
        "$line=('  [{0}] {1}  {2:mm\:ss}' -f $f[$i %% 4],$env:_SPIN_LBL,$e);" ^
        "Write-Host -NoNewline ($line+$cr);" ^
        "Start-Sleep -Milliseconds 120;$i++;" ^
    "}" ^
    "$errored=$false;$out=$null;" ^
    "try{$out=$p.EndInvoke($h)}catch{$errored=$true;$errmsg=$_.Exception.Message};" ^
    "$te=(Get-Date)-$t0;" ^
    "$bad=$p.HadErrors -or $errored;" ^
    "$status=if($bad){'FAIL'}else{'OK  '};" ^
    "$color=if($bad){'Red'}else{'Green'};" ^
    "$final=('  [{0}] {1}  ({2:mm\:ss})                                       ' -f $status,$env:_SPIN_LBL,$te);" ^
    "Write-Host -ForegroundColor $color $final;" ^
    "$rs.Close();$p.Dispose();" ^
    "if($errored){Write-Host -ForegroundColor Red ('    ' + $errmsg)};" ^
    "if($out){foreach($x in $out){Write-Host $x}};" ^
    "if($bad){exit 1};" ^
    "exit 0"
set "_SPIN_ERR=!errorlevel!"
set "_SPIN_LBL="
set "_SPIN_CMD="
exit /b !_SPIN_ERR!

:_SpinPlain
powershell -NoProfile -ExecutionPolicy Bypass -Command ^
    "try { & ([scriptblock]::Create($env:_SPIN_CMD)); exit 0 } catch { Write-Host $_.Exception.Message; exit 1 }"
set "_SPIN_ERR=!errorlevel!"
set "_SPIN_LBL="
set "_SPIN_CMD="
exit /b !_SPIN_ERR!


REM ============================================================================
REM  LOGGING + UI
REM ============================================================================

REM ----------------------------------------------------------------------------
REM  :InitColors
REM  Enables ANSI escape sequences and defines color constants.
REM  On terminals without ANSI support, the escape sequences are inert.
REM ----------------------------------------------------------------------------
:InitColors
REM Respect NO_COLOR (https://no-color.org) and TERM=dumb conventions.
if defined NO_COLOR goto :NoColors
if /i "%TERM%"=="dumb" goto :NoColors
REM Extract ESC (0x1B) via PowerShell. More reliable than the prompt-pipe trick.
for /f "usebackq delims=" %%E in (`powershell -NoProfile -Command "[char]27"`) do set "ESC=%%E"
if not defined ESC goto :NoColors
set "CLR_OFF=%ESC%[0m"
set "CLR_BOLD=%ESC%[1m"
set "CLR_DIM=%ESC%[2m"
set "CLR_OK=%ESC%[32m"
set "CLR_WARN=%ESC%[33m"
set "CLR_ERR=%ESC%[31m"
set "CLR_INFO=%ESC%[36m"
goto :EOF

:NoColors
set "CLR_OFF="
set "CLR_BOLD="
set "CLR_DIM="
set "CLR_OK="
set "CLR_WARN="
set "CLR_ERR="
set "CLR_INFO="
goto :EOF

:Header
if "!FLAG_QUIET!"=="1" goto :EOF
echo.
echo %CLR_BOLD%==^> %~1%CLR_OFF%
echo.
goto :EOF

:LogStep
echo.
echo %CLR_BOLD%-- %~1%CLR_OFF%
goto :EOF

:LogInfo
if "!FLAG_QUIET!"=="1" goto :EOF
echo %CLR_INFO%    %~1%CLR_OFF%
goto :EOF

:LogOk
if "!FLAG_QUIET!"=="1" goto :EOF
echo %CLR_OK%    OK %~1%CLR_OFF%
goto :EOF

:LogWarn
echo %CLR_WARN%    [!] %~1%CLR_OFF%
goto :EOF

:LogErr
echo %CLR_ERR%    [X] %~1%CLR_OFF% 1>&2
goto :EOF
