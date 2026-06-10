# EasyNote Documentation

This directory stores current engineering documentation for EasyNote. It should describe how the project works now, not preserve every historical planning detail.

## Start Here

- [Branching And Workflow](branching.md): branch roles, topic branch naming, PR expectations, and release flow.

## Documentation Rules

- Keep product-facing setup and usage in `README.md`.
- Keep current engineering contracts in `doc/`.
- Keep active or recently delivered implementation plans in `plan/`.
- Update this index in the same change that adds, retires, or moves a document.
- Prefer concise current-state documentation over long historical narratives.
- For documentation-only cleanup, run at least `git diff --check`.

## Related Project Files

- [AGENTS.md](../AGENTS.md): coding-agent rules, branch naming, review checklist, and documentation sync requirements.
- [plan/README.md](../plan/README.md): index of implementation plans and recently delivered records.
