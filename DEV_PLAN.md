# Development Plan (`DEV_PLAN.md`): Vala Commander (`vcmd`)

This document tracks the 7-stage architectural plan for **Vala Commander (`vcmd`)**, showing completed features, recent enhancements, and remaining roadmap tasks.

---

## Progress Overview

| Stage | Focus Area | Status | Key Highlights |
| :---: | :--- | :---: | :--- |
| **Stage 1** | Base UI Skeleton, Navigation & File Launching | **Completed (100%)** | Dual panes (`Gtk.Paned`), `Gtk.ColumnView`, `Gtk.GridView` (Brief), layout-agnostic hotkeys, MIME associations (`AppInfo.launch_default_for_uri`). |
| **Stage 2** | Tabs, Configuration & State Persistence | **Completed (100%)** | `Adw.TabBar` + `Adw.TabView`, `Ctrl+T`, `Ctrl+W`, `Ctrl+Shift+T` rename, `~/.config/vcmd/config` via `GLib.KeyFile`, Preferences dialog (`Ctrl+,`). |
| **Stage 3** | File Operations & Unified Error Handling (F5, F6, F7, F8) | **Completed (100%)** | Centralized `FileOperationService` (`GLib.IOError` handler), F7 mkdir, F8 recursive delete, F5 copy, F6 move/rename with conflict resolution, bottom F1-F10 bar. |
| **Stage 4** | File Viewing & Editing (F3, F4) | **Completed (100%)** | Configurable external editor/viewer execution (gnome-text-editor, gvim, code, terminal fallback). |
| **Stage 5** | Directory Bookmarks / Hotlist (`Ctrl+\`) & Modern Dialogs | **Completed (100%)** | Midnight Commander-style directory bookmark popup, modern `Adw.Dialog` migration, customizable dialog dimensions. |
| **Stage 6** | Search Engine (`Alt+F7`) | **Pending** | Background recursive directory search by filename mask and file contents. |
| **Stage 7** | Remote Connections & SFTP (`sftp://` / GVfs) | **Pending** | GVfs SFTP connection prompt and integration. |

---

## Detailed Status by Stage

### [x] Stage 1: Base UI Skeleton, Navigation & File Associations
- [x] Fast Makefile build system (`make`, `make run`, `install.sh lite`, `make install-lite`).
- [x] Dual-pane container with draggable divider (`Gtk.Paned`).
- [x] Full / Detailed View (`Gtk.ColumnView`): Name, Type, Size, Date Modified with native header sorting.
- [x] Brief View (`Gtk.GridView`): Multi-column Midnight Commander style layout with configurable column width (`100–800px`) and live shortcuts (`Ctrl++` / `Ctrl+-`).
- [x] Super Detailed View: Single-pane maximized view with deep metadata display and enhanced layout.
- [x] Triple view toggling with `Alt+T` and header bar button.
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
- [x] Multi-selection & Item Tagging:
  - `Insert` / `KP_Insert`: tag current file/folder and advance cursor down.
  - `+` / `KP_Add`: select files by wildcard mask (e.g., `*.png`, `*test*`).
  - Double `Escape`: clear all tags/selections in active panel.
  - `Alt+I` / `Esc` > `i`: sync opposite panel to active directory.
- [x] Bottom Command Line Bar (Midnight Commander style):
  - Type letters/digits to enter shell commands when terminal drawer is closed.
  - Pressing `Enter` opens the terminal drawer and executes the command directly in VTE terminal.
  - Built-in `cd` navigation without launching a shell.
  - Command history browsing (`↑` / `↓`).
  - `Ctrl+Enter`: insert focused file/folder name (shell-escaped) into command entry.
- [x] Embedded Interactive VTE Terminal Drawer (`Ctrl+O` / `Ctrl+~`):
  - Native GTK4 `Vte.Terminal` (`libvte-2.91-gtk4`) running in bottom drawer with draggable vertical paned splitter.
  - True PTY terminal session with full job control and terminal process group support.
  - Full TUI support: interactive tools like `top`, `htop`, `mc`, `nano`, `vim`, `less` run natively.
  - Full shell environment: loads `~/.bashrc`, aliases (`ll`, `l`, etc.), custom shell functions, and environment variables.
  - Hides command entry bar when open; focus and cursor locked into terminal until closed.
  - Terminal shortcuts: `Ctrl+Shift+C` (copy), `Ctrl+Shift+V` (paste), `Ctrl+O` / `Ctrl+~` (close).
  - Directory synchronization with active tab on launch and drawer open (with active process protection).
  - Header controls: Sync Directory (`folder-symbolic`), Clear (`edit-clear-symbolic`), Close.
- [x] Complete Sound Silencing Application-Wide:
  - `gtk_error_bell = false`: eliminates system error beeps.
  - `gtk_enable_event_sounds = false`: eliminates sound theme event sounds.
  - `vte_terminal.set_audible_bell(false)`: silences terminal bell (`\a`) on completion/backspace.
- [x] Toggle Window Header Bar (`Ctrl+Shift+H`): hide/show top header bar for maximal vertical screen real estate.
- [x] Quick directory filtering (`Ctrl+S`):
  - Case-insensitive substring matching (up to 20 chars).
  - List navigation (`↑`, `↓`, `Page Up`, `Page Down`) during filter typing.
  - Automatic focus on first matching item, `Enter` to open.
  - `Escape` resets filter and restores directory view.

---

## Detailed Status by Stage

### [x] Stage 2: Tabs & State Persistence
- [x] Multi-tab workspace per panel using `Adw.TabView` + `Adw.TabBar`:
  - `Ctrl+T`: open new tab in active panel.
  - `Ctrl+W`: close active tab with last tab protection.
  - `Ctrl+PageUp` / `Ctrl+PageDown` and `Ctrl+Tab` / `Ctrl+Shift+Tab`: switch tabs.
  - `Ctrl+Shift+T`: custom tab renaming dialog (max 15 characters).
- [x] Persistent XDG configuration (`~/.config/vcmd/config` via `GLib.KeyFile`):
  - Window dimensions and maximized state.
  - Paned divider position and vertical console drawer height.
  - Active panel (`left` / `right`).
  - Open tab directory paths and custom titles for both panels.
  - Active tab indices for both panels.
  - View modes (Brief, Detailed, Super Detailed) and hidden file visibility.
  - Brief column width setting.
  - Custom panel font family and font size.
  - Dialog sizes (Bookmarks, Shortcuts, Open With).
  - Safe fallback to `$HOME` if saved tab directories are unmounted or removed.
- [x] Libadwaita Preferences Window (`Ctrl+,`):
  - Path toolbar visibility toggle.
  - Function key bar visibility toggle.
  - Brief view column width spinner.
  - Panel font picker and size spinner with live CSS update.
  - Dialog sizes section (Bookmarks, Shortcuts, Open With dimensions).
  - Shell interpreter and terminal history scrollback limit.

---

## Detailed Status by Stage

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
  - Support for multi-selection / tagged items.
  - Asynchronous recursive deletion of directories.
- [x] `F5`: Copy Files / Directories:
  - Default target: opposite panel's active directory path.
  - Conflict resolution dialog (Overwrite / Cancel).
  - Support for multi-selection / tagged items.
- [x] `F6`: Move / Rename Files:
  - Fast rename if moving within same directory/filesystem.
  - Cross-device copy + delete fallback.
  - Conflict resolution dialog.
  - Support for multi-selection / tagged items.
- [x] `F10`: Clean application quit.

---

## Detailed Status by Stage

### [x] Stage 4: File Viewing & Editing (F3, F4) & Open With
- [x] `F3`: View File:
  - Launch external viewer command (default `gnome-text-editor`, `gvim`, `code`, or configured command with terminal fallback).
- [x] `F4`: Edit File:
  - Launch external editor command (default `gnome-text-editor`, `gvim`, `code`, or configured editor with terminal fallback).
- [x] `Ctrl+Shift+O`: Open With Dialog:
  - Search and launch any installed desktop application with live filtering.
- [x] Configuration options in `~/.config/vcmd/config` and Preferences Dialog for custom F3/F4 viewer/editor commands.

---

## Detailed Status by Stage

### [x] Stage 5: Directory Bookmarks / Hotlist (`Ctrl+\`) & Modern Dialogs
- [x] Bookmarks dialog (`Ctrl+\`):
  - Migrated to modern `Adw.Dialog` components.
  - View list of saved directory bookmarks with titles, subtitles (full path/URI), and folder icons.
  - Add current directory to bookmarks (`Ctrl+A` or button) with custom title.
  - Remove bookmark (`Delete` key or row delete button).
  - Jump to selected bookmark in active panel (`Enter` or double click).
  - Support for local paths and remote/virtual GVfs URIs.
- [x] Persist bookmarks in `~/.config/vcmd/config` under `[Bookmarks]`.
- [x] Customizable dialog sizes via Preferences.

---

## Detailed Status by Stage

### [ ] Stage 6: File Search Engine (`Alt+F7`)
- [ ] Search Dialog (`Alt+F7`):
  - Root directory selector (defaults to active panel directory).
  - Filename pattern / wildcard mask (`*.vala`, `*test*`).
  - Optional case sensitivity toggle.
  - Optional search within file contents (text grep).
- [ ] Background non-blocking scanning thread (`GLib.ThreadPool`).
- [ ] Results list with instant jump/navigate to selected search result in active pane.

---

## Detailed Status by Stage

### [ ] Stage 7: Remote Connections & SFTP (`sftp://` / GVfs)
- [ ] Connect to Server dialog:
  - Fields for Protocol (`sftp://`), Server, Port, User, Directory.
- [ ] Mount remote filesystem via `GLib.File.new_for_uri` and `GMountOperation`.
- [ ] Seamless file operations (navigation, F5, F6, F7, F8) across remote and local panels.
