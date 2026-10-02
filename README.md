# goal-tracker

![Goal Tracker panel](preview.png)

## Usage

- **Bar:** `Read ✓` means today's target is met, `●` means open. Left-click toggles the panel, middle-click logs +1.
- **Panel:** pick a goal to make it active; `− 1` / `+ 1` adjust today; finished goals show `· ended` — `Archive` them, `Restore` or `Delete` (two clicks) from the action bar or the `ARCHIVED` section.
- **Edit:** select a goal, then `Edit` (or `e`) — the form fills in with the goal's data. `Save Changes` writes back (log history is kept), `Cancel` or `Esc` backs out.
- **CLI:** `omarchy-shell io.github.adriansalvadorekomo.goal-tracker <method> [args]` — `log [n]`, `unlog [n]`, `select <id>`, `archive [id]`, `unarchive <id>`, `remove <id>`, `add <name> <target> <unit> <start> <end> <effort> <why>`, `edit <id> <name> <target> <unit> <start> <end> <effort> <why>` (dates `YYYY-MM-DD`, empty = sensible defaults; returns `""` on success, an error message otherwise).

| Key | Action | Context |
|---|---|---|
| `+` / `-` | Log / remove 1 for today | panel open, not typing |
| `j` / `k` or arrows | Move between goals | same |
| `g` / `G` | First / last goal | same |
| `Enter` / `Space` | Select goal (confirms an armed delete) | same |
| `e` | Edit selected goal | live goal shown |
| `a` | Archive / restore goal | goal shown |
| `d` or `x` | Arm delete (again to confirm) | goal shown |
| `Esc` | Cancel edit → disarm delete → close, in that order | always |
| `Tab` / `Shift+Tab` | Next / previous panel | always |

Keys pause while typing in a form field; letters are lowercase-only except `G`.

## Installation

From git (alias `install` works too):

```bash
omarchy plugin add https://github.com/adriansalvadorekomo/omarchy-goal-tracker.git --enable
```

Or manually — the repository root **is** the plugin, nothing to build:

```bash
mkdir -p ~/.config/omarchy/plugins/io.github.adriansalvadorekomo.goal-tracker
cp -r . ~/.config/omarchy/plugins/io.github.adriansalvadorekomo.goal-tracker/
omarchy plugin validate ~/.config/omarchy/plugins/io.github.adriansalvadorekomo.goal-tracker
omarchy plugin enable io.github.adriansalvadorekomo.goal-tracker
```

Then **restart the shell** (`omarchy restart shell`). The shell compiles and caches plugin QML: after any upgrade, validation passing is not enough — only a restart loads the new code. First run seeds one sample goal (`Read`, 20 pages); deleting every goal is respected and never re-seeded.

## Configuration

There is none. The manifest declares no settings; behavior is data-driven. Back up or hand-edit `goals.json` (`~/.local/state/omarchy/goal-tracker/goals.json`) while the shell runs — the watcher picks it up within a second. Keep it valid JSON; corrupt files load as empty rather than crashing.

## Architecture

![Architecture](docs/architecture.png)

Interactive version: [`docs/architecture.html`](docs/architecture.html) (spec: [`docs/architecture.json`](docs/architecture.json)).

The user acts on shell surfaces → `BarWidget.qml` owns the store → `Panel.qml` presents it → `Heatmap.qml` draws it → `Goals.js` computes it → `goals.json` keeps it.

| File | Role |
|---|---|
| `manifest.json` | Plugin identity: `io.github.adriansalvadorekomo.goal-tracker`, `kinds: ["bar-widget"]`, entry point `BarWidget.qml`. No settings schema, no services, no hooks. |
| `BarWidget.qml` | Store owner and bar slot. Loads/parses/persists `goals.json` via `FileView` (atomic writes, change watching, 300 ms save debounce), renders `name ✓/●`, routes IPC, hosts the panel through a `Loader`. |
| `Panel.qml` | Popup UI only — reads the store through `hostWidget`, never writes files directly. Goal selector, stepper, streak + pace line, heatmap instance, archive section, SMART form, keyboard map. |
| `Heatmap.qml` | Pure `Repeater` grid. Cell 10 px / 2 px gap / 2 px radius; level = `value / target` mapped to 0, <0.34, <0.67, <1.0, ≥1.0. |
| `Goals.js` | `.pragma library`: date keys (local-midnight, never UTC), `levelFor`, `streak`, `buildDays` (Sunday-aligned, future dates ignored), `sanitizeGoal` caps, `parseFile` (never throws), archive helpers. |
| `goals.json` | The only state: `{ activeId, goals[] }`, each goal `{ id, name, target, unit, startDate, endDate, log{date: value}, archived, archivedAt, effort, why }`. |

New goal fields go through `sanitizeGoal` + the `touchGoal` copy (both must list them); new panel sections are plain `Column` children; new IPC methods are one function in the `IpcHandler` block (typed `string` args only).

## Security

Local-only software, built to be boring:

- No network requests, no telemetry, no external processes except `mkdir -p` of its own state directory with fixed arguments.
- Every user-controlled string renders with `textFormat: Text.PlainText` — goal text cannot become executable markup.
- No `eval`, no URL opening, no shelling out with user data.
- `goals.json` parses inside try/catch; fields are re-validated with hard caps (names ≤ 60 chars, units ≤ 24, why ≤ 140, log values ≤ 1 000 000, ≤ 64 goals). Unknown goal ids are no-ops.
- All IPC arguments are typed `string`. `omarchy plugin add` only clones files — no `bin/`, services, or install hooks, so nothing executes until the widget is enabled.
- Found something? Open an issue with the QML snippet and the shell log line (`journalctl --user | grep goal-tracker`).

## Limitations

- One active goal is shown in the bar; the rest live one click away.
- Delete has no undo; the two-click arm and archiving are the safety net.
- Concurrent edits from two monitors converge on last-persisted-wins (300 ms debounce); simultaneous edits to the *same* day from two screens can drop one write.
- Days are local-timezone calendar days; the heatmap is fixed at 26 weeks.
- After upgrading the plugin, restart the shell — see Installation.

## Roadmap

Ideas, not promises: per-day adjustment by clicking heatmap cells; due-time reminders through Omarchy notifications; CSV import/export; non-daily (weekly) targets; optional second bar slot for another active goal.

## Contributing

- Keep the flat layout: the repo root is the plugin (`manifest.json` + sources at top level), exactly as `omarchy plugin add` expects it.
- Mirror changes in both places while developing: the repo is the source of truth, `~/.config/omarchy/plugins/io.github.adriansalvadorekomo.goal-tracker/` is the live copy.
- Lint with the **Qt6** checker — `/usr/lib/qt6/bin/qmllint`, never `/usr/bin/qmllint` (Qt5, silently passes Qt6 parse errors). Zero `syntax`/`Expected` diagnostics.
- `omarchy plugin validate <dir>` must exit 0.
- No new runtime dependencies. New goal fields must be added to **both** `sanitizeGoal` and the `touchGoal` copy or archiving/logging will wipe them. New user text must use `textFormat: Text.PlainText`.
- Prove UI changes visually: `omarchy-shell io.github.adriansalvadorekomo.goal-tracker open`, screenshot with `grim`, inspect at full resolution before claiming fixed.

## Development

```bash
omarchy plugin validate ./omarchy-goal-tracker
/usr/lib/qt6/bin/qmllint BarWidget.qml Panel.qml Heatmap.qml   # syntax only; qs.* import warnings are expected standalone
node -e 'eval(require("fs").readFileSync("Goals.js","utf8").replace(/^\.pragma library\s*/,"")); console.log(levelFor(14,20), streak({"2026-09-30":20},20,"2026-09-30"))'
omarchy-shell io.github.adriansalvadorekomo.goal-tracker log 2     # exercise the live store
```

Release checklist: Qt6 lint clean → `validate` exit 0 → sync to the live plugin dir → `omarchy restart shell` → no `goal-tracker.*(failed|error)` in `journalctl --user` → screenshot-verify the panel.

## License

MIT — see [LICENSE](LICENSE).
