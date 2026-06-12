# EasyNote MVP Runbook

This runbook is the operating guide for the public, local-first EasyNote MVP. It covers branch work, verification, Codex review loops, CI recovery, and promotion from `dev` to `main`.

## Branch Model

- `main` is the stable branch.
- `dev` is the integration branch.
- Routine work starts from latest `dev` and opens a PR back into `dev`.
- Promotion work starts from latest `dev` and opens a PR into `main`.
- Do not push routine changes directly to `main` or `dev`.

Topic branch prefixes:

- `feature/*` for user-visible behavior
- `fix/*` for defects
- `docs/*` for documentation-only changes
- `refactor/*` for internal structure
- `test/*` for verification harnesses
- `ci/*` for workflow changes
- `chore/*` for maintenance and promotion

## PR Flow

1. Start clean:

   ```bash
   git switch dev
   git pull --ff-only origin dev
   git status --short --branch
   ```

2. Create a focused topic branch:

   ```bash
   git switch -c <type>/<slug>
   ```

3. Add or update a plan before non-trivial implementation:

   - Use `plan/templates/implementation-plan.template.md`.
   - Mark the new plan `Active` in `plan/README.md`.
   - Move shipped active plans to `Delivered` in the same PR when appropriate.

4. Keep docs synchronized:

   - Update `README.md` for user-visible setup, limitations, or behavior.
   - Update `doc/` for stable current-state contracts.
   - Update `doc/src/` when important source ownership or test boundaries change.

5. Validate locally before PR:

   ```bash
   git diff --check
   xcodebuild -list -project EasyNote.xcodeproj
   ```

   For Swift changes, run `xcodebuild test` when a compatible local simulator runtime is installed.

6. Open the PR with:

   - Summary
   - Test Plan
   - Known Local Limitation
   - Docs Updated

## Codex Review Loop

Every PR must run the same review loop before merge readiness.

1. Trigger review:

   ```bash
   gh pr comment <pr-number> --body "@codex review"
   ```

2. Create one 10-minute heartbeat named `watch-easynote-pr-<number>-review-comments`.

3. On each loop, inspect:

   ```bash
   gh pr view <pr-number> --json number,url,headRefName,headRefOid,baseRefName,mergeStateStatus,reviewDecision,statusCheckRollup
   gh pr view <pr-number> --json reviews,comments
   python3 /Users/zhaoziqian/.codex/plugins/cache/openai-curated/github/c6ea566d/skills/gh-address-comments/scripts/fetch_comments.py --repo zzqDeco/EasyNote --pr <pr-number>
   ```

4. If the latest head has no completed Codex review and no very recent pending request, comment `@codex review` again.

5. For review feedback:

   - Treat P1/P2, requested changes, data loss, crashes, secrets, CI failures, or core feature breakage as serious.
   - Verify each serious-looking comment against current code, PR diff, CI logs, or local checks before editing.
   - Do not fix speculative, outdated, duplicate, already-addressed, non-serious, or behavior-regressing comments.
   - After a real severe fix, run the PR checks, commit, push, and trigger `@codex review` again.

6. Clean state requires:

   - latest head CI green
   - completed Codex review for latest head
   - no unresolved, non-outdated, verified severe actionable comments

7. Delete or pause the heartbeat after clean state. Do not merge until the user explicitly says `合并`.

## CI Recovery

EasyNote CI runs on `macos-15` and blocks on `EasyNoteTests`.

Use:

```bash
gh pr checks <pr-number> --watch
gh run view <run-id> --json status,conclusion,jobs,url
gh run view <run-id> --log
```

For failed GitHub Actions jobs, rerun failed jobs only:

```bash
gh run rerun <run-id> --failed
```

Public repositories using standard GitHub-hosted runners do not consume included private-repo minutes. Private repositories consume account minutes and can be blocked by billing or spending limits. If a job does not start and the log mentions billing or spending limits, treat it as an account/runner availability issue before changing code.

Sources:

- [GitHub Actions workflow syntax: standard runners for public repositories](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
- [GitHub Actions usage limits and billing](https://docs.github.com/en/actions/learn-github-actions/usage-limits-billing-and-administration)
- [Re-running workflows and jobs](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs)

## Local Xcode Runtime Mismatch

Local command-line tests require an installed simulator runtime compatible with the active Xcode SDK.

If local `xcodebuild test` fails with a destination/runtime error such as missing iOS 26.5, record the exact error and do not report local tests as passing. Use these checks instead:

```bash
git diff --check
xcodebuild -list -project EasyNote.xcodeproj
xcodebuild -showdestinations -project EasyNote.xcodeproj -scheme EasyNote
```

GitHub CI remains the source of truth for the blocking unit-test gate when local runtime mismatch blocks simulator execution.

## Manual Smoke Checklist

Before promoting `dev` to `main`, manually verify the MVP where local runtime/device access allows:

- create and edit a diary entry
- search and filter diaries, then clear filters
- create and complete a todo
- complete a recurring todo once and confirm the next instance
- switch todo focus segments
- create a todo from a recommendation
- configure and clear the DeepSeek API key
- start AI actions with an empty key and confirm a user-visible error
- record speech on a real device or compatible simulator
- insert and replace transcription explicitly
- deny speech or microphone permission and confirm typed content is preserved
- launch the app and navigate the four primary tabs with UI smoke identifiers

## Promotion To Main

Only promote after `dev` is clean.

1. Create promotion branch from latest `dev`:

   ```bash
   git switch dev
   git pull --ff-only origin dev
   git switch -c chore/promote-local-mvp-to-main
   ```

2. Open PR to `main`.

3. Do not add features or opportunistic fixes.

4. Run the same CI and Codex review loop.

5. Merge only after the user explicitly says `合并`.
