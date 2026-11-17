# Manual UI tests

These checks cannot be covered reliably by the display-free test suite.  
Run them against the installed binary after `make test` and `./install.sh lite`.

## Build and Startup

- [ ] `make test` reports all automated tests passing (or only tool-dependent skips).
- [ ] `vcmd --version` shows the expected version.
- [ ] Starting the application does not print `Theme parser error` to stderr.
- [ ] The window opens with both panels, tabs, path bar, and function bar.

## Destructive Operations
 
- [ ] Rename to `.` or `..` shows a validation error and changes nothing.
- [ ] Rename over a non-empty folder shows the “Folder Already Exists” warning and the destructive warning text.
- [ ] Cancelling the folder-replace dialog leaves the destination intact.
- [ ] Copying a file over a non-empty folder shows the folder warning.
- [ ] Copying a folder into its own subfolder is refused with a clear error.
- [ ] Multi-item symlink creation over existing items shows the preflight warning.
- [ ] Multi-item Trash restore over existing original locations shows the preflight warning.

## Tabs, Dialogs, and Feedback

- [ ] Pinned tabs cannot be closed; unpinning restores normal close behavior.
- [ ] Opening and closing many tabs does not show stale tab headers or grow memory continuously.
- [ ] Copy/move completion and cancellation show visible toasts.
- [ ] A conflict dialog remains open while the user waits longer than one second; it is not force-closed by another notification.
- [ ] Invalid `cd` input shows a toast and leaves the panel usable.
- [ ] Failed navigation to a missing/unreachable directory restores the previous path and file list.

## Archives
- [ ] Opening a normal `.tar`, `.tar.gz`, `.zip`, and `.7z` archive lists its contents.
- [ ] Nested archive navigation opens the inner archive and `..` returns correctly.
- [ ] F3/F4 inside an archive works, and saving updates the archive.
- [ ] Extracting a single file over an existing target shows the conflict dialog; Skip leaves the target unchanged.
- [ ] Extracting a full archive into a non-empty folder shows the “Destination Is Not Empty” warning.
- [ ] A crafted archive with `../` entries does not create files outside the destination; the log records the skipped entry.
- [ ] Password-protected zip/7z prompts for a password and retries after a wrong password.
- [ ] `ps`/`/proc/<pid>/cmdline` is checked during an encrypted archive operation for the known password-in-argv limitation.

## Processes and Cancellation

- [ ] Large archive listing/extraction keeps the UI responsive.
- [ ] Cancelling archive extraction does not leave `tar`, `7z`, `unzip`, or `zip` processes behind.
- [ ] A failing ExtFS helper shows its stderr diagnostics and does not hang.
- [ ] A failing sshfs connection does not leave a `sshfs` or `fusermount` process behind.

## Terminal and System Actions

- [ ] Terminal drawer opens, accepts input, and restarts correctly.
- [ ] A command passed from a dialog (for example Terminal fsck) is delivered after the PTY is ready.
- [ ] `pkexec fsck` is shown without `-y` and with a shell-quoted device path.
- [ ] Terminal close and restart do not leave duplicate shells.  

## Remote Connections

- [ ] Normal SSH/SFTP connection with an available key works.
- [ ] FTP/SMB connection uses GVfs and remains cancellable.
- [ ] Host/user input containing shell metacharacters is rejected or fails without executing a command.
- [ ] Remote paths containing `..` are rejected by the sshfs path handling.
- [ ] Stale sshfs mounts are released without a blocking shell call.  

## Drives, LUKS, and Permissions

- [ ] Opening Drives/Locations does not freeze while UDisks is queried.
- [ ] A locked LUKS volume is eventually marked “Encrypted • Locked” after the background probe.
- [ ] Mount, unmount, eject, and lock actions work with a real device.
- [ ] Emptying Trash asks for confirmation and reports failures instead of claiming success.  

## Desktop Integration
 
- [ ] “Open With vcmd” for a folder opens that folder, not Home.
- [ ] `vcmd /path/to/folder`, `vcmd /path/to/archive`, and `vcmd file.txt` behave as documented.
- [ ] The `.desktop` entry, icon, startup class, and `%U` argument all work.
- [ ] `./install.sh lite` and uninstall remove the expected files.  

## Visual and Metadata Checks

- [ ] Copying a folder preserves permissions and modification time (best effort).
- [ ] Long Unicode folder names, tab titles, and bookmark names truncate without broken glyphs.
- [ ] Brief, detailed, super-detailed, and thumbnail views render correctly.
- [ ] Thumbnail grid and previews work for supported images.
- [ ] Theme switching and font preferences apply without restart.
- [ ] No invalid CSS warnings appear in stderr.