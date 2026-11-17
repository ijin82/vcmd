# Project Assessment: Vala Commander (`vcmd`)

- **Assessment date:** 2026-11-17
- **Project version:** `v0.10.8`
- **Scope:** approximately 22,300 lines of Vala across 33 source files,
  Makefile, shell installers, documentation, and the new test suite.
- **Basis:** full source review, clean build, 27 automated tests, runtime
  smoke tests, and manual review of the main file-operation/archive/remote
  paths. A complete manual UI pass has not yet been recorded.

All scores are subjective and intentionally strict: `10` means production-grade
excellence, not merely "works on my machine".

## Score Summary

| Area | Score | Short rationale |
|---|---:|---|
| Code cleanliness | **6 / 10** | Readable and consistent, but large UI files, duplicated dialogs, and warning debt remain |
| Reliability | **6 / 10** | Critical data-loss and injection bugs were fixed, but destructive and security edge cases remain |
| Project overall | **7 / 10** | Strong niche product with broad functionality and an active base |
| Development potential | **8 / 10** | Clear room to become a mature GTK4 dual-pane file manager if quality work continues |

## 1. Code Cleanliness — 6/10

### Strengths

- Consistent namespace and naming conventions.
- English comments and user-facing strings; no mixed-language source.
- Clear service boundaries exist for file operations, archives, configuration,
  logging, and path/process utilities.
- `FileOperationService` centralizes most copy/move/delete/conflict behavior.
- `PathUtils` and `ProcessUtils` now provide reusable safety and subprocess
  helpers instead of repeating ad-hoc logic.
- The Makefile is small and understandable; the test suite lives under
  `tests/` and does not pollute application sources.
- The new tests provide executable documentation for several important
  invariants.

### Weaknesses

- `src/window.vala` is roughly 5,900 lines and mixes UI construction, global
  actions, terminal handling, navigation, operation orchestration, dialogs,
  and state persistence.
- `src/file_panel_page.vala` is roughly 3,600 lines and combines the list
  model, view factories, selection logic, navigation, status bar, filtering,
  and archive/search presentation.
- Several dialogs are near-duplicates: rename, copy, delete, restore, symlink,
  and archive conflict flows repeat layout and response handling.
- Embedded CSS in `window.vala` duplicates/overlaps with `data/style.css`.
- Dead code and unreachable `catch` blocks remain in a few places.
- The build still emits around 100 warnings, mostly Vala/GCC const-correctness
  noise, but also some real cleanup targets such as deprecated
  `Gtk.StyleContext` usage and unused methods.
- No formatter, linter, warning budget, CI check, or architecture decision log
  is enforced yet.
- Documentation drift exists between `README.md` and the historical `docs/DEV_PLAN.md`.

### What Would Raise the Score

- Extract controllers/services from the large UI files and set explicit file
  size targets.
- Introduce a single dialog/error service for destructive and conflict flows.
- Remove duplicated CSS and dead code; reduce project-owned warnings.
- Add CI for build warnings, tests, and documentation links.
- Record architecture decisions and keep README plus the current docs synchronized; keep `docs/DEV_PLAN.md` clearly marked as historical.

## 2. Reliability — 6/10

### Strengths

- High-risk path traversal and self-recursion scenarios were addressed:
  rename to `.`/`..`, copy/move into a descendant, archive `..` members, and
  unsafe archive preview paths.
- Archive temporary directories are now randomized and user-owned.
- The sshfs shell-concatenation path was replaced with argv-based process
  launch and host/user validation.
- Drive-queue lock accounting no longer decrements a lock that was never
  acquired.
- The most important subprocess stderr deadlocks were removed, and several
  cancellation paths now terminate child processes.
- Config writes are atomic and restricted to `0600`; logging appends instead of
  rewriting the whole file for every line.
- Archive extraction now has conflict handling for selected files and a
  preflight warning for non-empty bulk destinations.
- The automated suite covers path safety, file operations, archive tree
  sanitization, real tar/zip listing, stderr draining, config/logging, and
  temporary-directory cleanup.

### Weaknesses

- Archive passwords are still passed on command lines (`zip -P`,
  `unzip -P`, `7z -p...`) and are visible through `ps` and
  `/proc/<pid>/cmdline`.
- Full-archive extraction uses a single upfront warning rather than per-file
  skip/overwrite behavior.
- Confirmed "Replace Folder" still permanently deletes destination contents;
  there is no undo or Trash-backed replacement.
- File operations are not transactional. A partial failure can leave a
  partially copied tree, and there is no resume/rollback workflow.
- No automated coverage for GTK dialogs, drive queue behavior, SSH/SFTP, LUKS,
  VTE, or real password-protected archives.
- External tool behavior (`tar`, `zip`, `7z`, `sshfs`, ExtFS helpers) remains a
  source of variability; parser assumptions are sensitive to output formats.
- Some errors are deliberately or accidentally swallowed, and several UI
  paths still rely on best-effort state recovery.
- CI, sanitizer runs, and long-running stress tests are absent.

### What Would Raise the Score

- Move archive password handling to stdin/libarchive or a secure helper.
- Add explicit merge/replace/skip semantics for bulk extraction and folder
  replacement, preferably with Trash-backed backup.
- Make copy/move/restore resumable or cleanly roll back partial output.
- Add automated tests for the drive queue, process cancellation, and crafted
  archive corpora.
- Add CI with build, unit/integration tests, and optionally sanitizers.
- Run the manual UI matrix after each risky change.

## 3. Project Overall — 7/10

### Strengths

- A real, useful niche: GTK4/Libadwaita dual-pane file management with a
  keyboard-first Midnight Commander workflow.
- Broad feature set: tabs, archive VFS, Trash, remote connections, embedded
  VTE terminal, search, thumbnails, bookmarks, preferences, desktop
  integration, and packaging.
- Existing installer, desktop entry, icon generation, and release script.
- Active development and a codebase that already handles substantial
  complexity.
- The new test infrastructure provides a foundation for safer iteration.

### Weaknesses

- Feature breadth currently exceeds reliability and test coverage.
- Several advanced features are deep but still have rough edges.
- Large UI files make maintenance and onboarding harder.
- Documentation promises more than the implementation in a few places.
- The project does not yet have the CI and release discipline expected from a
  widely distributed desktop application.

Overall this is a strong enthusiast/small-team project with a credible product
identity. It is not yet a production-grade file manager for conservative users,
but it is well beyond a prototype.

## 4. Development Potential — 8/10

The project has high potential because:

- The "modern GTK4 file manager with MC-style keyboard control" niche is not
  saturated.
- The current architecture can be incrementally decomposed without a rewrite.
- The new test harness makes refactoring safer.
- Natural next steps are clear: safer destructive operations, secure password
  handling, better conflict semantics, CI, packaging, and remote robustness.
- The feature set provides multiple growth paths: plugins, user actions,
  archive backends, remote providers, Flatpak/distro packages, and deeper
  GNOME integration.

Main growth risks:

- Feature scope can outrun maintainability.
- UI monoliths will keep absorbing responsibilities unless decomposition is
  scheduled explicitly.
- Vala/GTK and external CLI tools add ecosystem and compatibility risks.
- Security-sensitive behavior (passwords, archive extraction, remote mounts)
  requires more rigor than the current test suite provides.

The potential score is higher than the current quality scores because the
project has a clear product direction and a workable base; the gap is mostly
engineering discipline, not lack of ideas.

## 5. Conditions for Higher Scores

| Target score | Code cleanliness | Reliability |
|---|---|---|
| 7/10 | Large UI files decomposed; dialog/CSS duplication removed; warning budget enforced | No known P0/P1 security or data-loss gaps; CI green; destructive semantics tested |
| 8/10 | Stable module boundaries, documented ADRs, low warning count, consistent review process | Transactional/undoable destructive operations, secure password handling, automated integration/stress coverage |
| 9–10/10 | Sustained architectural discipline across releases | Production-grade security review, fuzzing, CI matrix, release qualification, and measured recovery behavior |

## 6. Assessment Limits

- No complete manual UI walkthrough was performed for this assessment.
- Network, LUKS, polkit, and physical-device paths were not exercised.
- The automated suite intentionally excludes GTK rendering and real remote
  services.
- The scores should be revisited after the manual test plan in
  `docs/MANUAL_TESTING_PLAN.md` is completed and its findings are triaged.
