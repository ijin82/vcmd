# Automated Tests

The suite is intentionally split into fast, display-free tests and a manual UI
checklist. Tests run against a temporary filesystem tree and isolated XDG
directories; they must never modify the user's real configuration, bookmarks,
Trash, or home directory.

## Run Everything

```bash
make test
```

`make test` builds `tests/vcmd-tests` and runs every test through
`tests/run_tests.sh`. Each test runs in its own process with fresh
`XDG_CONFIG_HOME`, `XDG_CACHE_HOME`, `XDG_DATA_HOME`, `XDG_RUNTIME_DIR`, and
`TMPDIR` directories. This isolation is required because `ConfigManager` and
`AppLogger` are process-wide singletons.

## List Tests

```bash
make test-list
# or
./tests/vcmd-tests --list
```

Each line has the form:

```text
name|short description
```

## Run One Test

```bash
./tests/run_tests.sh path.names
./tests/run_tests.sh fileops.copy_into_self
./tests/run_tests.sh archive.list_tar
```

The wrapper sets the isolated environment for a single test as well.

## Direct Test Binary

`./tests/vcmd-tests --run <name>` is useful while debugging, but it does not
create isolated XDG directories. Use it only with the environment already
prepared by the wrapper. The binary deliberately refuses to run all tests
without an explicit `--run`; use `make test` for a full run.

## Test Groups

| Test | What it checks |
| --- | --- |
| `path.names` | Child-name validation rejects empty names, `.`, `..`, and `/`. |
| `path.ancestry` | Same/descendant checks use path-component boundaries, not raw prefixes. |
| `path.archive_sanitize` | Archive member normalization rejects `..` and strips leading `/`/`./`. |
| `path.unicode` | UTF-8 truncation and suffix operations do not split characters. |
| `fileops.copy_file` | A regular file is copied with the expected content. |
| `fileops.copy_into_self` | Copying a directory into its own descendant returns `INVALID_ARGUMENT`. |
| `fileops.move_into_self` | Moving a directory into its own descendant returns `INVALID_ARGUMENT`. |
| `fileops.delete_recursive_symlink` | Recursive delete removes a symlink itself, not its target. |
| `fileops.create_symlink` | Symlink creation produces a `SYMBOLIC_LINK` entry. |
| `fileops.copy_dir_metadata` | Directory permissions are preserved by a normal directory copy. |
| `fileops.cancel_preflight` | `file_exists_checked_async()` propagates `CANCELLED`. |
| `fileops.file_over_dir_skip` | A file copied over a directory with `SKIP` leaves directory contents intact. |
| `archive.reject_unsafe_entry` | `ArchiveTree.add_entry()` refuses traversal entries. |
| `archive.temp_path_contained` | Preview extraction paths remain inside the secure temp root. |
| `archive.list_tar` | A real tar archive is listed through `ArchiveTreeService`; skipped without `tar`. |
| `archive.list_zip` | A real zip archive is listed through `ArchiveTreeService`; skipped without `zip`. |
| `registry.extensions` | Common archive extensions are recognized. |
| `registry.formats` | Pack formats can be found by extension. |
| `process.stderr_drain` | A child writing more than a pipe buffer to stderr does not deadlock. |
| `config.atomic_save` | Config is written with mode `0600` and no temporary file remains. |
| `config.version_precedence` | Installed version data wins over other candidates. |
| `logger.append_order` | Log entries append chronologically with mode `0600`. |
| `remote.build_uri` | SFTP-style URIs are assembled correctly. |
| `remote.path_detection` | Remote, local, and archive URIs are distinguished. |
| `scripts.release_version` | `package-release.sh` rejects unsafe version strings. |
| `temp.legacy_symlink_cleanup` | Legacy `/tmp/vcmd-$UID` symlinks are not followed or deleted through. |
| `temp.secure_root` | The secure temp root is a real user-owned `0700` directory. |

## Requirements

- `valac`, GTK 4 development packages, libadwaita, VTE, and the normal build
  dependencies (`make`) are required to compile the test binary.
- `tar` and `zip` are optional. Their tests report `SKIP` when the tool is not
  installed.
- Tests do not require a display and must not create GTK windows.
- Do not run the suite as root unless explicitly testing a root-only scenario.
  The default suite is designed for an unprivileged user.

## Adding Tests

1. Add a `tests/test_*.vala` file in namespace `VCommander.Tests`.
2. Expose a `public static void register(TestRegistry registry)` method.
3. Register each case with a unique `group.test_name` and an English
   description.
4. Use `TestFs.create_temp_root()` and `TestFs.remove_tree()` for filesystem
   isolation. Always call `ctx.finish()` from `finally`.
5. Register the module in `tests/test_main.vala`.
6. Run `make test`.

Tests that need external tools should call `ctx.skip()` when the tool is not
available, and tests that need a display must be added to the manual checklist
instead.

## Manual UI Checklist

See [MANUAL_UI.md](MANUAL_UI.md) for the checks that require a real GTK display,
network access, polkit, or physical devices.
