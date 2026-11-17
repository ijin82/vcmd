# Manual Testing Plan (Phase 0)

This is the first phase of the quality and reliability work plan. Its purpose is
to establish what actually works in the real GTK application before any further
refactoring starts. Automated tests must already be green:

```bash
make test
./install.sh lite
```

Use `tests/MANUAL_UI.md` as the item-level checklist. This document defines the
execution order, recording format, triage rules, and the questions that must be
answered before coding work begins.

## 1. Goals

- Confirm the installed binary is the current build.
- Exercise every user-visible path affected by the first fix round.
- Record reproducible failures with enough detail to turn them into issues.
- Decide whether follow-up work is a bug fix, a design decision, or an
  enhancement.
- Freeze a short issue list before touching architecture.

## 2. Test Environment

Record at the start of every session:

- date and time zone;
- `vcmd --version` output;
- desktop session (GNOME/KDE/other), compositor, GTK/libadwaita versions;
- filesystem types under test (ext4, btrfs, NTFS, FAT, tmpfs, network mount);
- whether the test is local, SSH/SFTP, SMB, FTP, or a virtual machine;
- test data root, for example `~/vcmd-manual-tests/`;
- any special setup such as a LUKS device or mounted external disk.

Do not test destructive operations in the real home directory. Use a disposable
tree:

```bash
mkdir -p ~/vcmd-manual-tests/{src,dst,archives,trash}
```

## 3. Session Order and Time Budget

| Session | Focus | Estimate | Gate |
|---|---|---:|---|
| 0.1 | Build, install, startup, CSS, basic panels | 0.25 day | Must pass before continuing |
| 0.2 | Destructive operations and confirmation dialogs | 0.5 day | Record all deviations |
| 0.3 | Tabs, toasts, dialog stacking, failed navigation | 0.25 day | Record all deviations |
| 0.4 | Archives, extraction, encryption, zip-slip | 0.5 day | Blocking test for reliability |
| 0.5 | Process cancellation, terminal, fsck | 0.5 day | Record orphan processes and hangs |
| 0.6 | Remote SSH/SFTP/FTP/SMB | 0.5 day | May be skipped if no endpoint |
| 0.7 | Drives, UDisks, LUKS, Trash | 0.5 day | May require physical device |
| 0.8 | Desktop integration, CLI arguments, visual checks | 0.25 day | Final pass |

Total: roughly **3–4 focused days**, plus issue triage.

## 4. Procedure

### 4.1 Start clean

1. Close any running `vcmd` instance.
2. Run `make test`.
3. Run `./install.sh lite`.
4. Start the installed binary outside the source tree to verify installed data
   is used:

```bash
cd /tmp
vcmd --version
vcmd
```

5. Clear the old log or record its size so new warnings are attributable:

```bash
cp ~/.config/vcmd/vcmd.log ~/vcmd-manual-tests/vcmd.log.before
```

### 4.2 Execute by checklist group

Use `tests/MANUAL_UI.md` in order. For each item record:

```text
ID:
Result: PASS / FAIL / BLOCKED / NOT APPLICABLE
Steps:
Expected:
Actual:
Reproduction rate:
Log excerpt:
Screenshot/video:
Notes:
```

Do not mark an item PASS if it was not actually exercised. Use `BLOCKED` when a
device, network endpoint, or credential is unavailable.

### 4.3 Capture evidence

For a failure, capture:

```bash
tail -n 200 ~/.config/vcmd/vcmd.log
pgrep -af 'vcmd|tar|7z|unzip|zip|sshfs|fusermount'
```

For UI issues, attach a screenshot. For a freeze, note whether the main loop
was blocked and whether a child process remained alive.

### 4.4 Triage

Classify every finding:

- **P0 / data loss or security** — stop the session, preserve evidence, do not
  continue destructive tests until understood.
- **P1 / broken core workflow** — must be fixed before structural refactoring.
- **P2 / rough edge or UX issue** — schedule with the relevant workstream.
- **P3 / cosmetic or documentation** — batch into cleanup.

Record whether the issue is a regression from the recent fix round or a
pre-existing behavior.

## 5. Exit Criteria for Phase 0

Phase 0 is complete when:

- every checklist group is marked PASS, FAIL, BLOCKED, or N/A;
- all FAIL items have a class and a reproducible case;
- all P0/P1 findings are either fixed or explicitly accepted;
- open design questions below have an owner and a decision;
- the baseline assessment scores are revisited with the findings.

No large refactoring starts before this gate.

## 6. Questions to Answer After Manual Testing

These are expected to change the scope of the work plan:

1. **Folder replacement:** is permanent recursive deletion after an explicit
   confirmation acceptable, or must replacement move the old tree to Trash?
2. **Bulk archive extraction:** is an upfront warning sufficient, or is
   per-file Skip/Overwrite required for all archive formats?
3. **Password security:** should the project accept a libarchive dependency or
   use tool-specific stdin handling even if behavior differs between zip/7z?
4. **Minimum platform:** which GTK/libadwaita/Vala versions must remain
   supported? This affects deprecation cleanup and API use.
5. **Remote scope:** which providers are release-blocking (SSH/SFTP, SMB, FTP,
   WebDAV) and which are best-effort?
6. **LUKS/UDisks:** is administrative-device support in scope for the next
   release, or should it remain an advanced feature?
7. **Performance targets:** what directory sizes and archive sizes must stay
   responsive on reference hardware?
8. **UI automation:** is an Xvfb-based smoke harness acceptable as a CI
   dependency, or should all GTK tests remain manual?
9. **Test data policy:** may the repository contain small crafted archives, or
   must they be generated at test time?
10. **Release policy:** is a green `make test` plus a manual UI pass required
    for every release, or only for minor/major releases?

## 7. Output of Phase 0

Create a single triage summary with:

- counts by severity;
- affected checklist groups;
- confirmed regressions;
- accepted limitations;
- decisions for the questions above;
- proposed workstream updates for
  [CODE_QUALITY_RELIABILITY_PLAN.md](CODE_QUALITY_RELIABILITY_PLAN.md).

That summary becomes the input to Phase 1.
