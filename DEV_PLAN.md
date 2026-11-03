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
| **Stage 6** | Search Engine (`Alt+F7`) | **Completed (100%)** | Async recursive search by name mask and file contents. Results open in a Super Detailed tab. The last query is stored in config; the start path comes from the active tab. |
| **Stage 7** | Remote Connections & SFTP (`sftp://` / GVfs) | **Completed (100%)** | F2 connect dialog for SFTP, FTP, and SMB. Bookmarks store the URI without a password. Drives & Locations menu (`Ctrl+F1`). |
| **Stage 8** | Trash Management & File Recovery (`trash:///`) | **Completed (100%)** | Contextual Trash banner, Empty Trash confirmation, Restore Selected files (`trash::orig-path`), permanent delete (F8). |
| **Stage 9** | Non-Blocking Background Operations & Minimized Progress | **Planned (Complexity: Moderate)** | Minimizable copy/move dialogs into a toolbar progress indicator button/popover, allowing non-blocking workflow during heavy transfers. |
| **Stage 10** | Icon / Thumbnail Grid View & Live Background Thumbnail Engine | **Planned (Complexity: High)** | Single/dual-pane image & video thumbnail grid view (30–300px), Ctrl++/Ctrl+-/scroll zoom, atomic background worker pool (`~/.config/vcmd/thumbnails/`), crash recovery, streaming live updates without UI jumps. |

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
  - Custom panel and terminal font family, size, weight, and style.
  - Dialog sizes (Bookmarks, Shortcuts, Open With).
  - Safe fallback to `$HOME` if saved tab directories are unmounted or removed.
- [x] Libadwaita Preferences Window (`Ctrl+,`):
  - Path toolbar visibility toggle.
  - Function key bar visibility toggle.
  - Brief view column width spinner.
  - Panel and terminal font pickers (family, size, weight, style) with live update.
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

### [x] Stage 6: File Search Engine (`Alt+F7`)
- [x] Search dialog (`Alt+F7`), including while the terminal drawer has focus:
  - Start directory, prefilled from the active tab. A folder picker is available.
  - Filename pattern (`*` and `?`). A plain word matches anywhere in the name.
  - Optional text search inside files. Directories match by name only.
  - Case sensitivity and hidden-file toggles.
  - Live progress, Stop / Escape to cancel, and a stay-open dialog when nothing matches.
  - Name, content, case, and hidden-file options are saved under `[Search]` in `~/.config/vcmd/config` and restored on the next open. The start path always comes from the active tab.
- [x] Non-blocking scan via `GFileEnumerator` async APIs (`FileSearchEngine`). Symlink directories are not followed. Unreadable directories are skipped. Binary files and files larger than 32 MB are skipped for content search. Results stop at 5000 matches.
- [x] Results open as a new **Search** tab in Super Detailed view. The name column shows the path relative to the search root. The cursor lands on the first match.
  - `..`, Backspace, or Alt+Up leaves the results and opens the search root.
  - Enter on a directory opens that directory. Enter, F3, and F4 open a file without replacing the results list.
  - Closing the viewer or editor does not reload the search tab.

---

## Detailed Status by Stage

### [x] Stage 7: Remote Connections (`F2`, GVfs) & Connected Devices
- [x] Connect to Server dialog (`F2`):
  - Protocol: SSH (`ssh://`), SFTP, FTP, or SMB. SSH uses the GVfs SFTP backend and the same key or password prompt.
  - Host, optional port, user, and directory.
  - Optional bookmark name. Remember stores the URI in the existing bookmark list, without a password.
- [x] Mount through `GFile.mount_enclosing_volume` and `Gtk.MountOperation`. The system password dialog is used. An already loaded SSH key is picked up by GVfs for SFTP.
- [x] Opening a bookmark or typing a `sftp://`, `ftp://`, or `smb://` path mounts before the directory is listed.
- [x] Navigation and F5, F6, F7, F8 use the same GIO operations on the mounted location.
- [x] Connected Devices & Remote Mounts (`Ctrl+F1` Left Panel / `Ctrl+F2` Right Panel):
  - Centralized `VolumeService` using `GLib.VolumeMonitor` to detect USB drives, external disks, optical media, unmounted partitions, and network mounts (WebDAV, SFTP, SMB, GVfs).
  - Drives button (`drive-harddisk-symbolic`) in each panel header with an `Adw` styled `DrivesPopover`.
  - Sections for Devices & Drives (with safe eject `⏏`), Network & Remote (with disconnect `⏏`), Standard Places (Home, Root, Trash), and Quick Action to Connect to Server (`F2`).
  - Full keyboard navigation with arrows, Enter, Delete/E to eject, and Escape to dismiss.
  - Automatic fallback to `$HOME` if an open directory is unmounted or safely removed.

---

## Detailed Status by Stage

### [x] Stage 8: Trash Management & File Recovery (`trash:///`) [Complexity: Low]
- [x] Contextual Trash Banner:
  - When the active tab enters `trash:///`, show an action banner directly above the file list:
    - Display trash status: e.g. "Trash contains N items".
    - `Empty Trash` button with destructive styling (`destructive-action`) and confirmation dialog.
    - `Restore Selected` button (`suggested-action`), enabled when one or more files are selected or tagged.
- [x] Trash File Operations:
  - Reading `trash::orig-path` and `trash::deletion-date` from GIO attributes (`G_FILE_ATTRIBUTE_TRASH_ORIG_PATH`, `G_FILE_ATTRIBUTE_TRASH_DELETION_DATE`).
  - Restore Action: Moves the selected file(s) from `trash:///...` back to their original destination path, recreating any parent directories that were deleted in the meantime.
  - Permanent Delete (`F8` in `trash:///`): Executes permanent deletion (`g_file_delete_async`) instead of re-trashing, with explicit confirmation dialog ("Permanently delete N selected items?").
  - Double-click / Enter on trashed item: Shows dialog offering to either "Restore File" or "Cancel".
- [x] Columns in Detailed View for `trash:///`:
  - Show "Original Path" and "Date Deleted" columns when browsing `trash:///`.

---

## Detailed Status by Stage

### [x] Stage 9: Non-Blocking Background Operations & Minimized Progress [Complexity: Moderate]
- [x] Minimizable Progress Dialog:
  - In `OperationProgressDialog`, add a "Run in Background" / "Minimize" button (`window-minimize-symbolic` and dialog button).
  - Clicking Minimize closes the modal `Adw.Dialog` without interrupting or cancelling the active copy/move operations.
- [x] Toolbar Progress Indicator Button & Popover:
  - When background operations are active, an operation indicator button appears in the main window header bar (e.g. `folder-download-symbolic` + "45%").
  - Clicking the indicator button opens a Popover listing all active background tasks:
    - Current operation type (Copy / Move / Sync / Trash / Delete / Symlink).
    - Current source and target item names.
    - Mini progress bar and transfer speed (e.g. "34.5 MB/s • 1.2 GB / 2.8 GB").
    - Action buttons: "Restore" button (`view-fullscreen-symbolic`) and "Cancel" button (`process-stop-symbolic`).
  - Automatically hides the indicator button and presents an `Adw.Toast` notification when all background transfers finish.
- [x] Conflict, Error Handling & Close Protection while Minimized:
  - If an I/O error occurs while minimized, present the error alert dialog directly on the main window.
  - Safe application quit prompt protects against accidental exit while background operations are copying.


---

## Detailed Status by Stage

### [ ] Stage 10: Icon / Thumbnail Grid View & Live Background Thumbnail Engine [Complexity: High]
- [ ] Thumbnail Grid View Mode (`Gtk.GridView`):
  - New view mode alongside Detailed, Brief, and Super Detailed.
  - Vertical layout tile: large square image/preview area (30–300px) above, item name below (centered, wrapped).
  - Zoom scaling:
    - Step size: 30px (steps: 30, 60, 90, 120, 150, 180, 210, 240, 270, 300px). Default: 120px.
    - Zoom shortcuts: `Ctrl++` (zoom in), `Ctrl+-` (zoom out), `Ctrl+0` (reset to default 120px), and `Ctrl + Mouse Scroll`.
    - Persist zoom size and view mode per-tab or globally in `~/.config/vcmd/config`.
- [ ] Thumbnail Engine (`ThumbnailService`):
  - Cache location: `~/.config/vcmd/thumbnails/` (or configurable XDG cache).
  - Cache file format & naming: PNG/JPEG thumbnails scaled to max 300x300, named using hash of `canonical_path + mtime + file_size`.
  - Atomic Generation & Crash Recovery:
    - Worker generates thumbnails to temporary files: `.tmp.<hash>`.
    - On success, atomically renames `.tmp.<hash>` to `<hash>.png`.
    - On application startup or directory scan, any dangling `.tmp.*` files are safely detected as interrupted work and cleaned up or re-queued.
  - Supported Formats:
    - Native image formats: JPG, JPEG, PNG, GIF, SVG.
    - Fallback: Non-image files show standard system MIME / icon at the current tile size.
    - External tool support: Preference toggle to enable ImageMagick (`magick` / `convert`) and video thumbnailing (`ffmpegthumbnailer` / `ffmpeg`) when installed on the system.
    - Suppress non-critical thumbnail generation errors without interrupting directory browsing.
- [ ] Non-Blocking Live Streaming ("Дотекание"):
  - Generation occurs in a background worker pool (`GLib.ThreadPool`).
  - As each thumbnail is finished, dispatches an idle signal to the GTK main loop (`GLib.Idle.add`).
  - Binds the newly loaded texture/paintable directly to the `FileItem` without reloading or re-sorting the `GListStore`.
  - Zero scroll jumping, zero UI jitter, smooth streaming of thumbnails directly into the active view as they become available.

