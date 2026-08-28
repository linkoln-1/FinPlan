# Contributing to FinPlan

Thank you for considering a contribution. This document explains how the
project is organised, how to get a working build, and what a pull request
needs before it can be merged.

## Table of contents

- [Prerequisites](#prerequisites)
- [Getting the code](#getting-the-code)
- [Building and testing](#building-and-testing)
- [Development workflow](#development-workflow)
- [Branch naming](#branch-naming)
- [Commit messages](#commit-messages)
- [Pull request requirements](#pull-request-requirements)
- [Code style](#code-style)
- [Financial correctness](#financial-correctness)
- [Data safety rules](#data-safety-rules)
- [Reporting issues](#reporting-issues)
- [Reporting security problems](#reporting-security-problems)

## Prerequisites

- macOS with **Xcode 26** or newer (Swift 6.0 toolchain)
- **XcodeGen** — `brew install xcodegen`
- An iOS 18+ simulator (installed with Xcode)

No third-party Swift packages are used; the only dependency is the local
`Packages/FinPlanCore` package.

## Getting the code

```bash
git clone https://github.com/linkoln-1/FinPlan.git
cd FinPlan
xcodegen generate
open FinPlan.xcodeproj
```

`FinPlan.xcodeproj` is generated from `project.yml` and is git-ignored.
Re-run `xcodegen generate` whenever `project.yml` changes or files are added
or removed. Never edit the generated project by hand.

## Building and testing

The domain package has no UI dependencies and runs on macOS directly:

```bash
cd Packages/FinPlanCore
swift test
```

The app target builds and tests on the iOS simulator:

```bash
xcodebuild -project FinPlan.xcodeproj -scheme FinPlan \
  -destination 'platform=iOS Simulator,name=iPhone 17' \
  CODE_SIGNING_ALLOWED=NO test
```

`scripts/ci.sh` runs exactly what CI runs (project generation, core tests,
app build and tests) and picks an available simulator automatically:

```bash
./scripts/ci.sh
```

## Development workflow

`main` is protected. Nothing is pushed to it directly — every change, including
maintainer changes, goes through a pull request that passes CI.

```
main
 ↑  pull request (CI green, conversations resolved)
feature/* · fix/* · refactor/* · docs/* · test/* · chore/*
```

```bash
git switch main
git pull
git switch -c feature/short-description
# ... work, commit ...
git push -u origin feature/short-description
gh pr create
```

Pull requests are squash-merged, so a branch may contain as many commits as
you like; the PR title and description become the commit on `main`.

## Branch naming

| Prefix       | Use for                                   |
|--------------|-------------------------------------------|
| `feature/`   | New functionality                          |
| `fix/`       | Bug fixes                                  |
| `refactor/`  | Behaviour-preserving restructuring         |
| `docs/`      | Documentation only                         |
| `test/`      | Tests only                                 |
| `chore/`     | Tooling, CI, project configuration         |

## Commit messages

Use the imperative mood and keep the subject under ~72 characters:

```
Add month-end pinning to RecurringScheduler
Fix savings-rate rounding for zero income
```

Conventional prefixes (`feat:`, `fix:`, `docs:` …) are welcome but not
required.

## Pull request requirements

A pull request is ready for review when:

- [ ] It builds without warnings introduced by the change
- [ ] `swift test` in `Packages/FinPlanCore` passes
- [ ] The app test target passes on the simulator
- [ ] New behaviour in `FinPlanCore` is covered by tests
- [ ] Financial invariants in [docs/FINANCIAL_MODEL.md](docs/FINANCIAL_MODEL.md) still hold
- [ ] No secrets, credentials or personal financial data are included
- [ ] User-facing strings are added to both `en` and `ru` in the String Catalog
- [ ] Accessibility (labels, Dynamic Type) is considered for new UI
- [ ] Documentation is updated when behaviour or setup changes

Small, focused pull requests are reviewed faster than large ones.

## Code style

The project uses native Swift conventions and does not run a formatter or
linter in CI. Please follow the surrounding code:

- Four-space indentation, no trailing whitespace, one trailing newline
- `PascalCase` types, `camelCase` members, `UPPER_SNAKE_CASE` is not used
- Prefer value types, `let`, and immutable updates
- Swift 6 strict concurrency is enabled — keep types `Sendable` where the
  compiler asks for it; do not silence warnings with `@unchecked` without a
  justification in the PR description
- Avoid force unwraps and `try!` in production code
- No `print`/`debugPrint` in production code
- Debug-only code (previews, demo seeds, launch arguments) lives inside
  `#if DEBUG`

**Comments.** Prefer self-documenting code. Comments should explain
non-obvious constraints, invariants or external behaviour, not narrate what
the code does. Architecture and financial rules belong in `docs/`, not in
inline comments.

## Financial correctness

`FinPlanCore` is the only place where money is calculated. Views, view models
and persistence code call the engines; they never re-implement arithmetic.
Before touching an engine, read [docs/FINANCIAL_MODEL.md](docs/FINANCIAL_MODEL.md).
Every rule described there has a corresponding test — if you change a rule,
change the document and the test in the same pull request.

## Data safety rules

This is a finance app. Please observe the following without exception:

- **Never commit financial exports**, databases, backups or simulator data.
- **Never commit secrets** — API keys, tokens, certificates, provisioning
  profiles, `.env` files.
- **Never include personal financial data in fixtures.** Test data, previews
  and demo seeds must be obviously synthetic.
- **Never paste real account data into issues or pull requests.**

## Reporting issues

Use the issue templates. A good bug report includes the app version or commit,
iOS version, device or simulator, exact steps, expected and actual results.
Please strip any real amounts, names and notes from screenshots and logs.

## Reporting security problems

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).
