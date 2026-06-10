# Project Structure Bootstrap Plan

Status: Delivered

## Goal

Align EasyNote with the user's other active repositories by adding a lightweight branch workflow, documentation entry point, implementation plan index, and GitHub collaboration templates.

## Current State

- `main` contains the private prototype consolidation.
- The repository did not yet have `dev`, `doc/`, `plan/`, `AGENTS.md`, or GitHub PR/task templates.
- The project is still an iOS prototype. Release automation remains deferred; the minimum CI gate is tracked separately in [basic-ci.plan.md](basic-ci.plan.md).

## Implementation

- Add `AGENTS.md` with project shape, branch naming, commit style, documentation sync rules, and review checklist.
- Add `doc/README.md`, current-state docs, source-note index, doc templates, and `doc/branching.md`.
- Add `plan/README.md`, plan templates, and this delivered bootstrap record.
- Add `.github/pull_request_template.md` and `.github/ISSUE_TEMPLATE/project_task.md`.
- Create and push `dev` as the integration branch while keeping GitHub default branch on `main`.

## Acceptance

- `dev` exists locally and remotely.
- `main` remains stable and unchanged by routine future work until an integration merge is explicitly chosen.
- `doc/README.md` and `plan/README.md` link only to files that exist.
- `doc/src/README.md` mirrors the important source boundaries instead of acting as generic placeholder documentation.
- `git diff --check` passes.
