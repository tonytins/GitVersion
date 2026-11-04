# Project Guidelines

## Project structure

GitVersion is a Swift package that provides Git metadata through a SwiftPM
build-tool plugin. The public API lives in `Sources/GitVersion`, the plugin in
`Plugins/GitVersionPlugin`, and its generator in `Sources/GitVersionGenerator`,
with the generator's logic in the internal `Sources/GitVersionGeneratorCore`
target. `Tests/GitVersionTests` covers the library API and the generator's
logic, using real temporary Git repositories.

## Build and test

- Build with `swift build`.
- Run the test suite with `swift test`.
- When changing the plugin or generator, verify it with a consuming package in a
  Git repository as well as running the package tests.

## Swift and Git metadata

- Follow the package's Swift tools version and existing naming and formatting.
- Keep public APIs clear at the call site and document public behavior where
  names alone are not sufficient.
- Keep generated source deterministic and valid Swift. Escape repository
  values as Swift literals rather than interpolating them as code.
- Use Git commands with explicit arguments and report failures that prevent
  metadata from being collected. A repository that exists but cannot be read,
  including a shallow clone, must fail the build. Do not substitute plausible
  metadata for it.
- A build with no repository is the one exception. It succeeds with a warning,
  a version visibly marked `+unknown`, and `nil` repository fields. Never report
  placeholder commits or branches. `GITVERSION_VERSION` replaces all repository
  metadata when set.
- Preserve behavior for tagged and untagged commits, detached checkouts, CI
  branch names, and dirty working trees. Add focused tests for version
  calculation and validate plugin behavior in an actual consumer build.
- Base the version on the closest reset on the first-parent history: a semantic
  version tag or a commit that changed `GitVersion.txt`, with the tag winning on
  the same commit. Increment the patch by first-parent commits since that reset.
  Count first-parent merge commits, not commits reachable only through other
  merge parents. When `GitVersion.txt` is below the repository root, count only
  commits that changed its directory.
- Keep generated metadata internal to the consuming target, and never compile
  credentials or local paths from a remote URL into it.
- Expose semantic-version components and both abbreviated and full commit
  identifiers in generated metadata.
- Update `README.md` when package setup, generated API, or version behavior
  changes.

See [REVIEW.md](REVIEW.md) for the project's review checklist.

## Personal configuration

Keep personal preferences and machine-specific guidance in git-ignored
`*.local` files or directories, rather than in shared project instructions.
Check for relevant local guidance before environment-specific work. You can use
these files for coding preferences, local build setup, or personal workflows.
