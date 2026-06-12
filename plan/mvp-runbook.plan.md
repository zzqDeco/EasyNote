# MVP Runbook

## Summary

- Capture the current EasyNote development, validation, PR review, and merge workflow in a stable runbook.
- Retire the UI smoke/accessibility plan from Active status now that PR #8 has shipped to `dev`.
- Refresh public/local-first MVP wording after the repository visibility changed to public.

## Scope

- Add `doc/mvp-runbook.md` as the operating guide for branch work, CI checks, Codex review loops, and smoke validation.
- Update `README.md`, `doc/README.md`, `doc/branching.md`, `doc/mvp-acceptance.plan.md`, and `plan/README.md`.
- Do not change Swift source, tests, CI workflow behavior, or branch protection.

## Implementation

- Document the standard path: topic branch from `dev`, PR into `dev`, promotion PR from `dev` to `main`.
- Document the review loop contract: trigger `@codex review`, set a 10-minute heartbeat, inspect thread-aware comments, fix only verified severe issues, then delete the heartbeat at clean state.
- Document CI handling for public GitHub-hosted macOS runners, failed-job reruns, and local Xcode runtime mismatch.
- Keep manual smoke coverage tied to the existing MVP acceptance checklist.

## Test Plan

- `git diff --check`
- Markdown relative link sanity check over `README.md`, `doc/`, and `plan/`
- Secret scan for high-confidence token/private-key patterns
- PR CI remains the source of truth for `EasyNoteTests`

## Assumptions

- This PR is documentation-only and targets `dev`.
- Hosted UI tests remain non-blocking; GitHub CI continues to block only on `EasyNoteTests`.
- Promotion to `main` happens in a separate PR after this runbook lands in `dev`.
