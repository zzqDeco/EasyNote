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
| [project-structure-bootstrap.plan.md](project-structure-bootstrap.plan.md) | Align EasyNote with the user's branch, doc, plan, and PR workflow conventions | Delivered |

## Maintenance Rules

- Add or update a plan before implementing feature, fix, refactor, or behavior changes that need design review.
- Update this index in the same change that adds, absorbs, or retires a plan.
- Move stable behavior summaries into `doc/` after a plan ships.
- Mark old plans `Absorbed` or `Retire Candidate` before deleting them, unless the deletion is part of a dedicated docs cleanup.
- Do not duplicate long architecture explanations here; link to the relevant current-state document instead.
