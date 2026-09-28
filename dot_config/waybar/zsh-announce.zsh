# Announce this shell to waybar's niri-windows module, so that it measures this
# window instead of the whole terminal process: the shell writes its pid into the
# window title, in tag characters GTK drops. Source it last in ~/.zshrc, after
# anything else that sets the title. See docs/waybar.md.

# Only a local shell should announce: inside ssh the title belongs to the terminal
# on the other side, whose waybar cannot use this pid, and macOS titlebars draw the
# tag digits as missing-glyph boxes (GTK/Pango drops them). See docs/waybar.md.
[[ -n ${SSH_CONNECTION:-} || -n ${SSH_TTY:-} ]] && return 0

# Unicode tag characters: default-ignorable, so GTK/Pango drops them (macOS
# titlebars draw them). The module's grammar takes a decimal pid between U+E0001
# and U+E007F.
typeset -ga _wnw_tag_digit=(
  $'\U000E0030' $'\U000E0031' $'\U000E0032' $'\U000E0033' $'\U000E0034'
  $'\U000E0035' $'\U000E0036' $'\U000E0037' $'\U000E0038' $'\U000E0039'
)

# _wnw_tag [pid]: the announcement for a pid (this shell's by default).
_wnw_tag() {
  local digits=${1:-$$} out=$'\U000E0001' i
  for (( i = 1; i <= ${#digits}; i++ )); do
    out+=$_wnw_tag_digit[${digits[i]}+1]
  done
  print -rn -- "$out"$'\U000E007F'
}

# Built once: a shell keeps its pid for life. $$ is the shell that started, not a
# subshell, which is what a window's shell is.
typeset -g _wnw_announcement=$(_wnw_tag $$)

# Where the title goes: Ghostty's shell-integration fd, else the terminal (which
# keeps the title out of a redirected stdout), else stdout.
typeset -gi _wnw_fd=1
if [[ -n ${_ghostty_fd:-} ]]; then
  _wnw_fd=$_ghostty_fd
elif [[ -n ${TTY:-} && -w $TTY ]] && zmodload zsh/system 2>/dev/null; then
  sysopen -o cloexec -wu _wnw_fd -- "$TTY" 2>/dev/null || _wnw_fd=1
fi

# _wnw_title <text>: show <text>, then this shell's announcement. Control
# characters are dropped, so a working directory cannot end the escape sequence.
_wnw_title() {
  builtin print -rnu $_wnw_fd -- $'\e]2;'"${1//[[:cntrl:]]}$_wnw_announcement"$'\a'
}

# _wnw_precmd: rewrite the title at every prompt. Uses the same idle title the
# prompt's own hook would, so a window is named the same either way.
_wnw_precmd() {
  local text=${ZSH_THEME_TERM_TITLE_IDLE-'%(4~|…/%3~|%~)'}
  _wnw_title "${(%)text}"
}

# add-zsh-hook appends, so this lands after a shell integration sourced before
# ~/.zshrc; it also refuses to add the same hook twice.
autoload -Uz add-zsh-hook

# An older version rewrote the title before every command too. Drop that hook, so
# re-sourcing this file in a shell that had it leaves command titles alone.
add-zsh-hook -d preexec _wnw_preexec

add-zsh-hook precmd _wnw_precmd
