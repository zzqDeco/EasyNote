# .github/workflows/ci.yml

## Responsibility

- Provide the minimum GitHub Actions CI gate for EasyNote.
- Verify repository whitespace, Xcode project readability, simulator availability, and focused unit tests.

## Boundaries

- Do not sign, archive, notarize, publish releases, or enable CloudKit in this workflow.
- Do not store secrets in CI for the current prototype.

## Behavior Notes

- The workflow runs on pushes to `main`, `dev`, and topic branches, and on PRs into `main` or `dev`.
- It uses `macos-15` and keeps the hosted runner's default Xcode/runtime pairing.
- It discovers an available iPhone simulator dynamically and passes the simulator UDID to `xcodebuild test -only-testing:EasyNoteTests`.
- `CODE_SIGNING_ALLOWED=NO` is used for simulator test builds.
- UI tests are retained in the repository but are not part of the first blocking CI gate.

## Tests

- Local YAML syntax is checked with Ruby's YAML parser.
- CI success is the authoritative proof that hosted Xcode/runtime assumptions are still valid.
