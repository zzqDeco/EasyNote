# .github/workflows/ui-smoke.yml

## Responsibility

- Provide a manually dispatched hosted UI smoke workflow for EasyNote.
- Run launch and primary-tab navigation UI tests without making them required PR checks.

## Boundaries

- Do not replace the default `CI` unit-test gate.
- Do not run destructive UI flows, microphone flows, network-dependent AI flows, or API-key-dependent checks.
- Do not store secrets in this workflow.

## Behavior Notes

- The workflow runs only through `workflow_dispatch`.
- It uses `macos-15`, lists the Xcode project, discovers an available iPhone simulator, and runs the two stable UI smoke tests.
- UI-test process isolation is provided by `EasyNoteUITests` launch arguments and `EasyNoteApp` test-mode handling.

## Tests

- Validate YAML syntax locally after changes.
- Dispatch the workflow manually when hosted UI runner behavior needs verification.
