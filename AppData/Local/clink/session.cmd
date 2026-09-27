@echo off
:: Session setup for cmd.exe, launched by the terminals as
:: `cmd /s /k "%LOCALAPPDATA%\clink\session.cmd"`.
::
:: This is the equivalent of the retired win/init.bat, and it exists because of
:: one difference that bit us: a script run by cmd can `set` variables in cmd's
:: own process, while Clink's os.setenv cannot touch cmd's environment block.
:: So the environment and the injection have to happen here.
::
:: `--profile` and `--scripts` point at %LOCALAPPDATA%\clink explicitly: that is
:: where chezmoi deploys clink.lua / session.lua / fzf.lua / zoxide.lua. The
:: clink-completions package is not part of this path -- it is registered with
:: 'clink installscripts' in bootstrap/windows.bat, and only a registered script
:: directory makes Clink find its completions\ subdirectory for on-demand load.
::
:: See docs/windows-shell.md.

chcp 65001 >nul

set "STARSHIP_CONFIG=%USERPROFILE%\.config\starship.toml"
set "LANG=en_US.utf8"
set "PI_NERD_FONTS=1"
set "FZF_COMPLETE_OPTS=-e"

clink inject --quiet --profile "%LOCALAPPDATA%\clink" --scripts "%LOCALAPPDATA%\clink"

exit /b
