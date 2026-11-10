// Workspace spaces: stable colored avatars, worktrees under their checkout,
// grouped by machine when more than one is known. After a space's name, the repo
// its first terminal is in now, only where unusual: branch, ahead/behind. Agent state lives in the agents list, not here. Click to
// switch, right-click for its menu, drag to reorder.

import { View, div, svg } from "gpui-kit";
import { v_flex, h_flex } from "gpui-base";
import { spaces, machines, panes, run, openOverlay, exec, hc, theme, shared, setShared, watchFolder, window, layout } from "herdr";

function find(node, id) {
  if (node?.id === id) return node;
  for (const child of node?.children ?? []) {
    const found = find(child, id);
    if (found) return found;
  }
  return null;
}

// The sidebar's rail goes by its width, not a flag: dragging its edge narrows it too.
const narrow = () => (find(layout(), "sidebar")?.size?.px ?? Infinity) < 160;

// Where a space is now: its first terminal's live folder, else where it was made.
// `ps`: panes(), read once by the caller (each read copies every pane).
function place(s, ps) {
  const tabs = new Set((s.tabs ?? []).map((c) => c.id));
  return ps.find((p) => tabs.has(p.tab) && p.cwd)?.cwd || s.folder;
}
const rowHeight = ({ tree }) => (tree ? 28 : 30);
const RAIL_CELL = 32;
const railCell = (el) => h_flex().flex_none().justify_center().child(el);
const where = (s, ps) => JSON.stringify([s.machine ?? null, place(s, ps)]);
const base = (path) => path.replace(/\/+$/, "").split("/").pop();
// Changes made outside Herdr (an editor's save, a commit in another app): looked
// for this often, in repos the list shows, while the window is in front.
const FALLBACK = 60000;

// The second line under a machine's name: CPU and memory, read from that
// machine's own shell. Linux counters are compared with the previous reading;
// macOS has no such counters a shell can read, so `ps` sums what is running.
// A machine without a POSIX shell (Windows) keeps the placeholders.
const STAT_EVERY = 5000;
const CPU_WARN = 75;
const MEM_WARN = 80;
// A machine row's CPU sparkline: samples kept, bar width and gap, its height.
const HISTORY = 16;
const BAR_W = 3;
const BAR_GAP = 1;
const GRAPH_H = 14;
const METER_W = 36;
const STAT_SCRIPT = [
  'os=$(uname -s 2>/dev/null) || exit 1',
  'echo "os $os"',
  'case "$os" in',
  '  Linux|MINGW*|MSYS*|CYGWIN*)',
  '    echo "cores $(getconf _NPROCESSORS_ONLN 2>/dev/null)"',
  '    head -n 1 /proc/stat',
  "    grep -E '^(MemTotal|MemAvailable|MemFree):' /proc/meminfo",
  '    ;;',
  '  Darwin)',
  '    echo "cores $(sysctl -n hw.ncpu 2>/dev/null)"',
  '    echo "memsize $(sysctl -n hw.memsize 2>/dev/null)"',
  '    vm_stat',
  '    ps -A -o %cpu=',
  '    ;;',
  'esac',
].join("\n");
const clamp = (v) => Math.min(100, Math.max(0, v));

// A space speaks up only when something in it needs you.
export function glyph(status) {
  return status === "blocked" || status === "done" ? "●" : "·";
}

export function tone(t, status) {
  return t[status] ?? t.unknown;
}

// A space's state, drawn as the agents list draws an agent's: a spinner while
// working, a badge when blocked, a ring when idle, a dot when done.
export function mark(status, t) {
  if (status === "working") return svg("mods/workspace-chrome/spinner.svg").size(12).mx(1).flex_none().text_color(t.working).spin(900);
  if (status === "blocked") return div().size(14).flex_none().rounded(4).bg(t.blocked + "26").text_size(10.5).font_bold().text_color(t.blocked).flex().items_center().justify_center().child("!");
  if (status === "idle") return div().size(7).mx(3).flex_none().rounded(4).border(1.5).border_color(t.idle ?? t.dim);
  if (status === "done") return div().size(7).mx(3).flex_none().rounded(4).bg(t.done);
  return null;
}

export default class Spaces extends View {
  init(_props, cx) {
    this.git = {}; // where() -> { name, branch, ahead, behind, repo, linked }, null: not a repo
    this.checked = {}; // where() -> when it was last looked at
    this.unsure = new Set(); // where()s git couldn't answer for (a machine away)
    this.pending = new Set(); // where()s to look at next
    this.busy = {}; // pane -> an agent working or a program in front of its shell
    this.ready = {}; // machine -> its layout was readable at the last look
    this.at = {}; // space -> its where() at the last look
    this.watching = new Set(); // local repos' git folders
    // Spaces made while this runs wait (at most a moment) for their git, so a
    // worktree appears under its repo instead of jumping there.
    this.shown = new Set(spaces().map((s) => s.id));
    this.born = {};
    this.pressed = null;
    this.over = null;
    this.machines = [];
    this.stats = {}; // machine -> { cpu, mem, cores }, percentages or null
    this.history = {}; // machine -> its last CPU shares, oldest first
    this.ticks = {}; // machine -> its last Linux CPU counters
    this.statsAt = {}; // machine -> when it was last asked
    this.sampling = new Set(); // machines a sample is in flight for
    this.reconnecting = JSON.parse(localStorage.getItem("machines.reconnecting") ?? "{}");
    for (const state of Object.values(this.reconnecting)) state.busy = false;
    this.folded = new Set(JSON.parse(localStorage.getItem("machines.folded") ?? "[]"));
    this.refreshMachines(cx);
    cx.timer.every(15000, cx => this.refreshMachines(cx));
    cx.timer.every(2000, cx => this.refreshStats(cx));
    // `git status` walks the whole tree, on another machine a process there:
    // only when its answer could have changed (see `due`).
    cx.timer.every(250, (cx) => this.checkNew(cx));
  }

  checkNew(cx) {
    const now = Date.now();
    const sp = spaces();
    for (const s of sp) if (!this.shown.has(s.id)) this.born[s.id] ??= now;
    const due = this.due(now, sp, panes());
    if (due.size) this.refreshGit(due, cx);
    if (sp.some((s) => !this.shown.has(s.id)) || this.orderingDue(now)) cx.notify();
  }

  // Places whose git could have changed: new ones (a new space, a cd), where a
  // command or an agent's turn just ended (a checkout, a commit, edits), those on
  // a machine that is back, and repos in view whose fallback is due.
  due(now, sp, ps) {
    // Moved there: what it knew of that place may be old.
    const at = {};
    for (const s of sp) at[s.id] = where(s, ps);
    const keys = new Set(Object.values(at).filter((k) => JSON.parse(k)[1]));
    const due = new Set([...keys].filter((k) => !(k in this.git)));
    for (const [id, k] of Object.entries(at)) if (this.at[id] && this.at[id] !== k && keys.has(k)) due.add(k);
    this.at = at;
    const spaceOf = {};
    for (const s of sp) for (const t of s.tabs ?? []) spaceOf[t.id] = s;
    const busy = {};
    for (const p of ps) {
      if (!p.terminal || !spaceOf[p.tab]) continue;
      busy[p.pane] = p.status === "working" || !(p.program?.shell || p.program?.agent);
      if (this.busy[p.pane] && !busy[p.pane]) this.sameRepo(at[spaceOf[p.tab].id], keys).forEach((k) => due.add(k));
    }
    this.busy = busy;
    for (const m of machines()) {
      const ready = m.layout === "ready";
      if (ready && this.ready[m.name] === false) for (const k of keys) if (JSON.parse(k)[0] === m.name) due.add(k);
      this.ready[m.name] = ready;
    }
    if (window().active) {
      for (const k of keys) {
        const asks = this.git[k] || this.unsure.has(k);
        if (asks && !this.folded.has(JSON.parse(k)[0]) && now - (this.checked[k] ?? 0) > FALLBACK) due.add(k);
      }
    }
    return due;
  }

  // `key` and the other places in its repo (a commit there moves their ahead/behind).
  sameRepo(key, keys) {
    const repo = this.git[key]?.repo;
    return [key, ...(repo ? [...keys].filter((k) => this.git[k]?.repo === repo) : [])];
  }

  refreshMachines(cx) {
    cx.spawn(async cx => {
      try { const r = await hc(["machine", "ls", "--json"]); if (r.code === 0) this.machines = (JSON.parse(r.stdout).machines ?? []).filter((m) => !m.temporary); } catch {}
      cx.notify();
    });
  }

  // Ask each connected machine for its load; a slow or away machine misses its
  // turn without holding the others up.
  refreshStats(cx) {
    const now = Date.now();
    for (const m of [null, ...this.machines.filter(k => k.state === "connected").map(k => k.name)]) {
      const key = m ?? "";
      if (this.sampling.has(key) || now - (this.statsAt[key] ?? 0) < STAT_EVERY) continue;
      this.statsAt[key] = now;
      this.sampling.add(key);
      cx.spawn(async (cx) => {
        try {
          const r = await exec("sh", ["-c", STAT_SCRIPT], { on: m, timeout: 15000 });
          if (r.code === 0) this.takeStats(key, r.stdout);
          else if (this.stats[key]) this.stats[key].stale = true;
        } catch {
          if (this.stats[key]) this.stats[key].stale = true;
        }
        this.sampling.delete(key);
        cx.notify();
      });
    }
  }

  // One machine's answer: `os`, cores, memory, CPU counters (Linux) or a
  // moment of `ps` (macOS).
  takeStats(key, out) {
    const lines = out.split("\n").map(l => l.trim()).filter(Boolean);
    const os = lines[0]?.startsWith("os ") ? lines[0].slice(3) : "";
    const num = (v) => { const n = Number(v); return Number.isFinite(n) ? n : null; };
    const field = (name) => num(lines.find(l => l.startsWith(name + " "))?.slice(name.length + 1));
    let cpu = null, mem = null, cores = field("cores");
    if (/^(Linux|MINGW|MSYS|CYGWIN)/.test(os)) {
      const stat = lines.find(l => l.startsWith("cpu "));
      const f = stat ? stat.split(/\s+/).slice(1).map(Number) : [];
      if (f.length >= 4 && f.every(Number.isFinite)) {
        const total = f.reduce((a, b) => a + b, 0);
        const idle = f[3] + (f[4] ?? 0);
        const prev = this.ticks[key];
        if (prev && total > prev.total) cpu = clamp((1 - (idle - prev.idle) / (total - prev.total)) * 100);
        this.ticks[key] = { total, idle };
      }
      const kb = (name) => {
        const l = lines.find(x => x.startsWith(name + ":"));
        const v = l ? num(l.slice(name.length + 1).replace(/[^\d.]/g, "")) : null;
        return v == null ? null : v * 1024;
      };
      const total = kb("MemTotal"), free = kb("MemAvailable") ?? kb("MemFree");
      if (total && free != null) mem = clamp((total - free) / total * 100);
    } else if (os === "Darwin") {
      const page = num(/page size of (\d+) bytes/.exec(out)?.[1]) ?? 4096;
      const pages = (name) => {
        const l = lines.find(x => x.startsWith(name + ":"));
        return l ? num(l.slice(name.length + 1).replace(/[^\d.]/g, "")) : null;
      };
      const used = ["Pages active", "Pages speculative", "Pages wired down", "Pages occupied by compressor"]
        .reduce((a, name) => a + (pages(name) ?? 0), 0);
      const total = field("memsize");
      if (total) mem = clamp(used * page / total * 100);
      // `ps` prints one percentage per process, of one core each.
      const sum = lines.filter(l => /^\d+(\.\d+)?$/.test(l)).reduce((a, v) => a + Number(v), 0);
      if (cores && sum > 0) cpu = clamp(sum / cores);
    }
    if (cpu != null) {
      const hist = (this.history[key] ??= []);
      hist.push(cpu);
      if (hist.length > HISTORY) hist.shift();
    }
    this.stats[key] = { cpu, mem, cores, stale: false, at: Date.now() };
  }

  // CPU and memory shares under a machine's name, as Sheprd's host rows:
  // `CPU ▁▂▃ 12%  MEM ━━─ 61%` while the sidebar has room, small gauges
  // where it is narrower (Sheprd's compact density), the numbers always. A
  // stale reading keeps its numbers gray.
  usage(m, t, live) {
    const key = m ?? "";
    const s = live ? (this.stats[key] ?? {}) : {};
    const hist = live ? this.history[key] ?? [] : [];
    const width = find(layout(), "sidebar")?.size?.px ?? Infinity;
    const graphs = width >= 260 ? "full" : width >= 200 ? "gauge" : "none";
    const stale = s.stale === true;
    const tone = (v, warn) => (v >= 90 ? t.ansi1 : v >= warn ? t.ansi3 : stale ? t.muted : t.foreground);
    const share = (v, warn) => div().flex_none().min_w(28).flex().justify_end()
      .text_color(stale ? t.muted : v == null ? t.dim : v >= 90 ? t.ansi1 : v >= warn ? t.ansi3 : t.foreground)
      .child(v == null ? "\u2014" : `${Math.round(v)}%`);
    const pad = HISTORY - hist.length;
    const spark = h_flex().flex_none().items_end().gap(BAR_GAP).h(GRAPH_H)
      .children(Array.from({ length: HISTORY }, (_, i) => {
        const v = i < pad ? null : hist[i - pad];
        return v == null
          ? div().w(BAR_W).h(2).rounded(1).bg(t.border)
          : div().w(BAR_W).h(Math.max(1, Math.round((v / 100) * GRAPH_H))).rounded(0.5).bg(tone(v, CPU_WARN));
      }));
    const meter = div().w(METER_W).h(6).flex_none().rounded_full().overflow_hidden().bg(t.input)
      .child(div().h_full().w(Math.round(((s.mem ?? 0) / 100) * METER_W)).rounded_full().bg(tone(s.mem ?? 0, MEM_WARN)));
    // Sheprd's compact density: a 3px gauge filling from the bottom.
    const gauge = (v, warn) => div().w(3).h(GRAPH_H).flex_none().flex().flex_col().justify_end()
      .rounded(1).overflow_hidden().bg(t.input)
      .child(div().w_full().h(Math.max(1, Math.round(((v ?? 0) / 100) * GRAPH_H))).bg(tone(v ?? 0, warn)));
    return h_flex().pl(21).gap(10).items_center().overflow_hidden().text_size(11).text_color(t.muted)
      .child(h_flex().flex_none().gap(5).items_center().child("CPU")
        .when(graphs === "full", el => el.child(spark))
        .when(graphs === "gauge", el => el.child(gauge(s.cpu, CPU_WARN)))
        .child(share(s.cpu, CPU_WARN)))
      .when(s.mem != null, el => el.child(h_flex().flex_none().gap(5).items_center().child("MEM")
        .when(graphs === "full", el => el.child(meter))
        .when(graphs === "gauge", el => el.child(gauge(s.mem, MEM_WARN)))
        .child(share(s.mem, MEM_WARN))));
  }

  rebuilt(machine) {
    return machine?.state === "unreachable" && /^a different core answers there \("[^"]+"\)$/.test(machine.why ?? "");
  }

  reconnect(machine, cx) {
    const name = machine.name;
    if (this.reconnecting[name]?.busy) return;
    const state = this.reconnecting[name] ??= { machine, removed: false };
    state.busy = true;
    state.error = null;
    localStorage.setItem("machines.reconnecting", JSON.stringify(this.reconnecting));
    cx.notify();
    cx.spawn(async cx => {
      try {
        const ask = async args => {
          const r = await hc([...args, "--json"]);
          if (r.code !== 0) {
            let error;
            try { error = JSON.parse(r.stdout || r.stderr).error?.message; } catch {}
            throw new Error(error || r.stderr || r.stdout || "Couldn't connect.");
          }
        };
        if (!state.removed) {
          await ask(["machine", "rm", name]);
          state.removed = true;
          localStorage.setItem("machines.reconnecting", JSON.stringify(this.reconnecting));
        }
        const args = ["machine", "add"];
        if (machine.via) args.push("--via", machine.target);
        else args.push(machine.target);
        args.push("--name", name);
        if (machine.session) args.push("--session", machine.session);
        if (machine.temporary) args.push("--temp");
        await ask(args);
        this.folded.delete(name);
        localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
        delete this.reconnecting[name];
      } catch (e) {
        state.error = String(e.message ?? e);
        state.busy = false;
      }
      localStorage.setItem("machines.reconnecting", JSON.stringify(this.reconnecting));
      this.refreshMachines(cx);
      cx.notify();
    });
  }

  // One look at a time, each place once however often it was asked for meanwhile.
  refreshGit(keys, cx) {
    for (const k of keys) this.pending.add(k);
    if (this.refreshing) return;
    this.refreshing = true;
    cx.spawn(async (cx) => {
      while (this.pending.size) {
        const keys = [...this.pending];
        this.pending.clear();
        for (const key of keys) await this.check(key, cx);
      }
      const used = new Set(Object.values(this.git).filter(Boolean).map((g) => JSON.parse(g.repo)).filter(([on]) => !on).map(([, repo]) => repo));
      for (const repo of this.watching) if (!used.has(repo)) this.watching.delete(repo);
      this.refreshing = false;
      cx.notify();
    });
  }

  // One place's git: branch, ahead/behind, its repo.
  async check(key, cx) {
    const [on, cwd] = JSON.parse(key);
    this.checked[key] = Date.now();
    this.unsure.delete(key);
    try {
      // No optional locks: a status that touched the index would wake the watch again.
      // Writes nothing under .git (index lock, fsmonitor cookie): watch() would wake on it.
      const r = await exec("git", ["--no-optional-locks", "-c", "core.fsmonitor=false", "status", "--porcelain=v2", "--branch"], { cwd, on });
      if (r.code !== 0) {
        // Only git's own "no" is remembered as no repo; anything else is asked again.
        if (!/not a git repository/i.test(r.stderr)) this.unsure.add(key);
        this.git[key] = null;
        return;
      }
      // The repo's own .git folder names it; a worktree's top differs from it.
      const top = await exec("git", ["rev-parse", "--show-toplevel"], { cwd, on });
      const common = await exec("git", ["rev-parse", "--path-format=absolute", "--git-common-dir"], { cwd, on });
      const repo = common.stdout.trim();
      const name = repo.endsWith("/.git") ? base(repo.slice(0, -5)) : base(repo).replace(/\.git$/, "");
      const info = { name, branch: null, upstream: null, ahead: 0, behind: 0, repo: JSON.stringify([on, repo]), linked: repo !== `${top.stdout.trim()}/.git` };
      for (const line of r.stdout.split("\n")) {
        if (line.startsWith("# branch.head ")) info.branch = line.slice(14);
        else if (line.startsWith("# branch.upstream ")) info.upstream = line.slice(18);
        else if (line.startsWith("# branch.ab ")) {
          const [a, b] = line.slice(12).split(" ");
          info.ahead = Math.abs(parseInt(a, 10)) || 0;
          info.behind = Math.abs(parseInt(b, 10)) || 0;
        }
      }
      this.git[key] = info;
      if (!on) this.watch(repo, cx);
    } catch {
      // Couldn't ask (the machine is away): keep what it showed, look again later.
      this.git[key] ??= null;
      this.unsure.add(key);
    }
  }

  watch(repo, cx) {
    if (this.watching.has(repo)) return;
    this.watching.add(repo);
    cx.spawn(async (cx) => {
      try {
        while (this.watching.has(repo)) {
          await watchFolder(repo);
          const mine = JSON.stringify([null, repo]);
          if (this.watching.has(repo)) this.refreshGit(Object.keys(this.git).filter((k) => this.git[k]?.repo === mine), cx);
        }
      } catch { this.watching.delete(repo); }
    });
  }

  menu(w) {
    // A popup is as tall as its items; height is only the most.
    openOverlay({ mod: "menu", kind: "popup", width: 200, height: 260, props: { tab: "space", target: { id: w.id } } });
  }

  orderingDue(now) {
    return this.ordering && now - this.ordering.at >= 1000
      && this.ordering.machines.every(name => machines().some(m => m.name === name && m.layout === "ready"));
  }

  // Spaces in order, each worktree space moved under its main checkout's.
  ordered() {
    const sp = spaces(), ps = panes();
    const ready = (w) => this.shown.has(w.id) || where(w, ps) in this.git || Date.now() - (this.born[w.id] ??= Date.now()) > 1500;
    for (const w of sp) if (!this.shown.has(w.id) && ready(w)) this.shown.add(w.id);
    const list = sp.map((w, i) => ({ w, i, g: this.git[where(w, ps)] ?? null }));
    const mains = new Set(list.filter((r) => r.g && !r.g.linked).map((r) => r.g.repo));
    const nested = (r) => r.g?.linked && mains.has(r.g.repo);
    const out = [];
    const placed = new Set(); // repos whose worktrees are listed (under the first of its spaces)
    for (const r of list) {
      if (nested(r)) continue;
      out.push({ ...r, tree: null });
      if (!r.g || r.g.linked || placed.has(r.g.repo)) continue;
      placed.add(r.g.repo);
      const kids = list.filter((k) => nested(k) && k.g.repo === r.g.repo);
      kids.forEach((k, n) => out.push({ ...k, tree: n === kids.length - 1 ? "└─" : "├─" }));
    }
    // Simulate the batch so later indexes include earlier moves. An attempted
    // write can lose a sync conflict: allow the echo to settle before retrying.
    const order = sp.map(w => w.id);
    const target = out.map(r => r.w.id);
    const key = JSON.stringify([order, target, machines()]);
    if (order.every((id, i) => id === target[i])) {
      this.ordering = null;
    } else if (this.ordering?.key !== key || this.orderingDue(Date.now())) {
      const moved = new Set();
      this.ordering = { key, at: Date.now(), machines: [] };
      for (let i = 0; i < out.length; i++) {
        const from = order.indexOf(out[i].w.id);
        if (from === i) continue;
        run("space.move", { id: out[i].w.id, index: i + 1 });
        moved.add(out[i].w.machine ?? null);
        order.splice(i, 0, order.splice(from, 1)[0]);
      }
      this.ordering.machines = [...moved];
    }
    return out.filter(r => this.shown.has(r.w.id));
  }

  // The rows, under a header per machine once one isn't this computer.
  grouped(t, collapsed) {
    const rows = this.ordered();
    const draw = (r) => (collapsed ? this.compact(r, t) : this.row(r, t));
    const remote = [...new Set([...rows.map(r => r.w.machine).filter(Boolean), ...this.machines.map(m => m.name), ...Object.keys(this.reconnecting)])].sort();
    const loading = m => {
      const layout = machines().find(k => k.name === m)?.layout;
      return layout === "loading" || (!layout && this.machines.some(k => k.name === m && k.state === "connected"))
        || spaces().some(s => (s.machine ?? null) === m && !this.shown.has(s.id));
    };
    const loadingRow = m => h_flex().id(`machine-loading-${m ?? "local"}`).h(28).flex_none().ml(collapsed ? 0 : 20).my(1).px(collapsed ? 0 : 8).items_center().when(collapsed, el => el.justify_center()).text_size(12).text_color(t.dim).child(collapsed ? "…" : "Loading…");
    if (!remote.length) return loading(null) && !rows.length ? [loadingRow(null)] : rows.map(draw);
    const machineNames = [null, ...remote];
    return machineNames.flatMap((m) => {
      const mine = rows.filter((r) => (r.w.machine ?? null) === m);
      const repair = this.reconnecting[m];
      const machine = this.machines.find(k => k.name === m) ?? repair?.machine;
      const connected = !m || machine?.state === "connected";
      const rebuilt = this.rebuilt(machine) || !!repair;
      const folded = this.folded.has(m);
      const icon = svg(`mods/workspace-chrome/${m ? "server" : "monitor"}.svg`).size(14).flex_none().text_color(t.muted);
      const badge = div().absolute().right(-3).bottom(-2).size(6).rounded(3).border_1().border_color(t.chrome).bg(connected ? t.ansi2 : t.muted);
      const toggle = (cx) => {
        folded ? this.folded.delete(m) : this.folded.add(m);
        localStorage.setItem("machines.folded", JSON.stringify([...this.folded]));
        cx.notify();
      };
      const row1 = h_flex().gap(7).items_center()
        .child(icon)
        .child(div().flex_1().truncate().child(m ?? "This computer"))
        .when(!connected && !rebuilt, el => el.child(div().flex_none().child((machine?.state ?? "asleep").replace(/_/g, " "))))
        .when(rebuilt, el => el.child(h_flex().flex_none().gap(3).items_center()
          .child(div().max_w(140).truncate().child(repair?.error || "rebuilt ·"))
          .child(div().id(`machine-connect-${m}`).text_color(repair?.error ? t.blocked : t.muted)
            .hover(s => s.text_color(t.foreground))
            .tooltip(repair?.error || "This machine was rebuilt or replaced. Click to connect to the new one.")
            .on_click((_e, cx) => { cx.stop_propagation(); this.reconnect(machine, cx); })
            .child(repair?.busy ? "Connecting…" : "Connect"))))
        .when(connected, el => el.child(div().id(`machine-add-${m ?? "local"}`).flex_none().px(4).rounded(4).hover(s => s.bg(t.hover).text_color(t.foreground))
          .on_click((_e, cx) => { cx.stop_propagation(); run("space.new", { machine: m ?? "" }); }).child("+")))
        .child(div().size(6).rounded(3).flex_none().bg(connected ? t.ansi2 : t.muted))
        .child(svg(`mods/workspace-chrome/chevron-${folded ? "right" : "down"}.svg`).size(11).flex_none());
      const head = collapsed
        ? v_flex().id(`machine-${m ?? "local"}`).flex_none().mt(4).w(RAIL_CELL).h(30).items_center().justify_center().rounded(4).bg(t.surface)
          .tooltip(m ? `${m} · ${connected ? "connected" : (machine?.state ?? "asleep").replace(/_/g, " ")}` : "This computer")
          .cursor_pointer().hover(s => s.bg(t.hover))
          .on_click((_e, cx) => toggle(cx))
          .child(div().relative().flex_none().child(icon).when(Boolean(m), el => el.child(badge)))
        : v_flex().id(`machine-${m ?? "local"}`).flex_none().mt(4).mb(1).pl(collapsed ? 0 : 18).pr(collapsed ? 0 : 10).pt(5).pb(6).bg(t.surface)
          .text_size(13.5).font_medium().text_color(connected ? t.foreground : t.muted)
          .cursor_pointer().hover(s => s.bg(t.hover))
          .on_click((_e, cx) => toggle(cx))
          .child(row1)
          .child(this.usage(m, t, connected));
      const empty = h_flex().id(`machine-new-${m ?? "local"}`).h(28).flex_none().ml(collapsed ? 0 : 20).my(1).px(collapsed ? 0 : 8).gap(7).items_center().rounded(4)
        .text_size(12).text_color(t.dim).hover(s => s.bg(t.hover).text_color(t.foreground))
        .on_click(() => run("space.new", { machine: m ?? "" }))
        .when(collapsed, el => el.w(RAIL_CELL).rounded(4).justify_center().tooltip(`New space on ${m ?? "this computer"}`)
          .child(h_flex().size(18).rounded(5).border_1().border_color(t.dim).items_center().justify_center()
            .child(svg("mods/workspace-chrome/plus.svg").size(10))))
        .when(!collapsed, el => el.child(svg("mods/workspace-chrome/plus.svg").size(12)).child("New space there"));
      if (!collapsed && rebuilt) return [head];
      const cell = collapsed ? railCell : (el) => el;
      return [cell(head), ...(folded ? [] : mine.length ? mine.map(draw) : [loading(m) ? loadingRow(m) : cell(empty)])];
    });
  }

  // Only what's unusual, after the name: "herdr \u00b7 spike \u21912 \u21931". The repo or
  // branch goes when the name already says it (a worktree is named after its branch),
  // and master/main go: nearly every space is on one.
  // The git tail: the space's branch and the remote it tracks (dev \u25b8 origin,
  // purple as a branch reads), ahead/behind counts, and the repo when it is not
  // what the space is called.
  gitTail(g, tree, name, t) {
    const same = (a) => a.toLowerCase() === name.toLowerCase();
    const repo = tree || same(g.name) ? "" : g.name;
    const remote = g.upstream?.includes("/") ? g.upstream.slice(0, g.upstream.indexOf("/")) : "";
    return h_flex()
      .flex_1()
      .min_w(0)
      .gap(5)
      .justify_end()
      .items_center()
      .text_size(11.5)
      .text_color(t.dim)
      .when(Boolean(repo), (el) => el.child(div().min_w(0).truncate().child(repo)))
      .when(Boolean(g.branch), (el) => el.child(h_flex().flex_none().min_w(0).gap(4).items_center()
        .child(svg("mods/workspace-chrome/git-branch.svg").size(11).flex_none().text_color(t.dim))
        .child(div().min_w(0).max_w(110).truncate().text_color(t.dim).child(g.branch))
        .when(Boolean(remote), branch => branch
          .child(div().flex_none().text_color(t.dim).child("\u25b8"))
          .child(div().min_w(0).max_w(80).truncate().text_color(t.dim).child(remote)))))
      .when(g.ahead > 0, (el) => el.child(div().flex_none().text_color(t.ansi2).child(`\u2191${g.ahead}`)))
      .when(g.behind > 0, (el) => el.child(div().flex_none().text_color(t.ansi1).child(`\u2193${g.behind}`)));
  }

  row({ w, i, g, tree }, t) {
    const on = w.active;
    const fromIndex = this.pressed === null ? -1 : spaces().findIndex(s => s.id === this.pressed);
    return v_flex()
      .relative()
      .id(`space-${w.id}`)
      .ml(20)
      .my(1)
      .px(8)
      .h(rowHeight({ tree }))
      .flex_none()
      .justify_center()
      .rounded(4)
      .when(on, (el) => el.bg(t.ansi5 + "33"))
      .when(!on, (el) => el.hover((s) => s.bg(t.hover)))
      .when(this.pressed === w.id && this.over !== w.id, (el) => el.opacity(0.5))
      .when(this.pressed !== null && this.over === w.id && this.pressed !== w.id, (el) => el.child(
        div().absolute().left(0).right(0).h(2).bg(t.accent)
          .when(fromIndex < i, line => line.bottom(0))
          .when(fromIndex > i, line => line.top(0)),
      ))
      .on_mouse_down("left", () => {
        this.pressed = w.id;
        this.over = w.id;
      })
      .on_mouse_move((_e, cx) => {
        const source = spaces().find(s => s.id === this.pressed);
        const over = source && (source.machine ?? null) === (w.machine ?? null) ? w.id : null;
        if (this.pressed !== null && this.over !== over) {
          this.over = over;
          cx.notify();
        }
      })
      .on_mouse_up("left", (_e, cx) => {
        const from = this.pressed;
        const over = this.over;
        this.pressed = null;
        this.over = null;
        if (from !== null && over === w.id && from !== w.id) {
          const index = spaces().findIndex(s => s.id === w.id);
          if (index !== -1) run("space.move", { id: from, index: index + 1 });
        } else if (from === w.id) run("space.select", { id: w.id });
        cx.notify();
      })
      .on_mouse_down("right", () => this.menu(w))
      .child(
        h_flex()
          .gap(9)
          .items_center()
          .child(div().w(14).flex_none().flex().justify_center().when(Boolean(w.status), el => el.child(mark(w.status, t))))
          .when(Boolean(tree), el => el.pl(22).child(svg("mods/workspace-chrome/branch.svg").size(13).text_color(t.dim)))
          .when(!tree, el => el.child(svg("mods/workspace-chrome/folder.svg").size(16).flex_none().text_color(t.dim)))
          .child(div().flex_shrink(0).max_w(150).truncate().text_color(t.foreground).child(w.name))
          .child(g ? this.gitTail(g, tree, w.name, t) : div().flex_1()),
      );
  }

  compact({ w, i }, t) {
    return railCell(h_flex()
      .id(`space-${w.id}`)
      .relative()
      .w(RAIL_CELL)
      .h(26)
      .rounded(4)
      .justify_center()
      .items_center()
      .when(w.active, (el) => el.bg(t.ansi5 + "33"))
      .when(!w.active, (el) => el.hover((s) => s.bg(t.hover)))
      .on_click(() => run("space.select", { id: w.id }))
      .child(div().text_color(w.active ? t.foreground : t.muted).child(String(i + 1)))
      .child(div().absolute().right(5).text_color(tone(t, w.status)).child(glyph(w.status))));
  }

  render() {
    const t = theme();
    const collapsed = narrow();
    const palette = ["ansi6", "ansi3", "ansi4", "ansi5", "ansi2", "ansi1"];
    const sp = spaces();
    const ids = new Set(sp.map(p => p.id));
    const kept = Object.fromEntries(Object.entries(shared("space.colors") ?? {}).filter(([id]) => ids.has(id)));
    let changed = Object.keys(kept).length !== Object.keys(shared("space.colors") ?? {}).length;
    for (const p of sp) {
      if (kept[p.id] || p.name === "~") continue;
      const uses = c => Object.values(kept).filter(v => v === c).length;
      kept[p.id] = palette.reduce((best, c) => uses(c) < uses(best) ? c : best);
      changed = true;
    }
    if (changed) setShared("space.colors", kept);
    return v_flex().size_full().min_h(0).bg(t.chrome).text_size(13)
      .child(h_flex().h(31).pl(16).pr(10).items_center().justify_between().text_size(11.5).text_color(t.dim)
        .when(collapsed, el => el.pl(0).pr(0).justify_center())
        .when(!collapsed, el => el.child("Spaces"))
        .child(div().id("space-new").size(26).flex_none().flex().items_center().justify_center().rounded(6).hover(s => s.bg(t.hover).text_color(t.foreground))
          .on_click(() => run("space.new")).child(svg("mods/workspace-chrome/plus.svg").size(14))))
      .child(v_flex().flex_1().min_h(0).pb(14).overflow_y_scrollbar().mode("always")
        .on_mouse_up("left", (_e, cx) => { this.pressed = null; cx.notify(); })
        .children(this.grouped(t, collapsed)));
  }
}
