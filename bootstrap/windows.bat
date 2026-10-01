@echo off
setlocal enabledelayedexpansion
:: ========================================
:: dotfiles bootstrap (Windows), the third entry point next to
:: bootstrap/arch.sh and bootstrap/macos.sh.
::
:: Replaces the retired jwu/configs flow: clone the config repo, run
:: win/install.bat for the portable tools, then win/config.bat to generate the
:: pointer files. All three are gone -- scoop installs the tools, chezmoi
:: deploys the real content, and the terminals inject Clink via session.cmd.
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
if not defined PI_REPO_SSH set "PI_REPO_SSH=git@github.com:jwu/pi-config.git"
if not defined PI_REPO_HTTPS set "PI_REPO_HTTPS=https://github.com/jwu/pi-config.git"
if not defined PI_DIR set "PI_DIR=C:\bin\pi-config"
set "CONFIG_DIR=%USERPROFILE%\.config\chezmoi"
set "SCOOP_APPS=clink clink-completions starship fzf zoxide fd bat delta ripgrep eza just cocogitto uutils-coreutils alacritty"
set "SCOOP_FONT=FiraMono-NF"
set "SCOOP_DEV=uv bun nodejs-lts"
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
call :DO "developer runtimes (uv, bun, nodejs-lts)" :SCOOP_DEV_RUNTIMES
call :DO "rustup + stable toolchain" :DEV_RUSTUP
call :DO "user environment variables" :WRITE_ENV
call :DO "clink: register clink-completions" :CLINK_SCRIPTS
call :DO "pi-config checkout" :ENSURE_PI_CONFIG

call :REQUIRE "chezmoi init --apply" :CHEZMOI_APPLY || goto :ABORT

call :SUMMARY
echo.
echo ^>^>^> Restart your terminal: Alacritty and WezTerm launch session.cmd, which
echo     injects Clink and sets the environment in cmd's own block. A plain cmd
echo     started from Win+R has neither; see docs/windows-shell.md.
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

:ENSURE_PI_CONFIG
:: pi loads extensions/ live from the checkout, so the settings.json chezmoi
:: writes points at %PI_DIR%\extensions. nodejs now comes from scoop above; pi
:: itself is still a manual install on Windows, so this step only keeps the
checkout in place.
:: See docs/design.md, the pi-config orchestration section.
if exist "%PI_DIR%\.git" (
  echo     updating %PI_DIR%
  git -C "%PI_DIR%" pull --ff-only || echo     pull skipped: local changes or no network
  exit /b 0
)
if not exist "C:\bin" mkdir "C:\bin"
echo     cloning into %PI_DIR%
:: BatchMode keeps a first-time SSH connection from stopping on a host-key or
:: passphrase prompt; it fails immediately and the HTTPS fallback takes over.
set "GIT_SSH_COMMAND=ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new"
git clone "%PI_REPO_SSH%" "%PI_DIR%" 2>nul
if not errorlevel 1 exit /b 0
echo     SSH clone failed, retrying over HTTPS
git clone "%PI_REPO_HTTPS%" "%PI_DIR%"
exit /b %errorlevel%

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

:SCOOP_DEV_RUNTIMES
:: uv, bun and Node LTS come from scoop like the rest of the shell tools: their
:: shims land on a PATH that is already set up, so nothing here touches the
:: user environment. See docs/dev-env.md.
echo     Installing: %SCOOP_DEV%
call scoop install %SCOOP_DEV%
exit /b %errorlevel%

:DEV_RUSTUP
:: Rust's own installer rather than a manifest: rustup owns the toolchains, and
:: on Windows it is also the thing that appends %USERPROFILE%\.cargo\bin to the
:: user PATH -- Unix gets that line from dot_zshrc.tmpl instead, which is why
:: the Unix side passes --no-modify-path.
where rustup >nul 2>&1
if not errorlevel 1 (
  echo     rustup is already installed
  call rustup default stable
  if errorlevel 1 exit /b 1
  exit /b 0
)
set "RUSTUP_INIT=%TEMP%\rustup-init.exe"
curl -fsSL -o "%RUSTUP_INIT%" https://win.rustup.rs/x86_64
if errorlevel 1 (
  echo     downloading rustup-init.exe failed 1>&2
  exit /b 1
)
"%RUSTUP_INIT%" -y
set "RUSTUP_RC=%errorlevel%"
del "%RUSTUP_INIT%" >nul 2>&1
if not "%RUSTUP_RC%"=="0" exit /b %RUSTUP_RC%
:: The installer edits the registry, not this process, so make the shim visible
:: for the toolchain select below.
set "PATH=%PATH%;%USERPROFILE%\.cargo\bin"
:: rustup ships no toolchain, so cargo does not exist until this runs.
rustup default stable
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
:: The scoop clink-completions package registers its own directory at install
:: time; re-assert it here. Its top-level scripts are the argmatchers for git,
:: npm, scoop and friends, and its completions\ subdirectory is only found under
:: a registered script directory -- dropping the registration costs every one of
:: them (see docs/windows-shell.md).
call clink installscripts "%USERPROFILE%\scoop\apps\clink-completions\current"
exit /b 0

:CHEZMOI_APPLY
chezmoi init --apply
exit /b %errorlevel%
