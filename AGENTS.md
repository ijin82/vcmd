# Project Rules & Guidelines for AI Agents

## Language Requirement
- **All code, comments, documentation, README files, tooltips, commit messages, and user-facing strings must be exclusively in English.**
- Never write Russian or other non-English languages in code comments, docstrings, UI labels, or documentation.

## Project Overview
- **Name:** Vala Commander (`vcmd`)
- **Purpose:** A lightweight, responsive, modern dual-pane file manager for Linux, blending the keyboard-driven speed of Midnight Commander with modern GTK4/Libadwaita GUI aesthetics and Nautilus-grade system integration.

## Tech Stack & Architecture
- **Language:** Vala (compiled directly via `valac` with GCC)
- **UI Toolkit:** GTK4 + Libadwaita (`libadwaita-1`)
- **Core Libraries:** GLib 2.0, GIO 2.0 (`gio-2.0`, `gio-unix-2.0`)
- **Build System:** `Makefile` (fast direct compilation, sub-second incremental builds)
- **Configuration Format:** XDG standard `.ini` configuration using `GLib.KeyFile` located at `~/.config/vcmd/config`

## Core Architecture Principles
1. **Non-blocking Asynchronous I/O:**
   - All disk scanning, file copies, moves, and deletions must use asynchronous GIO APIs (`GFile.copy_async`, `GFile.move_async`, `GFileEnumerator`, or background `GLib.ThreadPool`).
   - The GTK main loop must never be blocked by synchronous file system operations.
2. **Unified Error Handling:**
   - File operations must never have scattered, duplicate error dialog implementations.
   - All file operation errors must be routed through a centralized service/handler that parses `GLib.IOError` types (e.g., `PERMISSION_DENIED`, `NOT_FOUND`, `EXISTS`, etc.) and presents consistent user feedback or actionable resolutions (Retry, Skip, Overwrite).
3. **Native Desktop Integration:**
   - Standard FreeDesktop / XDG MIME associations must be used to open files via `GLib.AppInfo.launch_default_for_uri()` or `Gtk.FileLauncher`.
   - GVfs URI schemes (e.g., `sftp://`, `trash://`) must be treated first-class using `GLib.File.new_for_uri()`.
4. **Keyboard-First & Dual-Pane Navigation:**
   - Strict adherence to Midnight Commander-compatible shortcuts where applicable (`Tab` to switch active pane, `F3` View, `F4` Edit, `F5` Copy, `F6` Move, `F7` New Folder, `F8` Delete, `Ctrl+\` Directory Hotlist/Bookmarks, `Alt+F7` File Search).
   - Tab management in each pane: `Ctrl+T` to open a tab, `Ctrl+W` to close the active tab.

## Development & Code Conventions
- Follow GNOME Human Interface Guidelines (HIG).
- Maintain clean separation between Models (file metadata, configuration), Views (file list `Gtk.ColumnView`, tab views), and Controllers/Services (file operations, search engine).
- Ensure all event controllers, signal handlers, and GIO cancellables (`GLib.Cancellable`) are properly disconnected and freed on destruction.
- Keep binaries lightweight with zero unnecessary runtime dependencies.

## Workflow & Testing
- **Local Build & Test:** Run `make` to compile and `make run` to test changes.
- **Local Installation:** Always run `./install.sh lite` (or `make install-lite`) upon completing changes / after each build so the user can immediately test the live application without redundant rebuilds.
- **Git Restrictions:** Do not run `git commit` or `git push` autonomously; all git commits and repository pushes are managed directly by the user.
