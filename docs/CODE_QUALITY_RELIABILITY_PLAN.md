# Code Quality and Reliability Work Plan

This plan turns the two lowest assessment scores into an ordered program of
work:

- **Code cleanliness: 6/10 → target 8/10**
- **Reliability: 6/10 → target 8/10**

The plan deliberately starts with manual validation. Architecture work must not
begin until the real application behavior has been recorded and triaged.

## 1. Order of Work

| Phase | Name | Purpose | Gate |
|---:|---|---|---|
| 0 | Manual validation | Establish the real baseline and collect reproducible defects | Required before any structural work |
| 1 | Reliability blockers | Fix confirmed data-loss/security/process issues and close regression gaps | No P0/P1 remains |
| 2 | Quality foundations | Dialog/error service, warning budget, CSS/resources, documentation | Build and tests stay green |
| 3 | UI decomposition | Reduce `window.vala` and `file_panel_page.vala` responsibility | Behavior unchanged; manual UI spot-check passes |
| 4 | Deep reliability | Archive semantics, passwords, queue, recovery, remote/UDisks | New tests and manual checklist pass |
| 5 | Continuous quality | CI, release qualification, warning/documentation ratchets | Green CI and repeatable release process |

Phase 0 is defined in [MANUAL_TESTING_PLAN.md](MANUAL_TESTING_PLAN.md). Complete
that phase first. Small, isolated safety hotfixes discovered during Phase 0 may
be applied immediately, but large refactoring waits for the triage summary.

## 2. Planning Assumptions

- One main developer with review support; estimates are ranges, not commitments.
- Vala 0.56/GTK 4 API constraints remain until a minimum-platform decision is
  made in Phase 0.
- External archive tools remain supported; replacing them with libarchive is a
  product decision, not a prerequisite.
- UI behavior must remain recognizable; refactors are extraction of
  responsibilities, not a redesign.
- Every workstream must leave the automated suite green and update
  `tests/MANUAL_UI.md` when user-visible behavior changes.

## 3. Part 1 — Code Cleanliness Workstreams

### QC-1. Quality baseline and tooling

**Goal:** make current quality measurable and prevent silent regressions.

Tasks:

- Capture the current project-owned warning list and classify it:
  - real defects;
  - deprecated GTK API use;
  - Vala/GCC const-correctness noise;
  - dead code.
- Add a documented warning budget to the Makefile/CI policy without hiding
  broad classes of warnings.
- Add `make check` or equivalent for:
  - `git diff --check`;
  - test build;
  - optional shell syntax checks;
  - documentation link checks if a lightweight tool is available.
- Define a file-size/ownership policy for new code:
  - no new UI file above an agreed threshold without review;
  - services and models must not depend on GTK widgets.
- Add `.editorconfig` if missing and document the Vala style in use.

Deliverables:

- Warning inventory and policy;
- `make check`/CI entry point;
- documented file-boundary rules.

Acceptance:

- The project can distinguish new warnings from existing ones.
- CI (or a documented local command) fails on a new error/warning budget breach.

Size: **S–M**.

### QC-2. Unified dialog and error service

**Goal:** remove repeated destructive/conflict dialog implementations.

Tasks:

- Inventory every dialog and error flow for copy, move, rename, symlink,
  restore, archive extraction, and delete.
- Introduce a `FileOperationDialogs`/`DialogService` that builds:
  - file/file conflict prompts;
  - file/folder and folder/folder replace prompts;
  - multi-item preflight warnings;
  - consistent error dialogs with Retry/Skip/Cancel where applicable.
- Route all call sites through the service; remove near-duplicate builders.
- Keep `ConflictResolver` as the behavior contract and add tests for each
  response mapping.
- Preserve focus restoration and avoid dialog stacking regressions.

Deliverables:

- One dialog service for destructive operations;
- all conflict prompts produced by that service;
- tests for response mapping and wording-independent behavior.

Acceptance:

- No duplicated overwrite/rename/restore dialog construction remains in
  feature code.
- All prompts carry explicit folder-content warnings where deletion is
  possible.
- Existing manual destructive-operation checklist passes.

Size: **M**.

### QC-3. Decompose `window.vala`

**Goal:** reduce the main window from a multi-purpose monolith into a small
composition root.

Vala has no partial classes, so use composition and controller objects rather
than mechanical file splitting.

Candidate extractions:

- `TerminalController`: spawn, PTY, focus, command delivery, restart, kill.
- `OperationController`: background tasks, progress dialogs, queue popover,
  completion cleanup.
- `NavigationController`: panel activation, path entry, history/current
  directory, cross-panel synchronization.
- `ArchiveUiController`: archive actions, extraction prompts, update flows.
- `WindowDialogs`: about, shortcuts, preferences launch, generic alerts.
- `WindowState`: geometry, paned positions, tab persistence.

Tasks:

- Define interfaces/ownership and signal contracts first.
- Move one controller at a time, keeping tests and a manual smoke pass green.
- Remove dead methods such as unused archive outside-action code.
- Keep `MainWindow` as wiring only: construct, connect, present, close.

Deliverables:

- Controllers with clear public APIs;
- `window.vala` below an agreed staged threshold (suggested: < 3,000 lines
  after the first split, < 2,000 after stabilization);
- no duplicate state ownership between window and controllers.

Acceptance:

- No behavior change in the manual UI checklist.
- Controllers can be unit-tested where they do not require a display.
- No new direct dependency from services to window widgets.

Size: **L**.

### QC-4. Decompose `file_panel_page.vala`

**Goal:** separate the list/view model from navigation, selection, status, and
operation wiring.

Candidate extractions:

- `FileListView`: column/grid/brief factories and view switching.
- `SelectionController`: cursor, tags, shift navigation, select-by-mask.
- `PanelNavigation`: current directory, go-up, search/archive presentation,
  failed-load recovery.
- `DirectorySizer`: asynchronous size calculation and cancellation lifecycle.
- `PanelStatus`: counts, free space, status labels.
- `PanelMenus`: item context menu and actions.

Tasks:

- Move view-factory code first; it is mostly self-contained.
- Extract selection/tag state with tests for index/cursor transitions.
- Extract directory loading and error recovery next.
- Keep one public `FilePanelPage` facade so panels/controllers do not churn.

Deliverables:

- Smaller page facade and focused helpers;
- tests for selection, sorting, and failed-load state where no display is
  required;
- documented lifecycle cleanup.

Acceptance:

- `file_panel_page.vala` below an agreed threshold (suggested: < 2,000 lines);
- no regressions in filtering, sorting, tags, or archive/search tabs;
- manual UI pass for all four view modes.

Size: **L**.

### QC-5. CSS, resources, dead code, and warning cleanup

**Goal:** remove structural noise and stale artifacts.

Tasks:

- Move embedded CSS from `window.vala` into `data/style.css` or a GResource.
- Remove duplicate CSS blocks and invalid properties.
- Remove unused methods/fields and unreachable `catch` blocks.
- Migrate deprecated `Gtk.StyleContext` usage when the minimum GTK version
  allows it.
- Reduce const-correctness warning volume where practical; do not hide real
  warnings globally.
- Normalize file permissions and test artifact cleanup.

Deliverables:

- CSS single source of truth;
- smaller warning baseline;
- no dead code in reviewed areas.

Acceptance:

- No duplicate CSS between source and data;
- no `Theme parser error` at startup;
- warning budget documented and met.

Size: **S–M**.

### QC-6. Documentation and architecture decisions

**Goal:** keep project knowledge current and prevent documentation drift.

Tasks:

- Add an architecture overview: models, views, services, controllers, process
  boundaries, data flow for file and archive operations.
- Record ADRs for:
  - archive backends and password handling;
  - destructive-operation semantics;
  - temp directory and path safety;
  - test strategy and UI manual scope.
- Reconcile `README.md` with the current feature set (including
  thumbnail/video claims, minimum GTK/libadwaita versions, and archive
  support).
- Keep `docs/DEV_PLAN.md` clearly marked as historical; do not maintain its
  stage statuses as current roadmap data.
- Link `tests/README.md`, `tests/MANUAL_UI.md`, and docs from the root README.

Deliverables:

- Architecture document and ADR directory;
- updated README and a clear historical pointer from the docs index;
- documentation link check.

Acceptance:

- New contributors can find the test, UI, and architecture entry points.
- No known false feature claim remains in top-level docs.

Size: **S**.

### QC-7. Naming, interfaces, and review discipline

**Goal:** keep the codebase coherent as it grows.

Tasks:

- Define naming conventions for controllers, services, dialogs, and tests.
- Add review checklist items for:
  - new synchronous I/O on the UI thread;
  - new direct process spawning;
  - new destructive path operations;
  - new dialogs that bypass the dialog service;
  - new warnings and file-size growth.
- Require tests for new pure logic and service behavior.

Deliverables:

- Review checklist in `AGENTS.md` or docs;
- consistent names across new modules.

Acceptance:

- Review feedback is repeatable rather than ad hoc.

Size: **S**, continuous.

## 4. Part 2 — Reliability Workstreams

### REL-1. Destructive operation semantics

**Goal:** make replace/merge/delete behavior predictable and recoverable.

Tasks:

- Define a state machine for:
  - file → file;
  - file → folder;
  - folder → file;
  - folder → folder (merge/replace);
  - archive member → local destination.
- Replace implicit recursive deletion with explicit decisions:
  - Merge;
  - Replace via Trash (recommended default where possible);
  - Replace permanently (explicit destructive response).
- Remove the “failed delete then recursively delete” fallback or gate it behind
  a specific replace decision.
- Handle partial failure:
  - report what was copied;
  - clean temporary destination;
  - avoid deleting source if copy was incomplete.
- Add conflict/preflight tests using dummy resolvers and temp trees.

Acceptance:

- No destructively recursive delete happens without a specific decision.
- A cancelled operation leaves source and destination in a documented state.
- Tests cover every conflict matrix cell.

Size: **L**.

### REL-2. Secure archive password handling

**Goal:** remove password exposure from process arguments.

Tasks:

- Inventory all password-bearing commands for zip/7z/unzip/tar helpers.
- Choose an approach:
  - libarchive integration; or
  - stdin-driven prompts for 7z plus a documented fallback for tools without a
    secure mechanism.
- Update pack, add, delete, update, list, and extract flows.
- Clear password cache entries on failure and application shutdown; avoid
  logging secrets.
- Add a test that asserts the password does not appear in a spawned process
  command line (using a fake helper or a process wrapper).
- Manually verify encrypted zip/7z workflows.

Acceptance:

- No archive password appears in `/proc/<pid>/cmdline`.
- Encrypted archive UX remains understandable and retryable.
- Security limitation is either removed or explicitly documented.

Size: **L**.

### REL-3. Archive robustness and parser coverage

**Goal:** make archive listing/extraction reliable across real-world names and
tools.

Tasks:

- Build a test corpus of small archives:
  - spaces, leading dashes, Unicode, newline-like names;
  - `..` and absolute paths;
  - symlinks, empty directories, large file counts;
  - password-protected zip/7z;
  - truncated/corrupt archives.
- Replace fragile fixed-offset parsing where possible (prefer structured tool
  output or locale-stable switches).
- Verify tool availability and skip/clear error behavior per format.
- Ensure cache invalidation covers mtime, size, and explicit mutations.
- Verify extraction preserves or intentionally ignores metadata.

Acceptance:

- Crafted corpus is part of the test suite (or generated by it).
- No path escape, no hang, and a clear error for corrupt archives.
- Tar/zip/7z variations have documented support status.

Size: **M–L**.

### REL-4. Unified process runner and cancellation

**Goal:** eliminate remaining deadlock/orphan-process classes.

Tasks:

- Finish migrating all external commands to the common capture/drain helper.
- Add configurable timeout and cancellation-to-`force_exit` behavior.
- Ensure stderr is bounded and diagnostic text is preserved.
- Provide a test double or fake tool for timeout/cancel tests.
- Audit `process_utils.vala`, archive, ExtFS, sshfs, and terminal helpers for
  remaining ad-hoc pipelines.

Acceptance:

- No code path waits for a child before draining both pipes.
- Cancellation kills the process group where appropriate.
- Tests prove no orphan processes after cancel/timeout.

Size: **M**.

### REL-5. Drive queue and asynchronous lifecycle

**Goal:** make queue accounting and cancellable UI lifecycles testable and
correct.

Tasks:

- Extract a pure `DiskLockTable` from `DriveQueueManager`:
  - acquire/release/refcount;
  - queued cancellation;
  - dispatch ordering.
- Keep `OperationProgressDialog` as a presentation adapter.
- Add unit tests for cancel-before-acquire, cancel-while-queued,
  cancel-after-acquire, and duplicate release.
- Audit async callbacks for UI access after destruction.
- Verify tab/page cleanup cancels loads, size calculations, and thumbnail
  requests.

Acceptance:

- Queue accounting has direct unit tests without GTK.
- Repeated cancellation does not leak or corrupt lock counts.
- No use-after-destroy path in reviewed async callbacks.

Size: **M**.

### REL-6. Error handling and recovery

**Goal:** stop silently swallowing actionable failures.

Tasks:

- Audit every `catch (Error e) {}` and best-effort helper.
- Keep best-effort only for metadata/cleanup; propagate fatal and cancellation
  errors.
- Ensure Empty Trash reports partial failures instead of declaring success.
- Standardize error categories and user actions (Retry/Skip/Cancel).
- Add cleanup on partial copy/move/extract and report leftover state.
- Verify config/log recovery paths and corrupt-config behavior.

Acceptance:

- No silent failure on user-visible operations.
- Cancellation and permission errors are distinguishable.
- Partial-operation outcome is visible and testable.

Size: **M**.

### REL-7. Remote connections and UDisks

**Goal:** make non-local features predictably cancellable and non-blocking.

Tasks:

- Keep URI validation strict and covered by tests.
- Add timeouts and cancellation handling to sshfs/GVfs setup and unmount.
- Ensure GVfs fallback preserves the original URI and does not lose context.
- Cache UDisks/LUKS probes and invalidate on device changes.
- Add tests for pure URI/remote-path helpers; keep real network tests manual.
- Document supported providers and credential limitations.

Acceptance:

- No blocking DBus/`fusermount` call on the GTK main thread.
- A failed/unreachable remote does not freeze the UI or leave child processes.
- Remote limitations are documented.

Size: **M**.

### REL-8. CI, integration tests, and release qualification

**Goal:** make quality continuous instead of session-based.

Tasks:

- Add CI that runs:
  - clean build;
  - `make test`;
  - shell syntax checks;
  - documentation/existence checks;
  - package script validation.
- Add an archive integration corpus job (tar/zip/7z when available).
- Add an optional headless GTK smoke job if a supported display server is
  available; otherwise keep UI manual.
- Define release checklist:
  - green tests;
  - manual UI pass;
  - version/package validation;
  - known-limitations update.
- Track warning count and file sizes over time.

Acceptance:

- A pull request cannot merge with a red test suite.
- Release candidates always have a completed manual UI checklist.
- Test skips are visible and justified.

Size: **M**, continuous.

## 5. Dependencies and Sequencing

```text
Phase 0 manual validation
        |
        v
Phase 1 reliability blockers
  REL-1 destructive semantics
  REL-2 password handling
  REL-4 process runner
  REL-6 error recovery (confirmed issues only)
        |
        v
Phase 2 quality foundations
  QC-1 baseline/tooling
  QC-2 dialog service
  QC-5 CSS/dead code/warnings
  QC-6 documentation
        |
        v
Phase 3 UI decomposition
  QC-3 window controllers
  QC-4 panel page helpers
        |
        v
Phase 4 deep reliability
  REL-3 archive corpus
  REL-5 queue/lifecycle
  REL-7 remote/UDisks
  REL-8 CI/release
        |
        v
Phase 5 continuous ratchets
```

`QC-1`, `QC-2`, and `REL-8` can start earlier because they reduce risk for
later work. `QC-3` and `QC-4` must not begin until Phase 0 is triaged and the
dialog/error contract from `QC-2` is stable.

## 6. Acceptance Metrics

Suggested targets, to be refined after Phase 0:

### Code cleanliness

- No feature file above the agreed threshold without a documented reason.
- `window.vala` and `file_panel_page.vala` each reduced by at least 50% from
  their current sizes.
- One dialog/error service owns destructive prompts.
- One CSS source of truth.
- Project-owned warnings below the agreed budget; no new deprecation warnings
  without a tracking issue.
- README, docs index, and architecture docs current; historical plan clearly marked.

### Reliability

- No known P0 or P1 issue.
- No archive password in process argv.
- All destructive operations have explicit, tested semantics.
- No child-process deadlock/orphan known; timeout/cancel tests pass.
- Drive queue accounting has direct unit tests.
- CI runs build + tests on every change.
- Manual UI checklist completed for each release candidate.
- Automated suite grows to cover every closed reliability bug with a regression
  test.

## 7. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Large UI refactor changes behavior | Extract incrementally; keep a facade; manual spot-check after each extraction |
| Password refactor changes tool UX | Decide libarchive vs stdin first; keep fallback and document limitations |
| Dialog service becomes another monolith | Model conflict semantics first; keep presentation adapters thin |
| Archive test corpus adds binary blobs | Generate archives at test time unless a small fixture is explicitly approved |
| Remote/LUKS tests are flaky | Keep real network/device checks manual; unit-test pure helpers |
| CI lacks a display | Keep GTK tests manual; add optional headless job only if stable |
| Scope grows during refactoring | Tie every task to a measurable acceptance criterion; no feature work in refactor PRs |

## 8. Deliverables Checklist

- [ ] Phase 0 triage summary completed.
- [ ] Reliability blocker issues fixed or accepted.
- [ ] Dialog/error service in use.
- [ ] `window.vala` and `file_panel_page.vala` decomposed.
- [ ] Password handling no longer exposes argv.
- [ ] Destructive operation matrix implemented and tested.
- [ ] Process runner migration completed.
- [ ] Disk lock table extracted and tested.
- [ ] Archive corpus and integration tests added.
- [ ] CI and release checklist active.
- [ ] README, docs index, architecture docs, and manual checklist updated; historical plan marked.
- [ ] Assessment scores re-evaluated after Phase 4.
