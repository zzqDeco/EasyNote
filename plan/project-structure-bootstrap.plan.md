# Project Structure Bootstrap Plan

Status: Delivered

## Goal

Align EasyNote with the user's other active repositories by adding a lightweight branch workflow, documentation entry point, implementation plan index, and GitHub collaboration templates.

## Current State

- `main` contains the private prototype consolidation.
- The repository did not yet have `dev`, `doc/`, `plan/`, `AGENTS.md`, or GitHub PR/task templates.
- The project is still an iOS prototype, so CI and release automation remain intentionally deferred until simulator/runtime and signing assumptions are stable.

## Implementation

- Add `AGENTS.md` with project shape, branch naming, commit style, documentation sync rules, and review checklist.
- Add `doc/README.md` plus `doc/branching.md` for current branch workflow and validation expectations.
- Add `plan/README.md`, plan templates, and this delivered bootstrap record.
- Add `.github/pull_request_template.md` and `.github/ISSUE_TEMPLATE/project_task.md`.
- Create and push `dev` as the integration branch while keeping GitHub default branch on `main`.

## Acceptance

- `dev` exists locally and remotely.
- `main` remains stable and unchanged by routine future work until an integration merge is explicitly chosen.
- `doc/README.md` and `plan/README.md` link only to files that exist.
- `git diff --check` passes.
