# TryStation

> A retro visual workbench for [Tobi's `try`](https://github.com/tobi/try), turning ephemeral coding experiments into searchable, inspectable tries.

TryStation is an Omarchy Quattro plugin for the experiment directories already managed by `try`. It adds a themed desktop window and optional bar widget without replacing the CLI or introducing a second project format.

## Features

- Compact Omarchy-style summary popout for recent and pinned tries
- Fuzzy search across names, groups, notes, languages, and Git branches
- Numbered `1`–`5` shortcuts that open visible results in a terminal
- Full retro library window for deeper organization
- `TRY` bar widget with left-click, right-click, and middle-click actions
- Browse and search every try by name, group, language, Git branch, or note
- Inspect Git status, worktree state, stack, README summary, and activity time
- Create date-prefixed tries compatible with the CLI and open them immediately in the default editor
- Reuse existing groups through autocomplete or type a new group to create it
- Event-based autosave for groups and notes, plus instant pin/unpin, without changing the try directory layout
- Open a try in the Omarchy editor, terminal, or file manager
- Copy its path or safely move it to the desktop trash
- Follow graduated symlinks created by `try`
- Refresh automatically while the window is open

The filesystem remains the source of truth. TryStation scans the immediate directories under the configured try path, just as `try` does. Optional labels are kept separately in `$XDG_STATE_HOME/trystation/metadata.json` and keyed by filesystem identity, so groups survive CLI renames.

## Requirements

TryStation targets Omarchy 4 / Quattro and uses tools included by Omarchy:

- `try`
- Python 3
- Git
- `gio`
- `xdg-terminal-exec`
- `omarchy-launch-editor`
- Nautilus and `wl-copy`

It does not use sudo, install hooks, background services, network access, or a second Quickshell process.

## Install

```sh
omarchy plugin add https://github.com/guillechuma/trystation.git --enable
```

The plugin is added to the left section of the bar:

- **Left-click** opens the compact recent-tries summary.
- **Right-click** opens the full TryStation library.
- **Middle-click** opens the quick-create form.

From the summary, select a try to open it in the editor, press `T` for a terminal, or choose **Open Library** for the full interface.

You can also summon it directly:

```sh
omarchy-shell shell summon io.github.guillechuma.trystation '{}'
```

## Configure

Omarchy configures `try` at `~/Work/tries` by default. Change the path through the bar settings UI or directly in the widget's `shell.json` entry:

```json
{
  "id": "io.github.guillechuma.trystation",
  "triesPath": "~/Work/tries"
}
```

When summoned without the bar widget, TryStation defaults to `~/Work/tries`. A caller may provide another path:

```sh
omarchy-shell shell summon io.github.guillechuma.trystation '{"path":"~/src/tries"}'
```

## Keyboard

### Summary popout

| Key | Action |
| --- | --- |
| `1`–`5` | Open the corresponding visible try in a terminal |
| `/` | Focus fuzzy search |
| `↑` / `↓`, `j` / `k` | Select a recent or matching try |
| `Enter` | Open the selected try in the default editor |
| `T` | Open the selected try in a terminal |
| `N` | Create a try |
| `O` | Open the full library |
| `R` | Refresh |
| `Esc` | Close |

### Full library

| Key | Action |
| --- | --- |
| `↑` / `↓`, `j` / `k` | Select a try |
| `Enter` | Open the selected try in the default editor |
| `/` | Focus search |
| `Ctrl+N` | Create a try |
| `Ctrl+R` | Refresh |
| `Esc` | Clear/leave the active input, then close |

## Safety and privacy

- All inspection is local.
- Git commands are read-only and have a two-second timeout.
- Delete uses the desktop trash, not `rm -rf`.
- TryStation only trashes an immediate child of the configured try directory.
- Graduated symlinks are unlinked; their destination project is never deleted.
- Notes and groups remain local and are never written into repositories.

## Development

```sh
omarchy plugin validate .
qmllint -I "$OMARCHY_PATH/shell" BarWidget.qml SummaryPanel.qml TryStation.qml
python3 -m unittest discover -s tests -v
```

For live development, install the repository as a local path or copy it under `~/.config/omarchy/plugins/io.github.guillechuma.trystation/`, enable it, and run:

```sh
omarchy-shell shell rescanPlugins
omarchy-shell shell summon io.github.guillechuma.trystation '{}'
```

Files under the user plugin directory hot-reload on save.

## Remove

```sh
omarchy plugin remove io.github.guillechuma.trystation
```

Removing the plugin does not remove tries or local labels. To remove labels as well:

```sh
rm -rf "${XDG_STATE_HOME:-$HOME/.local/state}/trystation"
```

## License

MIT
