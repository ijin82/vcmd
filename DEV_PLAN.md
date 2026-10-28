# Development Plan (`DEV_PLAN.md`): Vala Commander (`vcmd`)

This document tracks the original 7-stage architectural plan for **Vala Commander (`vcmd`)**, showing completed features, partially implemented components, and remaining roadmap tasks.

---

## Progress Overview

| Stage | Focus Area | Status | Key Highlights |
| :---: | :--- | :---: | :--- |
| **Stage 1** | Base UI Skeleton, Navigation & File Launching | **Completed (100%)** | Dual panes (`Gtk.Paned`), `Gtk.ColumnView`, `Gtk.GridView` (Brief), layout-agnostic hotkeys, MIME associations (`AppInfo.launch_default_for_uri`). |
| **Stage 2** | Tabs, Configuration & State Persistence | **Completed (100%)** | `Adw.TabBar` + `Adw.TabView`, `Ctrl+T`, `Ctrl+W`, `Ctrl+Shift+T` rename, `~/.config/vcmd/config` via `GLib.KeyFile`, Preferences dialog (`Ctrl+,`). |
| **Stage 3** | File Operations & Unified Error Handling (F5, F6, F7, F8) | **Completed (100%)** | Centralized `FileOperationService` (`GLib.IOError` handler), F7 mkdir, F8 recursive delete, F5 copy, F6 move/rename with conflict resolution, bottom F1-F10 bar. |
| **Stage 4** | File Viewing & Editing (F3, F4) | **Completed (100%)** | Configurable external editor/viewer execution (gnome-text-editor, gvim, code, terminal fallback). |
| **Stage 5** | Directory Bookmarks / Hotlist (`Ctrl+\`) | **Pending** | Midnight Commander-style directory bookmark popup, add/remove hotlist, persistent storage. |
| **Stage 6** | Search Engine (`Alt+F7`) | **Pending** | Background recursive directory search by filename mask and file contents. |
| **Stage 7** | Remote Connections & SFTP (`sftp://` / GVfs) | **Pending** | GVfs SFTP connection prompt and integration. |

---

## Detailed Status by Stage

### [x] Stage 1: Base UI Skeleton, Navigation & File Associations
- [x] Fast Makefile build system (`make`, `make run`, `install.sh lite`, `make install-lite`).
- [x] Dual-pane container with draggable divider (`Gtk.Paned`).
- [x] Full View (`Gtk.ColumnView`): Name, Type, Size, Date Modified with native header sorting.
- [x] Brief View (`Gtk.GridView`): Multi-column Midnight Commander style layout with configurable column width (`100–800px`) and live shortcuts (`Ctrl++` / `Ctrl+-`).
- [x] Instant view toggling with `Alt+T` and header bar button.
- [x] Pinned `..` (parent directory) always at top regardless of sort column or order.
- [x] Keyboard navigation:
  - `Tab` switching active panel with visual indicator.
  - `Enter` / Double Click: open directory or launch file via system default app (`AppInfo.launch_default_for_uri`).
  - Smart cursor positioning: entering a directory auto-selects the first file/folder after `..`; returning up via `..` or `Backspace` restores cursor directly onto the exited folder.
  - `Backspace` / `Alt+Up`: navigate up to `/`.
  - `Left Arrow` / `Right Arrow`: jump to top/start (`Home`) and bottom/end (`End`).
  - `Ctrl+Space`: asynchronous directory/file size calculation.
  - `Ctrl+H`: toggle hidden files visibility.
  - `Ctrl+L`: focus path entry bar.
  - Universal layout-agnostic shortcut handling (`KeyUtils.to_latin`) supporting Cyrillic/Russian keyboard layouts.
- [x] Bottom terminal command line bar (Midnight Commander style):
  - Type letters/digits to enter shell commands.
  - Context-aware execution in active panel's directory.
  - Configurable shell interpreter in Preferences (default `/bin/bash`, supports `zsh`, `fish`, custom paths).
  - Automatically loads user environment and startup configurations (`-l -i` for bash/zsh).
  - Clear error dialog if configured shell executable is missing or invalid.
  - Fast built-in `cd` navigation.
  - Command history browsing (`↑` / `↓`).
- [x] Toggle Window Header Bar (`Ctrl+Shift+H`): hide/show top header bar for maximal vertical screen real estate.
- [x] Quick directory filtering (`Ctrl+S`):
  - Case-insensitive substring matching (up to 20 chars).
  - List navigation (`↑`, `↓`, `Page Up`, `Page Down`) during filter typing.
  - Automatic focus on first matching item, `Enter` to open.
  - `Escape` resets filter and restores directory view.

---

### [x] Stage 2: Tabs & State Persistence
- [x] Multi-tab workspace per panel using `Adw.TabView` + `Adw.TabBar`:
  - `Ctrl+T`: open new tab in active panel.
  - `Ctrl+W`: close active tab with last tab protection.
  - `Ctrl+PageUp` / `Ctrl+PageDown` and `Ctrl+Tab` / `Ctrl+Shift+Tab`: switch tabs.
  - `Ctrl+Shift+T`: custom tab renaming dialog (max 15 characters).
- [x] Persistent XDG configuration (`~/.config/vcmd/config` via `GLib.KeyFile`):
  - Window dimensions and maximized state.
  - Paned divider position.
  - Active panel (`left` / `right`).
  - Open tab directory paths and custom titles for both panels.
  - Active tab indices for both panels.
  - View modes (Full vs Brief) and hidden file visibility.
  - Brief column width setting.
  - Custom panel font family and font size.
  - Safe fallback to `$HOME` if saved tab directories are unmounted or removed.
- [x] Libadwaita Preferences Window (`Ctrl+,`):
  - Path toolbar visibility toggle.
  - Brief view column width spinner.
  - Panel font picker and size spinner with live CSS update.

---

### [x] Stage 3: File Operations & Unified Error Handling (F5, F6, F7, F8)
- [x] Centralized `FileOperationService`:
  - Centralized parser and error dialog for all `GLib.IOError` types (`PERMISSION_DENIED`, `NOT_FOUND`, `EXISTS`, etc.).
  - Actionable prompt options: Overwrite, Skip, Cancel.
  - Non-blocking asynchronous execution (`GFile.copy_async`, `GFile.move_async`, `GFileEnumerator`).
- [x] Bottom Function Key Bar (F1..F10 buttons row at bottom of window with key number badges and action labels).
- [x] `F7`: Create Folder:
  - Input dialog for new folder name with Enter to confirm.
  - Error checking (already exists, invalid name, permission denied).
  - Automatically selects the new folder in the active panel upon creation.
- [x] `F8`: Delete Files / Directories:
  - Confirmation dialog with count/name of items to delete and destructive styling.
  - Asynchronous recursive deletion of directories.
- [x] `F5`: Copy Files / Directories:
  - Default target: opposite panel's active directory path.
  - Conflict resolution dialog (Overwrite / Cancel).
- [x] `F6`: Move / Rename Files:
  - Fast rename if moving within same directory/filesystem.
  - Cross-device copy + delete fallback.
  - Conflict resolution dialog.
- [x] `F10`: Clean application quit.

---

### [x] Stage 4: File Viewing & Editing (F3, F4)
- [x] `F3`: View File:
  - Launch external viewer command (default `gnome-text-editor`, `gvim`, `code`, or configured command with terminal fallback).
- [x] `F4`: Edit File:
  - Launch external editor command (default `gnome-text-editor`, `gvim`, `code`, or configured editor with terminal fallback).
- [x] Configuration options in `~/.config/vcmd/config` and Preferences Dialog for custom F3/F4 viewer/editor commands.

---

### [ ] Stage 5: Directory Bookmarks / Hotlist (`Ctrl+\`)
- [ ] Bookmarks dialog (`Ctrl+\`):
  - View list of saved directory bookmarks.
  - Add current directory to bookmarks (`Ctrl+A` or button).
  - Remove bookmark (`Delete` or button).
  - Jump to selected bookmark in active panel (`Enter`).
- [ ] Persist bookmarks in `~/.config/vcmd/config`.

---

### [ ] Stage 6: File Search Engine (`Alt+F7`)
- [ ] Search Dialog (`Alt+F7`):
  - Root directory selector (defaults to active panel directory).
  - Filename pattern / wildcard mask (`*.vala`, `*test*`).
  - Optional case sensitivity toggle.
  - Optional search within file contents (text grep).
- [ ] Background non-blocking scanning thread (`GLib.ThreadPool`).
- [ ] Results list with instant jump/navigate to selected search result in active pane.

---

### [ ] Stage 7: Remote Connections & SFTP (`sftp://` / GVfs)
- [ ] Connect to Server dialog:
  - Fields for Protocol (`sftp://`), Server, Port, User, Directory.
- [ ] Mount remote filesystem via `GLib.File.new_for_uri` and `GMountOperation`.
- [ ] Seamless file operations (navigation, F5, F6, F7, F8) across remote and local panels.
