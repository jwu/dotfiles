# Windows 的 sshd：让别的机器用 `herdr machine add` 进来

这台 Windows 默认只有 OpenSSH **客户端**（`C:\Windows\System32\OpenSSH\`，9.5p2，随系统自带），
服务端是另一个能力，默认 `NotPresent`。`herdr` 的 SSH machine（`herdr machine add <target>`）
要求远端有可达的 shell，所以服务端得自己装。

## 安装（一次性，要管理员）

```powershell
Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
Set-Service sshd -StartupType Automatic
Start-Service sshd
Set-NetFirewallRule -Name 'OpenSSH-Server-In-TCP' -Profile Any
```

- 安装器自动建防火墙规则 `OpenSSH-Server-In-TCP`，但 `Profile` 只有 `Private`。网卡被系统判成
  公用网络的机器上，不改成 `Any` 就连不进。
- 主机密钥在安装时生成到 `C:\ProgramData\ssh\ssh_host_*`，不需要手工 `ssh-keygen`。

## 默认 shell 换成 pwsh

```powershell
# HKLM\SOFTWARE\OpenSSH
#   DefaultShell = C:\Program Files\PowerShell\7\pwsh.exe
```

只影响 ssh 会话；本地终端仍是 cmd + Clink（见 [`windows-shell.md`](windows-shell.md)）。
值必须是 **Windows 路径**，且 sshd 没有 `sh` 语义：远端命令是交给 `pwsh -c` 执行的。
这也是下面那条 `/bin/sh` 噪声的来处。

## 公钥位置：Administrators 组不读 `~/.ssh/authorized_keys`

默认 `sshd_config` 尾段：

```
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

本机账户在 Administrators 组，所以往 `~/.ssh/authorized_keys` 里加公钥是**静默无效**的。
那份文件还必须收紧 ACL，否则 sshd 以 `Bad owner or permissions` 拒读：

```powershell
icacls C:\ProgramData\ssh\administrators_authorized_keys /inheritance:r `
  /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F'
```

用 SID 而不是组名：中文系统的组名显示不一定是 `Administrators`。

## 公钥不是可选项：herdr 输不了密码

只配密码时，`herdr machine add` 会**静默悬停**：屏幕上只有那一行 `/bin/sh` 探测噪声，之后既无输出
也退不出。看着像网络问题，实际在等一个永远不会出现的密码——`remote/attach.rs` 给每条 ssh 都加了
`SSH_ASKPASS_REQUIRE=never`，密码提示只能走 `/dev/tty`，而 herdr 的 TUI 把它吞掉了。

判据在 sshd 自己的认证日志里（Event Log 不需要提权）：

```powershell
Get-WinEvent -LogName 'OpenSSH/Operational' -MaxEvents 40 |
  Where-Object { $_.Message -match 'Accepted|Failed' } |
  Select-Object TimeCreated, Message
```

实测对照：本机回环是 `Accepted publickey for <user> from 127.0.0.1 … ED25519 SHA256:…`，而远处那台
Mac 连续三条都是 `Accepted password for <user> from <mac-ip> …` —— 手敲 `ssh` 时输密码能通，
所以很容易误判成“ssh 没问题”。

追加公钥（文件已存在时 `Add-Content` 不改 ACL，安全）：

```powershell
Add-Content -LiteralPath C:\ProgramData\ssh\administrators_authorized_keys -Value 'ssh-ed25519 AAAA… mac'
```

### 为什么 `ssh-copy-id` 在这里没用

1. 它写的是 `~/.ssh/authorized_keys`，而 `Match Group administrators` 让管理员组只读
   `administrators_authorized_keys`——它会报成功，然后认证照样要密码。
2. 它需要在远端跑 `mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys && chmod …`，而 DefaultShell
   是 pwsh，这些 POSIX 语法直接失败（就是那一行 `/bin/sh` 的来源）。
3. 它没有 ACL 概念，而 sshd 对授权文件只认 `SYSTEM` + `Administrators` + 本人。

所以只能走 PowerShell 的 `Add-Content`，或者把公钥贴给能提权的一方代写。

## 坑：scoop 的 `current` 是挂载点，提权令牌穿不过去

症状——本地 pwsh 一切正常，一 ssh 就刷出一屏错误，把 `herdr` 的输出解析搅乱：

```
&: C:\Users\<user>\Documents\PowerShell\Microsoft.PowerShell_profile.ps1:14
     | Invoke-Expression (& starship init powershell | Out-String)
     |                     ~~~~~~~~
     | 术语 'starship' 不会被识别为 cmdlet、函数、脚本文件或可执行程序的名称。
Shim: Could not create process with command '"...\apps\zoxide\current\zoxide.exe"  init powershell'.
```

原因不在 starship，也不在 PATH（ssh 会话的 `PATH` 里 `scoop\apps\starship\current` 与 `scoop\shims`
都在）：

1. scoop 的 `apps\<name>\current` 是 NTFS junction（reparse tag `0xa0000003`，Mount Point）。
2. 这个挂载点坐在**普通用户可写**的目录里，Windows 因此把它视为可被低完整性进程替换的
   “不受信任的装入点”。
3. sshd 给 Administrators 成员的是完整令牌（High Mandatory Level），Windows 拒绝从 High IL
   穿越这种挂载点，直接报「无法遍历该路径，因为它包含不受信任的装入点」
   （junction attack 防护）。本地终端跑的是 Medium IL，所以本地没症状。

`GetChildItem` 会因此返回空、`Test-Path current\tool.exe` 返回 `False`，看着像文件丢了；直接访问
`apps\<name>\<version>\` 实体目录则完全正常。改 ACL 不是解法——那会破坏 scoop 在普通用户下的写入。

解法写在 profile 源 `Documents/PowerShell/Microsoft.PowerShell_profile.ps1` 的 `Resolve-ScoopApp`：
绕开 `current`，按 `apps\<name>\<version>\<name>.exe` 找实体目录。

- 版本目录按 `LastWriteTime` 降序取最新一个。字符串排序不可用：`1.9.0` 会排在 `1.26.0` 后面。
- 解不出路径时静默跳过，宁肯退化到默认 `PS>` 提示符，也不往会话里打错误——`herdr` 之类的
  工具会解析 ssh 的输出。
- 路径来源优先 `$env:SCOOP`，否则 `%USERPROFILE%\scoop`。

## 已知噪声：`herdr machine add` 会先试 `/bin/sh -s`

从别的机器 `herdr machine add` 到这台时，终端里会先出现一行：

```
/bin/sh: 术语 '/bin/sh' 不会被识别为 cmdlet、函数、脚本文件或可执行程序的名称。
```

然后照常 `Saved SSH machine … Remote server is ready.`。**这一行不影响功能**，是探测阶段的残渣。

`src/remote/attach.rs:1530` 的 `detect_remote_platform()` 先无条件走 `sh_output()`（`attach.rs:853`）：
`ssh <target> "/bin/sh -s"`，再把 `uname -s; uname -m` 喂到 stdin。pwsh 把 `/bin/sh` 当命令名，
报错并 exit 1；`should_try_windows_probe()` 因此放行回退，走
`windows_powershell_script_command()` —— 显式 `powershell.exe -NoLogo -NoProfile -NonInteractive
-EncodedCommand <base64>`，不依赖 DefaultShell —— 拿到 `herdr-windows:AMD64` 后判定 Windows 平台，
后面的安装与启动全走 Windows 分支。

让它不吭声的唯一办法是让远端 shell 能执行 `/bin/sh -s`，即把 DefaultShell 换成 Git Bash：

```
sh.exe -c "/bin/sh -s"   →   MINGW64_NT-10.0-26200 / x86_64   (exit 0)
```

这样 `looks_like_windows_uname()` 命中，直接进 Windows 探测，零噪声。没这么做是因为代价更大：
ssh 交互登录会变成 MSYS sh/bash，starship 与 pwsh profile 全部失效，而这只是 `machine add`
时的一行输出。**herdr 的 pane shell 不受这条影响**，它读 `[terminal] default_shell`
（或 Windows 默认的 PowerShell），不是 sshd 的 DefaultShell。

**别把这行噪声当成失败。** 它是每次 `machine add` 必打的一行，与卡住无关；真正的静默悬停
是上一节的密码认证。两者症状都在同一屏上，先看 Event Log 里的 `Accepted password` /
`Accepted publickey` 再判断。

## 诊断：临时把 sshd 日志调到 DEBUG

命令行级别的记录只出现在 `LogLevel DEBUG1` 以上，且必须落到文件：

```
SyslogFacility LOCAL0
LogLevel DEBUG1
Match Group administrators
       AuthorizedKeysFile __PROGRAMDATA__/ssh/administrators_authorized_keys
```

两行**必须插在 `Match` 之前**。`Match` 之后的关键字属于该块，写在末尾不会成为全局设置，
改了等于没改。日志落 `C:\ProgramData\ssh\logs\sshd.log`，该目录只有 `SYSTEM` 与
`Administrators` 可读——不提权直接 `ls` 会 `Permission denied`，这种情况下改用 Event Log 那条命令。

改完 `Restart-Service sshd`（会断掉现有 ssh 会话），诊断完把这两行删掉并重启服务。

## 验证

```powershell
# 在另一台机器上
ssh <user>@<host> whoami                                  # 不应出现任何 stderr
ssh <user>@<host> 'if ($function:prompt) { "starship" }'  # 远端仍是 starship 提示符
```

`herdr machine add` 自己会下载并启动远端 herdr server；它只在 ssh 输出干净时才能正确判定。
认证类型可以在同一份日志里确认：`Accepted publickey` 才是 herdr 可用的状态。

## 没做的

- 端口仍是 22，密码认证没关（公钥配好后 herdr 走公钥，密码只是保留给人手登录）。
- sshd 属于系统层，不进本仓库的源；这里只记下装法与几个坑。
