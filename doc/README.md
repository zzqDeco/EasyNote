# EasyNote Documentation

This directory keeps current project documentation. It should describe how EasyNote works now, not preserve every historical planning detail.

## Start Here

- [Architecture](architecture.plan.md): SwiftUI, SwiftData, service, ViewModel, and sync/AI boundaries.
- [Interfaces](interfaces.plan.md): persistence models, local settings keys, AI request contract, and CloudKit boundary.
- [MVP Acceptance](mvp-acceptance.plan.md): local and CI validation matrix for the current prototype.
- [Branching And Workflow](branching.md): branch roles, topic branch naming, PR expectations, and release flow.
- [Source Notes](src/README.md): short source-boundary notes organized to mirror repository paths.
- [Documentation Template](templates/documentation.template.md): template for new current-state docs under `doc/`.
- [Source Note Template](templates/source-note.template.md): template for source notes under `doc/src/`.

## Documentation Rules

- Keep product-facing setup and usage in `README.md`.
- Keep current engineering contracts in `doc/`.
- Keep active or recently delivered implementation plans in `plan/`.
- Use templates when adding new docs or source notes.
- Update this index in the same change that adds, retires, or moves a document.
- Prefer concise current-state documentation over long historical narratives.
- When behavior changes, update the narrowest relevant document and link out instead of duplicating the same explanation everywhere.
- For documentation-only cleanup, run at least `git diff --check`.

## Related Project Files

- [AGENTS.md](../AGENTS.md): coding-agent rules, branch naming, review checklist, and documentation sync requirements.
- [plan/README.md](../plan/README.md): index of implementation plans and recently delivered records.
