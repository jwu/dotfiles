-- Session setup for cmd.exe, loaded by Clink from %LOCALAPPDATA%\clink.
--
-- Replaces the retired win/init.bat. That script set the codepage, the PATH and
-- the doskey aliases, and every terminal had to launch 'cmd /k init.bat' to get
-- them. The PATH entry was already a per-user variable, the codepage and the
-- aliases belong to the session, and Clink now loads itself through its own
-- cmd.exe AutoRun entry, so this file is all that is left.
--
-- Clink has no alias API, so the aliases are first-word rewrites through
-- clink.onfilterinput -- the same mechanism zoxide.lua uses. See docs/design.md.
--
-- The ln/mv/rm/cp/pwd aliases the old script defined are gone: scoop's
-- uutils-coreutils puts those binaries on PATH directly, so nothing has to
-- redirect to a 'coreutils' multicall. mkdir and rmdir are also gone -- they
-- are cmd builtins, which win over anything on PATH anyway.

-- cmd starts at the OEM codepage (936 here), which garbles eza and starship
-- output. chcp changes the console rather than just this process, so the cmd
-- that injected Clink sees it too. Suppress the "Active code page" line.
os.execute('>nul 2>nul chcp 65001')

-- name -> expansion; whatever follows the name on the line is appended, which
-- is what doskey did with the trailing $* in the old macro file.
local aliases = {
  clear = 'cls',
  open = 'explorer',
  vi = 'nvim',
  gl = 'git log --oneline --all --graph --decorate',
  ls = 'eza',
  ll = 'eza -lh --icons',
  la = 'eza -lah --icons',
  lt = 'eza --tree --icons',
  pon = 'set HTTP_PROXY=http://127.0.0.1:7890& set HTTPS_PROXY=http://127.0.0.1:7890& set ALL_PROXY=socks5://127.0.0.1:7890& echo [Clash] Terminal Proxy ON (Port: 7890)',
  poff = 'set HTTP_PROXY=& set HTTPS_PROXY=& set ALL_PROXY=& echo [Clash] Terminal Proxy OFF',
  pstat = 'echo HTTP:  %HTTP_PROXY% & echo HTTPS: %HTTPS_PROXY% & echo ALL:   %ALL_PROXY%',
}

clink.onfilterinput(function(text)
  local name, rest = text:match('^%s*(%S+)%s*(.*)$')
  if not name then
    return
  end
  local expansion = aliases[name:lower()]
  if not expansion then
    return
  end
  if rest == '' then
    return expansion
  end
  return expansion .. ' ' .. rest
end)
