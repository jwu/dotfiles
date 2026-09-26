@echo off
setlocal enabledelayedexpansion
:: ========================================
:: dotfiles bootstrap (Windows), the third entry point next to
:: bootstrap/arch.sh and bootstrap/macos.sh.
::
:: Replaces the retired jwu/configs flow: clone the config repo, run
:: win/install.bat for the portable tools, then win/config.bat to generate the
:: pointer files. All three are gone -- scoop installs the tools, chezmoi
:: deploys the real content, and Clink registers itself in cmd.exe's AutoRun.
::
:: Needs no administrator rights: scoop installs per-user and the Nerd Font goes
:: to %LOCALAPPDATA%\Microsoft\Windows\Fonts, so nothing here -- or in
:: `chezmoi apply` -- needs elevation or a terminal. See docs/design.md, the
:: bootstrap section.
::
:: Usage (curl.exe ships with Windows 10+):
::   curl -fsSL https://raw.githubusercontent.com/jwu/dotfiles/main/bootstrap/windows.bat -o "%TEMP%\dotfiles-bootstrap.bat"
::   "%TEMP%\dotfiles-bootstrap.bat"
:: ========================================

if not defined REPO_SSH set "REPO_SSH=git@github.com:jwu/dotfiles.git"
if not defined REPO_HTTPS set "REPO_HTTPS=https://github.com/jwu/dotfiles.git"
if not defined SRC_DIR set "SRC_DIR=%USERPROFILE%\bin\dotfiles"
set "CONFIG_DIR=%USERPROFILE%\.config\chezmoi"
set "SCOOP_APPS=clink clink-completions starship fzf zoxide fd bat delta ripgrep eza uutils-coreutils alacritty"
set "SCOOP_FONT=FiraMono-NF"
set "ERROR_COUNT=0"

echo ^>^>^> dotfiles bootstrap ^(Windows^)
echo     repo:      %REPO_SSH%
echo     sourceDir: %SRC_DIR%

call :REQUIRE "git, curl and scoop" :CHECK_TOOLS || goto :ABORT
call :REQUIRE "install chezmoi" :INSTALL_CHEZMOI || goto :ABORT
call :REQUIRE "clone/update dotfiles" :ENSURE_REPO || goto :ABORT
call :REQUIRE "configure chezmoi sourceDir" :WRITE_CONFIG || goto :ABORT

call :DO "scoop buckets (extras, nerd-fonts)" :SCOOP_BUCKETS
call :DO "scoop packages" :SCOOP_PACKAGES
call :DO "user environment variables" :WRITE_ENV
call :DO "clink: lazy completions only" :CLINK_SCRIPTS

call :REQUIRE "chezmoi init --apply" :CHEZMOI_APPLY || goto :ABORT

call :SUMMARY
echo.
echo ^>^>^> Restart your terminal: Clink now loads from cmd.exe's AutoRun in every
echo     cmd, so nothing has to launch a setup script any more.
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

:CHECK_TOOLS
:: scoop is the package manager for the shell tools; git and curl are what this
:: script itself needs. All three are per-user installs.
for %%t in (git curl scoop) do (
  where %%t >nul 2>&1
  if errorlevel 1 (
    echo     %%t is required; install it and re-run 1>&2
    exit /b 1
  )
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

:SCOOP_BUCKETS
:: extras has alacritty; nerd-fonts has FiraMono-NF. Adding a bucket that is
:: already there only prints a message, so both are safe to re-run.
call scoop bucket add extras
call scoop bucket add nerd-fonts
exit /b 0

:SCOOP_PACKAGES
echo     Installing: %SCOOP_APPS%
call scoop install %SCOOP_APPS%
if errorlevel 1 exit /b 1
:: The font manifest installs into %LOCALAPPDATA%\Microsoft\Windows\Fonts on
:: Windows 10 1809 and later, which is why this no longer needs admin.
echo     Installing %SCOOP_FONT%
call scoop install %SCOOP_FONT%
exit /b %errorlevel%

:WRITE_ENV
:: Per-user variables, so every process sees them -- not only the terminal that
:: happened to launch a setup script. Clink's own os.setenv does not touch cmd's
:: environment block, so anything starship or cmd must see has to live here.
:: PATH already carries ~\bin and the scoop shims, so nothing is added there.
call setx LANG "en_US.utf8" >nul || exit /b 1
call setx PI_NERD_FONTS "1" >nul || exit /b 1
call setx FZF_COMPLETE_OPTS "-e" >nul || exit /b 1
call setx STARSHIP_CONFIG "%USERPROFILE%\.config\starship.toml" >nul || exit /b 1
exit /b 0

:CLINK_SCRIPTS
:: The scoop clink-completions package registers its own directory with
:: 'clink installscripts', which makes Clink eager-load every top-level script in
:: it. The session launcher points CLINK_COMPLETIONS_DIR at just the completions
:: subdirectory instead (Clink loads those on demand), so drop the registration.
:: Not fatal if it is absent: 'clink uninstallscripts' then just reports it.
call clink uninstallscripts "%USERPROFILE%\scoop\apps\clink-completions\current"
exit /b 0

:CHEZMOI_APPLY
chezmoi init --apply
exit /b %errorlevel%
