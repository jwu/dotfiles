# Working in this repository

Read `README.md` for the design. This file is the short list of rules for whoever
(or whatever) edits here next.

## Comments: concise English

Every comment in this repository — chezmoi source files (`dot_*`, `*.tmpl`), the
`run_*` scripts, `bootstrap/*.sh`, helpers under `scripts/`, and the config files
they deploy — is written in **English**, and kept **short**.

1. Say only what the code cannot: a non-obvious constraint, or a pointer.
2. **Move the reasoning to `docs/`.** Measurements, rejected alternatives, upstream
   bugs, machine-specific quirks, "why not the obvious thing" — those go in a topic
   file under `docs/`, and the comment points at it:

   ```sh
   # Wayland client-side decorations only; see docs/alacritty.md.
   ```

A comment longer than a few lines in a config file or script is almost always a
sign that a `docs/` file should exist.

`README.md` and `docs/` stay in **Chinese**: they are the design record, not code.
Commit messages are English, and explain *why*.

## What is not a comment

Do not translate user-visible strings to satisfy the rule above. These are content,
and changing them changes what the user sees:

- `format` / `tooltip-format` strings in `dot_config/waybar/**`
- the `emit_off()` messages in `scripts/gpu-watch.c`
- `--help` text in `scripts/update-rime-dict.sh`
- the 中 glyph in `dot_local/share/icons/**`
- Rime option *names* (`hilited_candidate_text_color` and friends); the inline
  annotations beside them are ordinary comments and do get translated

## Not covered

`private_dot_pi/private_agent/{agents,skills,prompts}/**` is pi's own prompt
content, not comments. It is written for a model to read and is left alone.

## Before committing

```bash
chezmoi diff --include=files    # must be empty
chezmoi apply -v                # run twice; the second run must print nothing
```

A `run_onchange_` script re-runs when its content changes. A script that *failed*
is still recorded in `scriptState` and will not retry, so clear the bucket first:

```bash
chezmoi state delete-bucket --bucket=scriptState
```

Never let a platform-inappropriate `run_*` script fail: exit 0 instead
(`docs/chezmoi-notes.md`).
