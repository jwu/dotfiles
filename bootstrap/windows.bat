@echo off
setlocal enabledelayedexpansion
:: ========================================
:: dotfiles bootstrap (Windows), the third entry point next to
:: bootstrap/arch.sh and bootstrap/macos.sh.
::
:: Replaces the retired jwu/configs flow: clone the config repo, run
:: win/install.bat for the portable tools, then win/config.bat to generate the
:: pointer files. config.bat is gone -- chezmoi deploys the real content now --
:: and win/init.bat no longer points Clink at the repo.
::
:: Everything needing administrator rights lives here: win/install.bat installs
:: the Nerd Font through win/cmds/addfonts.cmd, which writes %SystemRoot%\Fonts
:: and HKLM. Run this from an elevated terminal; from then on `chezmoi apply`
:: needs neither elevation nor a terminal. See docs/chezmoi-notes.md and
:: docs/design.md, the bootstrap section.
::
:: Usage (curl.exe ships with Windows 10+; run the second line elevated):
::   curl -fsSL https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/windows.bat -o "%TEMP%\dotfiles-bootstrap.bat"
::   "%TEMP%\dotfiles-bootstrap.bat"
:: ========================================

if not defined REPO_SSH set "REPO_SSH=git@github.com:jwu/dotfiles.git"
if not defined REPO_HTTPS set "REPO_HTTPS=https://github.com/jwu/dotfiles.git"
if not defined SRC_DIR set "SRC_DIR=%USERPROFILE%\bin\dotfiles"
set "CONFIG_DIR=%USERPROFILE%\.config\chezmoi"
set "WIN_DIR=%SRC_DIR%\win"
set "ERROR_COUNT=0"

echo ^>^>^> dotfiles bootstrap ^(Windows^)
echo     repo:      %REPO_SSH%
echo     sourceDir: %SRC_DIR%

call :REQUIRE "administrator terminal" :CHECK_ADMIN || goto :ABORT
call :REQUIRE "git and curl" :CHECK_TOOLS || goto :ABORT
call :REQUIRE "install chezmoi" :INSTALL_CHEZMOI || goto :ABORT
call :REQUIRE "clone/update dotfiles" :ENSURE_REPO || goto :ABORT
call :REQUIRE "configure chezmoi sourceDir" :WRITE_CONFIG || goto :ABORT

call :DO "portable tools and Nerd Font (win\install.bat)" :INSTALL_TOOLS

call :REQUIRE "chezmoi init --apply" :CHEZMOI_APPLY || goto :ABORT

call :SUMMARY
echo.
echo ^>^>^> Restart your terminal for the Clink and Starship setup to take effect.
echo     From now on 'chezmoi apply' needs neither elevation nor a terminal.
exit /b %ERROR_COUNT%

:ABORT
echo.
echo ^>^>^> Stopped: a required step failed. Fix it and re-run; every step is idempotent.
exit /b 1

:: ========================================
:: Step runner
:: ========================================

:REQUIRE
:: %1 = display name, %2 = label. Hard dependency: stop the run on failure.
echo.
echo ^>^>^> %~1
call %2
if errorlevel 1 (
  echo     FAILED; cannot continue 1>&2
  exit /b 1
)
echo     ok
exit /b 0

:DO
:: %1 = display name, %2 = label. Best-effort: record the failure and continue.
echo.
echo ^>^>^> %~1
call %2
if errorlevel 1 (
  set /a "ERROR_COUNT+=1"
  echo     FAILED; continuing 1>&2
) else (
  echo     ok
)
exit /b 0

:SUMMARY
echo.
echo ==========================================
if "%ERROR_COUNT%"=="0" (
  echo ^>^>^> All steps completed.
  exit /b 0
)
echo ^>^>^> Finished with %ERROR_COUNT% failed step^(s^). Fix them and re-run.
exit /b 1

:: ========================================
:: Steps
:: ========================================

:CHECK_ADMIN
>nul 2>&1 fltmc
if errorlevel 1 (
  echo     Run this from an elevated terminal: right-click Command Prompt, then 'Run as administrator' 1>&2
  exit /b 1
)
exit /b 0

:CHECK_TOOLS
where git >nul 2>&1
if errorlevel 1 (
  echo     git is required; install Git for Windows and re-run 1>&2
  exit /b 1
)
where curl >nul 2>&1
if errorlevel 1 (
  echo     curl is required; it ships with Windows 10 and later 1>&2
  exit /b 1
)
exit /b 0

:INSTALL_CHEZMOI
where chezmoi >nul 2>&1
if not errorlevel 1 (
  for /f "delims=" %%v in ('chezmoi --version 2^>nul') do echo     chezmoi: %%v
  exit /b 0
)
where winget >nul 2>&1
if not errorlevel 1 (
  echo     installing chezmoi with winget...
  winget install --id twpayne.chezmoi -e --silent --accept-source-agreements --accept-package-agreements
)
call :REFRESH_PATH
where chezmoi >nul 2>&1
if not errorlevel 1 exit /b 0
where scoop >nul 2>&1
if not errorlevel 1 (
  echo     winget did not provide chezmoi; trying scoop...
  call scoop install chezmoi
)
call :REFRESH_PATH
where chezmoi >nul 2>&1
if errorlevel 1 (
  echo     chezmoi is still not on PATH; install it manually and re-run 1>&2
  exit /b 1
)
exit /b 0

:REFRESH_PATH
:: winget and scoop put their shims outside the PATH this process started with;
:: add the known locations so the checks above and chezmoi below can see them.
if exist "%LOCALAPPDATA%\Microsoft\WinGet\Links" set "PATH=%PATH%;%LOCALAPPDATA%\Microsoft\WinGet\Links"
if exist "%USERPROFILE%\scoop\shims" set "PATH=%PATH%;%USERPROFILE%\scoop\shims"
exit /b 0

:ENSURE_REPO
if exist "%SRC_DIR%\.git" (
  echo     updating %SRC_DIR%
  git -C "%SRC_DIR%" pull --ff-only || echo     pull skipped: local changes or no network
  exit /b 0
)
if not exist "%USERPROFILE%\bin" mkdir "%USERPROFILE%\bin"
echo     cloning into %SRC_DIR%
:: BatchMode keeps a first-time SSH connection from stopping on a host-key or
:: passphrase prompt; it fails immediately and the HTTPS fallback takes over.
set "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
git clone "%REPO_SSH%" "%SRC_DIR%" 2>nul
if not errorlevel 1 exit /b 0
echo     SSH clone failed, retrying over HTTPS
git clone "%REPO_HTTPS%" "%SRC_DIR%"
if errorlevel 1 exit /b 1
exit /b 0

:WRITE_CONFIG
if not exist "%CONFIG_DIR%" mkdir "%CONFIG_DIR%"
if exist "%CONFIG_DIR%\chezmoi.toml" (
  echo     keeping existing %CONFIG_DIR%\chezmoi.toml
  findstr /b /c:"sourceDir" "%CONFIG_DIR%\chezmoi.toml" >nul || echo     warning: no sourceDir in it; chezmoi may not find %SRC_DIR% 1>&2
  exit /b 0
)
:: chezmoi accepts forward slashes on Windows, and they avoid TOML escaping.
set "SRC_TOML=%SRC_DIR:\=/%"
> "%CONFIG_DIR%\chezmoi.toml" echo sourceDir = "%SRC_TOML%"
echo     wrote %CONFIG_DIR%\chezmoi.toml
exit /b 0

:INSTALL_TOOLS
:: install.bat reads cmds\addfonts.cmd relative to the working directory.
pushd "%WIN_DIR%"
call install.bat
set "RC=%errorlevel%"
popd
exit /b %RC%

:CHEZMOI_APPLY
chezmoi init --apply
exit /b %errorlevel%
