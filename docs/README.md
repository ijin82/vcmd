# Project Documentation

This directory stores project-level assessment, planning, and quality records so
they are not lost in chat history or temporary notes.

## Documents

| Document | Purpose |
|---|---|
| [PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md) | English translation of the project assessment with scores for code cleanliness, reliability, overall project, and development potential |
| [MANUAL_TESTING_PLAN.md](MANUAL_TESTING_PLAN.md) | Phase 0 execution plan: manual validation order, evidence capture, triage, and questions to resolve |
| [CODE_QUALITY_RELIABILITY_PLAN.md](CODE_QUALITY_RELIABILITY_PLAN.md) | Workstreams, sequencing, acceptance criteria, and risks for the two lowest-scoring areas |
| [DEV_PLAN.md](DEV_PLAN.md) | Historical development plan, kept for project history; outdated and not a current source of truth |

## Related Records

- [../CODE_REVIEW.md](../CODE_REVIEW.md) — original detailed technical review
  with `file:line` findings.
- [../tests/README.md](../tests/README.md) — automated test inventory and
  commands.
- [../tests/MANUAL_UI.md](../tests/MANUAL_UI.md) — item-level manual UI
  checklist.

## Workflow

1. Execute manual validation using [MANUAL_TESTING_PLAN.md](MANUAL_TESTING_PLAN.md).
2. Triage the findings and answer the open design questions.
3. Update workstream scope in
   [CODE_QUALITY_RELIABILITY_PLAN.md](CODE_QUALITY_RELIABILITY_PLAN.md).
4. Work through the phases, keeping `make test` green and recording
   user-visible changes in the manual checklist.
5. Re-evaluate the scores in [PROJECT_ASSESSMENT.md](PROJECT_ASSESSMENT.md) after
   each major phase.
