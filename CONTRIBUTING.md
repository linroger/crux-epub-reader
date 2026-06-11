# Contributing to Crux

Thanks for your interest in helping out. Crux is a SwiftUI EPUB reader
with AI-powered passage explication targeting macOS 14+ and iOS 17+.
This document covers what you need to know to land a change cleanly.

If you're looking for the layered architecture overview — where code
lives, how layers depend on each other, what touches what — read
[ARCHITECTURE.md](ARCHITECTURE.md) first.

---

## Development environment

| Tool             | Version          | Why                                  |
|------------------|------------------|--------------------------------------|
| Xcode            | 26.x             | Liquid Glass APIs, Swift 6.2 toolchain |
| macOS SDK        | 26.2 (deployment 14.0) | Targets macOS 14+ and iOS 17+ |
| xcodegen         | 2.x              | Project file is generated, not hand-edited |
| Swift            | 5.9+ language mode (toolchain ships 6.2) | Project setting |

Install xcodegen via Homebrew:

```bash
brew install xcodegen
```

There are no other external dependencies — the only SPM package is
[`swift-markdown-ui`](https://github.com/gonzalezreal/swift-markdown-ui),
pinned in `project.yml`.

---

## First-time setup

```bash
git clone <repo>
cd crux
xcodegen generate                        # regenerates Crux.xcodeproj from project.yml
open Crux.xcodeproj                      # or build from CLI (below)
```

`Crux.xcodeproj` is **checked in** so the project opens out of the box,
but anytime you add or rename a source file you should re-run
`xcodegen generate` to keep the pbxproj in sync. The `Shared/` directory
is folder-globbed, so new files in subdirectories pick up automatically
once regenerated.

---

## Build & test from the command line

```bash
# Build the macOS target.
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' build

# Run the unit-test suite.
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' test

# Build the iOS target on the simulator.
xcodebuild -scheme Crux_iOS \
  -destination 'platform=iOS Simulator,name=iPhone 16,OS=latest' build
```

If SPM has trouble fetching `swift-markdown-ui` (intermittent GitHub
connectivity), you can point `xcodebuild` at a pre-cached package
checkout:

```bash
xcodebuild -scheme Crux_macOS -destination 'platform=macOS' \
  -clonedSourcePackagesDirPath /tmp/spm-checkouts \
  -skipPackagePluginValidation \
  -disableAutomaticPackageResolution build
```

---

## Code conventions

* **SwiftUI views go in `Shared/Views/`** (or a topic subdirectory like
  `Shared/Views/Library/`, `Shared/Views/Reader/`). Keep views under
  ~250 lines — extract subviews aggressively. `LibraryView` and
  `ReaderView` are exceptions tracked in IMPROVEMENTS.md for further
  decomposition.
* **Services go in `Shared/Services/`.** Long-lived state lives in
  `actor`s; UI-bound state uses `@MainActor @Observable`.
* **No `print()`** — use `AppLog` (`Shared/Services/AppLog.swift`)
  with the appropriate category channel (`parser`, `ai`, `storage`,
  `security`, `errors`, `data`, `reader`, `ui`).
* **API keys live in Keychain.** Never persist a credential through
  SwiftData / UserDefaults — go through `KeychainService`.
* **Liquid Glass adoption** goes through the shim modifiers in
  `Shared/Views/LiquidGlass.swift` (`cruxGlassCard`, `cruxGlassBar`,
  etc.) so the macOS 14 deployment target stays viable.
* **Comments explain "why," not "what."** A surprising invariant,
  a workaround for a known bug, or a non-obvious design tradeoff is
  worth a comment. Code that names itself well doesn't need one.

---

## Adding things

`ARCHITECTURE.md` ends with a "Where to add things" cheatsheet — use it
as a quick reference for the most common extensions (new AI provider,
new reader chrome control, new annotation field, new export format,
new prompt preset).

### Tests

Tests live in `Tests/` and use `XCTest`. Each new service or value type
should ship at least one test file covering the primary success path
and any non-trivial edge cases. We deliberately keep the suite small
and fast — favor scenario tests over exhaustive permutations.

Naming: `<SubjectUnderTest>Tests.swift` (e.g.,
`CitationFormatterTests.swift`). Test methods use the
`test_<scenario>_<expectedOutcome>` pattern when the structure helps,
or just `testSomething()` for simple cases.

---

## Commit messages

Short imperative subject (under 70 chars), followed by a blank line and
a body that explains *why*. Reference the IMPROVEMENTS.md item ID when
relevant:

```
Implement 2.1 CFI-precise position restoration

viewport-tracker.js now emits an element-level CFI; ReaderView
prefers it over scroll-percentage on reopen so users land on the
exact paragraph they were reading.
```

Don't bundle unrelated changes in a single commit. Bundle the
implementation + its tests + its documentation updates in **one**
commit (so the diff tells a coherent story).

---

## Pull-request checklist

Before opening a PR:

- [ ] `xcodebuild ... build` succeeds with no new warnings.
- [ ] `xcodebuild ... test` passes (or you've documented why a test is
      deliberately skipped).
- [ ] `xcodegen generate` ran after any file additions/renames; the
      pbxproj is in the diff.
- [ ] `handoff.md` updated if your change affects ongoing work or
      decisions.
- [ ] `IMPROVEMENTS.md` updated when you complete or update an item.
- [ ] No `print()` calls left behind.
- [ ] No commented-out code or `TODO:` placeholders that won't be
      addressed in this PR.

---

## Questions?

`handoff.md` is the running narrative; check there for recent decisions
and in-flight work before starting something that touches the same
seams.
