# EasyNote Plan Index

`plan/` stores active implementation plans and short records for recently delivered work. Current system behavior belongs in [doc/](../doc/README.md); plans should stay implementation-oriented and retire once stable behavior is absorbed into current-state documentation.

Use [the implementation plan template](templates/implementation-plan.template.md) for new work and [the delivered plan template](templates/delivered-plan.template.md) when converting shipped work into a short record.

## Status Definitions

- `Active`: work is still being designed, implemented, or used as a live decision source.
- `Delivered`: work has shipped, but the record is still useful for release notes, review context, or branch archaeology.
- `Absorbed`: stable behavior has moved into `doc/`; the plan can usually be removed in a docs cleanup.
- `Retire Candidate`: old or duplicated plan that should be deleted once links and docs are checked.

## Active References

| Document | Purpose | Status |
|---|---|---|

## Delivered Or Recent References

| Document | Purpose | Status |
|---|---|---|
| [cloudkit-sync-preflight.plan.md](cloudkit-sync-preflight.plan.md) | Make future CloudKit enablement prerequisites explicit without enabling real sync | Delivered |
| [ui-ci-stabilization.plan.md](ui-ci-stabilization.plan.md) | Add UI-test launch isolation and a manual hosted UI smoke workflow | Delivered |
| [service-injection-seams.plan.md](service-injection-seams.plan.md) | Add narrow service protocols and initializer injection seams for ViewModels and Settings | Delivered |
| [ai-workflow-history.plan.md](ai-workflow-history.plan.md) | Add current-session AI result history with apply/copy/discard confirmation | Delivered |
| [diary-review-insights.plan.md](diary-review-insights.plan.md) | Add local diary review projections and read-only insights UI | Delivered |
| [local-export-backup.plan.md](local-export-backup.plan.md) | Add local JSON backup and restore with voice recording assets | Delivered |
| [mvp-runbook.plan.md](mvp-runbook.plan.md) | Capture the MVP development, validation, review, and promotion workflow | Delivered |
| [ui-smoke-and-accessibility.plan.md](ui-smoke-and-accessibility.plan.md) | Add stable accessibility identifiers and local non-destructive UI smoke coverage | Delivered |
| [speech-diary-flow.plan.md](speech-diary-flow.plan.md) | Make speech transcription a permission-aware explicit diary draft input flow | Delivered |
| [ai-parser-and-settings-hardening.plan.md](ai-parser-and-settings-hardening.plan.md) | Extract AI parsing into tested helpers and harden empty-key settings behavior | Delivered |
| [todo-focus-view.plan.md](todo-focus-view.plan.md) | Add focused todo category views and remove duplicated todo CRUD from ExploreViewModel | Delivered |
| [diary-search-filter.plan.md](diary-search-filter.plan.md) | Add stable diary search, filtering, and sort behavior without mutating source entries | Delivered |
| [local-core-reliability.plan.md](local-core-reliability.plan.md) | Tighten local ViewModel context binding, save failures, and recurring todo completion | Delivered |
| [project-structure-bootstrap.plan.md](project-structure-bootstrap.plan.md) | Align EasyNote with the user's branch, doc, plan, and PR workflow conventions | Delivered |
| [basic-ci.plan.md](basic-ci.plan.md) | Add the first GitHub Actions CI gate for Xcode project listing and tests | Delivered |

## Maintenance Rules

- Add or update a plan before implementing feature, fix, refactor, or behavior changes that need design review.
- Update this index in the same change that adds, absorbs, or retires a plan.
- Move stable behavior summaries into `doc/` after a plan ships.
- Mark old plans `Absorbed` or `Retire Candidate` before deleting them, unless the deletion is part of a dedicated docs cleanup.
- Do not duplicate long architecture explanations here; link to the relevant current-state document instead.
