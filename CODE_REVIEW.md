# Code Review: Vala Commander (`vcmd`) `v0.10.8`

## Scope and Method

This review covers the 33 Vala sources under `src/` (about 22,300 lines), plus
`Makefile`, `install.sh`, `package-release.sh`, and the documentation.

Work was split into five passes:

1. Clean build and compiler-warning triage (`make`, `./vcmd --version`).
2. Static pattern scans: synchronous I/O, process spawning, cancellables,
   signal connections, error handling, TODO markers, string truncation.
3. Core service review: file operations, drive queue, archive VFS, remote
   mounts, configuration, logging, thumbnails.
4. UI/controller review: `window.vala`, `file_panel.vala`,
   `file_panel_page.vala`, dialogs, terminal handling.
5. Manual verification of each candidate finding against the source.

No functional GUI tests were run in this session. The findings below are
static-analysis results, verified against the current source; several of them
should still be reproduced with an integration test before fixing.

The project builds successfully with Vala 0.56.18 and the locally installed
GTK 4.20 / libadwaita 1.8.3 / VTE 0.80.3 stack. The build emits a substantial
number of warnings; the relevant ones are summarized at the end of this
document.

## Severity Legend

- **P0** — data loss or security issue, or a crash/hang reachable by normal use.
- **P1** — serious correctness or robustness bug, likely to be hit by users.
- **P2** — meaningful improvement: performance, UX, maintainability, or a
  lower-probability correctness issue.
- **P3** — cleanup, documentation, or style.

---

## P0 Findings

### F-01 — Rename accepts `.` and `..`, then recursively deletes the target

**Locations:** `src/window.vala:5250-5295`,
`src/file_operation_service.vala:460-480`

`prompt_execute_rename()` only rejects names containing `/`. Names such as `.`
and `..` are accepted. The destination is built with
`parent_dir.get_child(new_name)`, so `..` resolves to the parent directory and
`.` resolves to the directory itself.

If that destination exists, the overwrite confirmation is shown. On confirmation
`do_rename_file()` calls `move_file_or_dir()`, which performs:

```vala
try {
    yield dest.delete_async(...);
} catch (Error e) {
    yield delete_recursive(dest, cancellable);
}
```

A non-empty directory fails `delete_async()` and is then recursively deleted.
Renaming a file to `..` therefore attempts to recursively delete the parent
directory; `.` attempts to delete the current directory. A privileged run could
reach far beyond the selected folder.

**Fix:**

- Reject empty, `.`, `..`, absolute names, and any name whose normalized path
  is the source itself or one of its ancestors.
- Compare canonical paths, not only the raw string.
- Never recursively delete a rename target. Fail the rename, or offer an
  explicit, separately worded “replace non-empty folder” operation.

### F-02 — Copy or move into the source's own descendant causes unbounded recursion

**Locations:** `src/window.vala:4533-4542`, `src/window.vala:4805-4813`,
`src/window.vala:5348-5357`,
`src/file_operation_service.vala:324-378`

The copy/move prompts only check exact equality:

```vala
if (dest_target.equal(item.file)) { ... }
```

They do not reject the case where `dest_target` is inside `source`. This is
easy to trigger accidentally: tag folder `a/sub` in one panel and copy it to
the opposite panel while that panel is inside `a/sub`. The destination becomes
`a/sub/sub`. `copy_file_or_dir()` creates the destination directory and then
enumerates the source, so the newly created destination appears in the
enumeration and is copied into itself again.

The multi-item path has the same problem because it builds
`dest_dir.get_child(it.name)` without an ancestry check.

**Impact:** unbounded directory recursion, path-length failures, disk fill, and
a large number of partial files. A move that falls back to copy + delete can
also leave the source partially duplicated.

**Fix:**

- Reject `source` when it is an ancestor of `dest` (or vice versa for move).
- Use canonical/real paths where possible and compare path components, not
  raw string prefixes.
- Exclude the destination from the enumeration as an additional safety net.
- For moves, perform the ancestry check before any deletion.

### F-03 — Archive member paths are not sanitized (zip-slip)

**Locations:** `src/archive_tree.vala:92-120`,
`src/archive_tree.vala:820-823`, `src/archive_tree.vala:899-903`,
`src/archive_operation_service.vala:785-808`,
`src/archive_operation_service.vala:816-838`

`ArchiveTree.add_entry()` strips leading slashes and skips `.` components, but
does not reject `..` components. Member names are then used directly to build
local destination paths:

- `get_temp_extracted_file()` uses
  `Path.build_filename(base_dir, inner_path)`.
- `collect_node_leaves()` uses `base_dest_dir.resolve_relative_path(rel)`.
- `extract_single_file_to()` creates the parent directory and writes the file.

An archive containing an entry such as
`../../../../home/user/.bashrc` therefore becomes a tree path with the same
components. Viewing or editing that entry with F3/F4 extracts it outside the
private preview directory. Copying a directory out of the archive can likewise
write outside the destination directory.

**Impact:** arbitrary file overwrite (with the user's permissions) from a
malicious archive. This is the classic zip-slip class, but it bypasses any
protection the external `unzip`/`tar` tools might apply because extraction is
performed manually by vcmd.

**Fix:**

- Normalize archive member names: remove leading `/`, reject any `..`
  component, reject absolute paths, and optionally reject empty names.
- Resolve the final destination and verify that it is a child of the intended
  base directory using `get_relative_path()` or a component-aware prefix check.
- Apply the same validation in `list_directory()`, nested archive navigation,
  and extraction paths.
- Add a regression test with crafted tar/zip/7z archives.

### F-04 — Predictable temporary directory can be pre-created as a symlink

**Locations:** `src/archive_tree.vala:788-871`

The private temp root is deterministic:

```vala
string root = Path.build_filename(tmp, @"vcmd-$((int)Posix.getuid())");
DirUtils.create_with_parents(root, 0700);
Posix.chmod(root, 0700);
```

`clean_temporary_directories()` calls `delete_recursive_sync()` on that path at
startup and shutdown. Neither the creation nor the cleanup checks that the
path is a real directory, that it is owned by the current user, or that it is
not a symlink. `chmod()` and directory enumeration follow symlinks.

On a shared `/tmp` (sticky bit prevents removing another user's files, but not
creating a new name), another local user can pre-create
`/tmp/vcmd-<victim-uid>` as a symlink to a directory owned by the victim. On
the next start, vcmd can chmod and then recursively delete the symlink target.

**Impact:** local cross-user data loss/denial of service. The same design also
lets two vcmd instances delete each other's staging data.

**Fix:**

- Use the per-user runtime directory (`$XDG_RUNTIME_DIR`) when available, or
  `g_dir_make_tmp("vcmd-XXXXXX")` for an unpredictable directory.
- Use `lstat()`/`O_NOFOLLOW` semantics and verify owner and mode before using
  or deleting the path.
- Refuse to continue if the path exists but is not a directory owned by the
  current UID.
- Never recursively delete a path that is a symlink.

### F-05 — Shell injection in the sshfs mount path

**Locations:** `src/remote_mount.vala:340-364`,
`src/remote_mount.vala:366-384`

`try_sshfs()` builds a mountpoint from the URI user, host, and port and then
executes:

```vala
Posix.system("fusermount -u -z " + mountpoint + " 2>/dev/null");
```

The host is not escaped when the URI is constructed by
`RemoteMount.build_uri()`; URI host grammar allows sub-delimiters such as
`;`, `&`, `$`, `(`, `)`, and quotes. A crafted bookmark or a pasted URI can
therefore inject shell syntax into this command. The call also blocks the main
loop while `fusermount` runs.

There is a second injection surface in the sshfs argument list: `target` is
built as `user@host:/` and appended without `--`. A URI user or host beginning
with `-` can be interpreted by sshfs as an option, including `ProxyCommand`
style options that execute commands.

**Fix:**

- Replace `Posix.system()` with `SubprocessLauncher` and an explicit argv:
  `{ "fusermount3", "-u", "-z", mountpoint }` (with a `fusermount` fallback).
- Validate the host as a DNS name or IP literal, and the user as a safe login
  name, before using them.
- Add `--` before the sshfs target where supported and reject targets that
  begin with `-`.
- Consider `StrictHostKeyChecking=accept-new` policy explicitly in the UI;
  automatically trusting new host keys is a separate security decision.

### F-06 — Cancelling a queued operation corrupts per-disk lock counts

**Locations:** `src/drive_queue_manager.vala:124-137`,
`src/drive_queue_manager.vala:170-187`,
`src/window.vala:4556-4584` (and all similar `finally` blocks)

`acquire_disks_async()` can throw `IOError.CANCELLED` in two cases before any
lock is acquired:

1. the cancellable is already cancelled at entry;
2. the task was queued and the user cancelled while waiting.

Every caller wraps the acquire in `try { ... } finally { release_disks(...); }`.
`release_disks()` unconditionally calls `unmark_disks_active(disks)`, which
decrements the active count even though this operation never incremented it.
If another operation is currently using the same disk, its count is reduced;
at zero, the queue considers the disk free and dispatches overlapping
operations.

**Impact:** serialization is broken exactly when a user cancels a queued
operation. This can lead to concurrent writes to the same HDD, which the
queue exists to prevent, and to queue state that no longer matches reality.

**Fix:**

- Make `acquire_disks_async()` return an acquisition token/lease, or set an
  `acquired` flag in the caller and release only when it is true.
- Make `release_disks()` idempotent and verify that the dialog is present in
  `active_tasks` before decrementing the count.
- Add a unit test for cancel-before-acquire, cancel-while-queued, and
  cancel-after-acquire.

### F-07 — “Overwrite” can silently delete a non-empty destination directory

**Locations:** `src/file_operation_service.vala:386-408`,
`src/file_operation_service.vala:460-480`,
`src/window.vala:5250-5295`

`copy_file_or_dir()` handles a regular file whose destination is an existing
directory by trying `dest.delete_async()` and, on failure,
`delete_recursive(dest)`. `move_file_or_dir()` does the same for any existing
destination. The conflict dialog only says that a file or folder with that name
already exists; it does not disclose that the entire existing folder tree will
be removed.

This affects:

- copying a file to a name currently occupied by a non-empty folder;
- moving/renaming a folder to a name currently occupied by another non-empty
  folder;
- restoring a trashed folder over an existing folder;
- creating a symlink over an existing folder.

**Impact:** accidental loss of arbitrary destination data after a generic
confirmation.

**Fix:**

- Distinguish file/file, file/directory, and directory/directory conflicts.
- For directory/directory conflicts, merge with per-file conflict resolution
  or require an explicit “Replace Folder and Delete Its Contents” warning that
  names the affected path and item count.
- Prefer moving the old destination to Trash instead of permanent recursive
  deletion.
- Never silently convert a failed file delete into a recursive directory
  delete without a specific user decision.

### F-08 — Extracting from archives overwrites existing files without prompting

**Locations:** `src/archive_operation_service.vala:785-808`,
`src/archive_operation_service.vala:875-889`,
`src/archive_tree.vala:963`

`extract_vfs_items()` calls `extract_single_file_to()` for each target without
checking whether the destination exists. `extract_single_file_to()` opens the
destination with `FileCreateFlags.REPLACE_DESTINATION`.
`extract_full_archive()` uses `unzip -o` and `7z x -y`, both of which overwrite
unconditionally.

**Impact:** copying files out of an archive (F5) or extracting a whole archive
can silently replace user files, unlike ordinary copy/move operations which use
`ConflictResolver`.

**Fix:**

- Reuse `ConflictResolver` for archive extraction targets.
- Preflight existing destinations and ask for overwrite/skip/skip-all, or
  extract into a temporary directory and merge with conflict handling.
- Do not pass `-o`/`-y` unconditionally.

---

## P1 Findings

### F-09 — Several subprocess paths can deadlock on a full stderr pipe

**Locations:** `src/archive_tree.vala:344-374`,
`src/archive_tree.vala:959-968`,
`src/archive_operation_service.vala:920-957`,
`src/extfs_runner.vala:71-98`,
`src/remote_mount.vala:391-401`

These paths start a child with `STDERR_PIPE`, then wait for child exit before
reading stderr. A child that writes more than the pipe buffer (typically
64 KiB) blocks in `write()`, and the parent blocks in `wait_check_async()`.
The same pattern appears in `extract_single_file_to()`, which splices stdout to
a file and only reads stderr after the child exits.

In addition, most of these paths do not connect cancellation to
`proc.force_exit()`. On cancellation the wait returns, but the child may remain
running and blocked on its pipe.

**Affected flows:** archive listing, single-file extraction, full archive
extraction, ExtFS helper commands, sshfs startup.

**Fix:**

- Drain stdout and stderr concurrently for every spawned child, or use
  `Subprocess.communicate_utf8_async()`.
- Cap collected stderr (already done in some places) and discard the excess.
- Connect the cancellable to a handler that calls `force_exit()` and closes
  pipes; disconnect it after wait.
- Add a timeout for external tools.

### F-10 — Archive passwords are passed on the command line

**Locations:** `src/archive_operation_service.vala:146-154`,
`src/archive_operation_service.vala:163-175`,
`src/archive_operation_service.vala:334-335`,
`src/archive_operation_service.vala:351-353`,
`src/archive_operation_service.vala:480-482`,
`src/archive_operation_service.vala:640-642`,
`src/archive_operation_service.vala:878-889`,
`src/archive_operation_service.vala:944-953`

Passwords are passed as `zip -P <password>`, `7z -p<password>`,
`unzip -P <password>`, and so on. Command lines are visible to the same user
(and often to other users depending on `/proc` mount options) through
`ps`, `/proc/<pid>/cmdline`, and process accounting.

**Impact:** credential disclosure while any archive operation is running.

**Fix:**

- Prefer a tool mechanism that reads the password from stdin or a securely
  permissioned file (7z can prompt/read from stdin; `unzip` has no secure CLI
  option, so consider libarchive or a temporary protected file with cleanup).
- If no secure mechanism exists, document the limitation and avoid caching
  passwords longer than necessary.
- Do not include passwords in logs (currently they are not logged, which is
  good).

### F-11 — Packing items from different directories archives the wrong files

**Locations:** `src/archive_operation_service.vala:20-24`,
`src/archive_operation_service.vala:208-211`,
`src/window.vala:3980-4000`

`pack_archive()` chooses the working directory from the first source item's
parent, then appends only `item.name` for every source. This is correct only if
all selected items share that parent. Search results and other cross-directory
selections violate that assumption. If a file with the same basename exists in
the first parent, the wrong file is archived; otherwise the tool reports a
missing file.

**Fix:**

- Validate that all source items share a common parent, or
- Stage the items (or compute paths relative to a common root) and pass
  unambiguous relative paths; or
- Reject cross-directory selections with a clear message.

Also exclude the destination archive when it is located inside a source
directory, to avoid including the archive in itself.

### F-12 — Command-line arguments are ignored, contradicting the desktop entry

**Locations:** `src/main.vala:6-21`, `src/application.vala:10-25`,
`install.sh:77-90`

The desktop file uses `Exec=<binary> %U`, and the application registers
`MimeType=inode/directory`, but `main()` only handles `--version`/`-v`, and
`Application` does not enable `HANDLES_OPEN` or implement `open`. Opening a
folder from Nautilus therefore starts vcmd at its saved/home directory rather
than the requested folder.

**Fix:**

- Enable `ApplicationFlags.HANDLES_OPEN` and implement `open(File[] files, ...)`.
- For local directories, open them in the active panel or a new tab.
- For archives/URIs, reuse the normal open path.
- Add a CLI parser for multiple arguments and `--new-window` if desired.

### F-13 — A failed directory load leaves the old file list under the new path

**Locations:** `src/file_panel_page.vala:3159-3203`,
`src/file_panel_page.vala:3230-3236`,
`src/file_panel_page.vala:3463-3469`

`load_directory()` sets `current_directory = dir` synchronously, then starts
the async load. On an error (permission denied, deleted directory, unreachable
mount, bad archive), the async function returns without clearing or restoring
the store. The panel now shows entries from the previous directory while
`current_directory` points to the failed one.

**Impact:** misleading path/status, and subsequent operations (copy destination,
“go up”, refresh) may use the wrong directory. The user may act on stale items
without realizing the navigation failed.

**Fix:**

- Keep the previous directory until the load succeeds, then commit the new
  path and store atomically.
- Or clear the store and show an inline error state on failure.
- Always restore `current_directory` and the cursor when a load fails.

### F-14 — `AppLogger` rewrites the whole log file for every entry

**Locations:** `src/app_logger.vala:135-161`

Every `info()`/`warn()`/`error()` call locks a mutex, reads the entire log file
with `FileUtils.get_contents()`, prepends the new line, and writes the whole
file back with `FileUtils.set_contents()`. This is synchronous disk I/O on the
calling thread, often the GTK main thread. The cost grows linearly with the
log size, and the whole file is rewritten for each event.

**Fix:**

- Append entries with `FileOutputStream`/`File.append_to()`.
- Rotate by size or keep the log bounded; reverse it only when displaying.
- Move file I/O off the main loop (writer thread or async queue).
- Set restrictive permissions (for example `0600`) for logs containing paths
  and usernames.

### F-15 — Synchronous UDisks DBus calls on the main thread

**Locations:** `src/volume_service.vala:493-520`

`check_is_encrypted()` calls `Bus.get_sync()` and `call_sync()` with a 500 ms
timeout. It is invoked for every mount and volume from `get_locations()`, which
runs on the UI thread during startup and on every volume-monitor change. A
slow or unavailable UDisks service can freeze the window for hundreds of
milliseconds per device.

**Fix:**

- Query encryption state asynchronously and update rows when results arrive.
- Cache per device node and invalidate on mount/volume changes.
- Avoid blocking DBus calls in any function reachable from the main loop.

### F-16 — Terminal command is fed before the async spawn completes; `fsck -y` is not interactive

**Locations:** `src/window.vala:5864-5868`,
`src/window.vala:1096-1160`,
`src/filesystem_repair_dialog.vala:192-195`

`open_terminal_with_command()` calls `set_console_visible(true)` and immediately
calls `vte_terminal.feed_child()`. If the terminal was not alive,
`set_console_visible()` starts `spawn_terminal()`, which uses
`vte_terminal.spawn_async()`. The command can be written before the PTY is
ready and be lost.

In addition, the repair dialog labels the action “Terminal fsck...” and says it
is interactive, but the command is `pkexec fsck -y '<device>'`; `-y` answers
“yes” to all repairs. It also does not unmount the device first in that path.

**Fix:**

- Queue the command and feed it from the `spawn_async` callback after a
  successful spawn.
- Check spawn errors and show them.
- For the interactive path, use plain `pkexec fsck '<device>'` (after
  unmounting) rather than `-y`, or clearly label it as automatic repair.
- Shell-escape the device node with `Shell.quote()` rather than manual single
  quotes.

### F-17 — Closed tab headers leak through signal-controller reference cycles

**Locations:** `src/file_panel.vala:1024-1035`,
`src/file_panel.vala:1126-1132`

The pin/mode/up `GestureClick` closures capture `tab_widget` and `this`.
`tab_widget` owns the controller, the controller owns the closure, and the
closure owns a strong reference to `tab_widget`. Vala generates a `g_object_ref`
for a captured local widget, so this is a cycle. The cycle keeps the closed
tab header and its closures alive after the page is removed.

`sync_tab_bar_pins()` also schedules an `Idle` callback on every call, so a
burst of tab events can queue many redundant full traversals of the tab bar.

**Fix:**

- Capture a weak reference to `tab_widget` (or use the controller's widget at
  signal time), and use a weak reference to the panel where possible.
- Disconnect/destroy custom controllers in `on_tab_page_detached()`.
- Debounce/coalesce `sync_tab_bar_pins()` instead of adding an `Idle` per call.

### F-18 — Version resolution prefers the current working directory and has a stale fallback

**Locations:** `src/config_manager.vala:29-57`

`get_version()` checks the relative path `VERSION` before the installed data
directory. Running the installed binary from any directory that happens to
contain a `VERSION` file reports that unrelated version. The final fallback is
hard-coded to `v0.7.2`, far behind the current `v0.10.8`.

**Fix:**

- Embed the version at build time (generated Vala constant or `-D`).
- Read only installation-owned paths at runtime.
- If a development override is desired, gate it behind an environment variable
  such as `VCMD_DEV_VERSION` or a debug build.
- Remove the hard-coded fallback or make it match the build version.

### F-19 — Configuration writes are not atomic

**Locations:** `src/config_manager.vala:758-766`

`save()` builds the complete config in memory and writes it directly to
`~/.config/vcmd/config` with `FileUtils.set_contents()`. A crash, full disk, or
power loss during the write can leave a truncated config. The next start
silently falls back to defaults or loads a partially valid file.

**Fix:**

- Write to a temporary file in the same directory, `fsync` it, then `rename()`
  over the target.
- Create the config directory with mode `0700` and the file with `0600`.
- Keep a backup of the last known-good config.
- Report write failures to the user at least once, rather than only `warning()`.

---

## P2 Findings and Improvements

### F-20 — Byte-based truncation breaks Unicode names

**Locations:** `src/file_panel.vala:613-615`, `src/file_panel.vala:644-645`,
`src/config_manager.vala:236-237`, `src/search_dialog.vala:290-292`

The code compares `char_count()` with a limit, then calls `substring(0, limit)`.
Vala strings are UTF-8 byte sequences, so `substring` counts bytes. For names
with multibyte characters, this either cuts too few characters or splits a
UTF-8 sequence, producing invalid text in tabs/bookmarks/status labels.

**Fix:** add a small helper that truncates by character/grapheme count using
`utf8_offset_to_pointer()` or repeated `next_char()`, and use it consistently.
The same helper should handle the leading ellipsis in the search status path.

### F-21 — Toasts are a no-op, so many operations finish silently

**Locations:** `src/window.vala:2463-2466`; call sites throughout
`src/window.vala`

`show_command_toast()` only logs the message. At least 30 call sites use it for
“copy completed”, “queued”, “cancelled”, “cd: no such directory”, terminal
restart, archive extraction, clipboard errors, and similar feedback. Users get
no visible confirmation.

**Fix:** re-enable `Adw.Toast` via `toast_overlay.add_toast()` (the overlay is
already present), or remove the no-op call sites and provide status-bar
feedback. If toasts were intentionally disabled, record that decision and stop
routing important errors through them.

### F-22 — The dialog “clearer” force-closes user dialogs after 500 ms

**Locations:** `src/window.vala:2752-2765`

`wait_for_dialogs_to_clear()` waits at most 25 × 20 ms (500 ms); if any
`Adw.AlertDialog` is still visible, it calls `force_close()`. A slow user
answering an overwrite/password dialog can therefore have that dialog forcibly
closed (which normally resolves to the cancel/default response) because another
dialog wants to appear.

**Fix:**

- Do not force-close user-facing dialogs. Queue the new dialog or integrate it
  into the existing dialog stack.
- If a timeout is required, use a much longer one and only apply it to
  internally owned progress dialogs, not alert dialogs.
- Log/diagnose “stuck” dialogs instead of silently closing them.

### F-23 — Directory metadata is lost when copying/merging directories

**Locations:** `src/file_operation_service.vala:324-352`

Directories are created with `dest.make_directory_async()` and never receive
the source's permissions, modification time, owner, or other metadata. Files use
`FileCopyFlags.ALL_METADATA`, but the directories do not. Move fallback
(cross-filesystem) inherits the same behavior.

**Fix:** after creating each destination directory, copy the relevant
attributes from the source `FileInfo` (`set_attribute_*` with
`query_settable_attributes()`), or use a dedicated recursive-copy helper that
preserves metadata best-effort. Report metadata failures without failing the
whole copy.

### F-24 — `file_exists_async()` swallows cancellation and all other errors

**Locations:** `src/file_operation_service.vala:167-178`

Every `query_info_async` error is converted to `false`. Cancellation during a
preflight check is ignored, and permission errors are treated as “does not
exist”; callers then proceed to create/copy and fail later with a less useful
error. In a copy loop this can also continue after the user pressed Cancel.

**Fix:** return `false` only for `IOError.NOT_FOUND` (and optionally
`NOT_SUPPORTED`); rethrow `CANCELLED` and other errors. Provide a separate
best-effort boolean helper for UI checks if needed.

### F-25 — Archive cache invalidation is weak and coupled to the password cache

**Locations:** `src/archive_tree.vala:283-303`,
`src/archive_tree.vala:201-209`; `src/window.vala:3796`

`get_tree()` caches only by archive path and modification time. Replacing an
archive with the same mtime (or modifying it externally while preserving mtime)
serves a stale tree. Conversely, `clear_cache(archive_path)` clears the
password cache too. After editing a file inside an encrypted archive,
`window.vala` calls `clear_cache()`, so the user is asked for the password
again even though only the listing changed.

**Fix:** key the tree cache by path + mtime + size + inode where available;
invalidate explicitly after every archive mutation; keep the password cache
separate and clear it only on authentication failure or explicit user action.
Cap the cache size.

### F-26 — `bool[]` properties and other Vala warnings indicate fragile models

**Locations:** `src/config_manager.vala:72`, `src/config_manager.vala:82`;
`src/drive_queue_manager.vala:163`, `src/drive_queue_manager.vala:275`;
`src/archive_pack_dialog.vala:79`

The compiler reports that `bool[]?` cannot be used for a GObject property.
Direct getter/setter access still compiles, but property notification, bindings,
and introspection are unreliable. The “copying delegates is not supported”
warnings around `ThumbnailTask.resume_callback` should be reviewed; simple
function-pointer copies currently work, but the warning is a maintenance risk.

**Fix:** make these plain fields or use a boxed/GObject wrapper type if they
must be properties. Replace copied delegates with an explicit callable wrapper
or a small object that owns the continuation. Treat these warnings as errors in
CI once the noisy const-qualifier warnings are filtered.

### F-27 — Build warnings worth cleaning up

Observed during a clean build:

- `Gtk.StyleContext` deprecated in GTK 4.10 (`window.vala:376-390`,
  `filesystem_repair_dialog.vala:71,535-539`). Plan the migration to the
  current style-provider API before the next GTK major release.
- `ConnectDialog.connect` hides `GLib.Object.connect`; rename to `do_connect`.
- `WallpaperDialog.show` and `DrivesDialog.show` hide `Gtk.Widget.show`;
  these are static helpers, but the name collision is confusing and warned
  about. Rename to `present`/`open`.
- Multiple unreachable `catch (Error)` clauses in `thumbnail_service.vala`,
  `device_detector.vala`, `wallpaper_service.vala`, and `archive_tree.vala`.
  These are dead error-handling paths; either remove them or call a throwing
  API deliberately.
- `g_list_store_splice()` pointer-type warnings in `file_panel_page.vala:178,
  3328, 3511` and the custom filter warning at `:954`. The ABI happens to be
  compatible, but the generated casts are fragile; prefer an intermediate
  `Object[]`/`void**` helper or a newer Vala.
- `spawnv()` receives `gchar**` where `const gchar* const*` is expected in
  many places; this is mostly const-correctness noise from Vala 0.56, but it
  can hide real argument bugs.
- `MainWindow.prompt_archive_outside_actions()` is never used
  (`window.vala:4323`). Remove it or wire it to the intended menu path.

### F-28 — No tests and no CI for the risky logic

There is no `tests/` directory or test target in the `Makefile`. The highest-risk
logic is pure enough to test without a display:

- archive line parsers and archive path normalization;
- rename/copy path validation and ancestor checks;
- conflict resolution state machine;
- config load/save round-trip and malformed input;
- drive queue acquire/release/cancel ordering;
- `format_error()` mapping.

**Recommendation:** add a small Vala test executable (or a separate test target)
and a CI job that runs `make` with warnings-as-errors for the project's own
sources. Integration tests for copy/move/delete/extract should use a temporary
directory under `$XDG_RUNTIME_DIR`, never the user's home.

### F-29 — Documentation drift

- `README.md:34` advertises “image and video thumbnail generation”, but
  `ThumbnailService` only recognizes image extensions and uses GdkPixbuf.
  There is no video/ffmpeg thumbnailer path in the source.
- `README.md:249-275` lists generic package names without minimum versions.
  The code uses libadwaita APIs added in 1.5 (`get_visible_dialog()`) and
  `Adw.TabView`/`Adw.AlertDialog` from earlier 1.x releases, so Debian/Ubuntu
  versions listed as generic examples may fail to compile or run.
- `DEV_PLAN.md:21,271` still marks the archive/ExtFS stage as “Planned”, while
  the feature is substantially implemented. Either update the plan or mark it
  as implemented with known gaps (the P0/P1 findings above are those gaps).
- The README claims “sub-second incremental builds”; the Makefile invokes
  `valac` on all 33 sources whenever any source changes, so a change triggers
  a full recompile, not an incremental link.

### F-30 — Packaging script path injection

**Location:** `package-release.sh:12-32,50`

`STAGE_DIR="${DIST_DIR}/${RELEASE_TAG}"` is built from the `VERSION` argument
or environment variable without validation. A value containing `/` or `..`
can make `rm -rf "${STAGE_DIR}"` delete outside `dist/`. Validate the version
against a strict pattern such as `^v?[0-9]+(\.[0-9]+){1,3}([-.+][A-Za-z0-9.-]+)?$`
and refuse paths outside `DIST_DIR`.

---

## Cross-Cutting Recommendations

1. **Centralize path safety.** Add a single utility module with
   `is_descendant()`, `validate_child_name()`, `normalize_archive_member()`,
   and `ensure_within()`. Use it from copy/move/rename/extract/symlink code.
2. **Centralize destructive decisions.** All “overwrite/replace/delete”
   operations should pass through one service that knows whether the target is
   a file or a directory and can offer Merge / Replace / Trash / Cancel.
3. **Own process plumbing.** Create one small `SubprocessRunner` that always
   drains stdout/stderr, honors cancellation, enforces a timeout, and never
   uses a shell. Migrate archive/ExtFS/sshfs code to it.
4. **Separate UI from blocking work.** Audit remaining `query_exists()`,
   `query_info()`, `FileUtils.*`, and `Bus.*_sync()` calls reachable from the
   GTK main loop. Move them to `*_async` or a worker thread with an idle
   callback.
5. **Bound all caches and queues.** Archive trees, nested origins, thumbnails,
   and log entries have weak or no bounds. Add size/age limits and explicit
   invalidation.
6. **Make version/build data generated.** Do not read `VERSION` from the
   current directory at runtime; generate a Vala constant from the build.
7. **Add a security test corpus.** Crafted zip/tar/7z files with `..`, absolute
   paths, leading dashes, symlinks, and huge stderr output should be part of
   the test suite.

## Build/Warning Summary

- Clean build: **success**, exit code 0.
- Smoke test: `./vcmd --version` prints `Vala Commander v0.10.8`.
- Notable warnings: deprecated `Gtk.StyleContext`; static `show()`/`connect()`
  name hiding; unreachable catch clauses; `bool[]` GObject property warnings;
  copied delegates; `g_list_store_splice` and custom-filter pointer-type
  mismatches; `spawnv()` const-qualifier mismatches; an unused
  `prompt_archive_outside_actions()` method.
- The many `-Wdiscarded-qualifiers` warnings in generated C are mostly a
  Vala/GCC const-correctness artifact and are lower priority than the
  behavioral findings above.

## Suggested Order of Work

1. Fix F-01, F-02, F-07 (destructive path handling) first.
2. Fix F-03, F-04, F-05 (security: archive paths, temp dir, shell).
3. Fix F-06 (queue lock accounting) and add tests.
4. Fix F-08/F-09 (archive extraction conflicts and subprocess deadlocks).
5. Address performance/UX issues: F-14, F-15, F-17, F-21, F-22.
6. Clean up F-26/F-27 warnings and add CI once the higher-risk fixes land.
