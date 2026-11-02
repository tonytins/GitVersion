# Project Guidelines

## Project structure

GitVersion is a Swift package that provides Git metadata through a SwiftPM
build-tool plugin. The public API lives in `Sources/GitVersion`, the plugin in
`Plugins/GitVersionPlugin`, and its generator in `Sources/GitVersionGenerator`.
`Tests/GitVersionTests` covers the library API.

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
  metadata from being collected. Do not silently substitute plausible metadata
  for required repository information.
- Preserve behavior for tagged and untagged commits, detached checkouts, CI
  branch names, and dirty working trees. Add focused tests for version
  calculation and validate plugin behavior in an actual consumer build.
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
