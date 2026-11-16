# Project Guidelines

GitVersion is a SwiftPM build-tool plugin that makes Git repository metadata
available to Swift code. It generates a `GitVersion` namespace containing a
snapshot of the repository when SwiftPM builds a target, and is inspired by
[GitInfo](https://github.com/devlooped/GitInfo).

## Project Structure

| Path                                                    | Contents                                                          |
| ------------------------------------------------------- | ----------------------------------------------------------------- |
| `Sources/GitVersion/GitVersionInfo.swift`               | Public `GitVersionInfo` and `GitSemanticVersion` types.           |
| `Sources/GitVersionGenerator/main.swift`                | Generator executable: arguments, generated output, failures.      |
| `Sources/GitVersionGeneratorCore/RepositoryInfo.swift`  | Repository discovery, version calculation, CI branches, remotes.  |
| `Sources/GitVersionGeneratorCore/GeneratedSource.swift` | Renders the collected metadata as Swift source.                   |
| `Sources/GitVersionGeneratorCore/GitCommand.swift`      | Git process runner with a pinned environment.                     |
| `Sources/GitVersionGeneratorCore/SemanticVersion.swift` | Semantic-version parsing and precedence.                          |
| `Plugins/GitVersionPlugin/plugin.swift`                 | Build-tool plugin: declares inputs, output, and the command.      |
| `Sources/GitVersionDemo/main.swift`                     | Example executable that attaches the plugin.                      |
| `Tests/GitVersionTests/`                                | Library and generator tests over real temporary repositories.     |
| `GitVersion.txt`                                        | Base version used as a reset when it changes.                     |
| `README.md`                                             | User-facing setup, behavior, and version calculation docs.        |

## Build and Test

- Build with `swift build`.
- Run the test suite with `swift test`.
- When changing the plugin or generator, verify it with a consuming package in a
  Git repository as well as running the package tests.

## Golden Rules

### Design Process

- **Iterate**. A first design or name is a draft. Rebuild clumsy parts as understanding improves.
- **Ask when a decision is open**, and explain the reasoning behind what you suggest.
- **Keep it simple**. The simplest approach that matches what the plugin does wins.
- **Say what you're unsure of**: assumptions, unverified behavior, and what needs testing.

### Never Fabricate Metadata (Outranks Convenience)

GitVersion's output is compiled into users' binaries and shipped in releases, so
a plausible-looking wrong version is worse than a failed build. Accuracy outranks
convenience.

- **A repository that exists but cannot be read must fail the build**, including a
  shallow clone. Do not substitute plausible metadata for it.
- **The only fallback is a build with no repository.** It succeeds with a warning,
  a version visibly marked `+unknown`, and `nil` repository fields. Never report
  placeholder commits or branches. `GITVERSION_VERSION` replaces all repository
  metadata when set; an invalid value fails the build.
- **Report Git failures explicitly** on standard error and exit non-zero. Use Git
  commands with explicit arguments, and keep the environment pinned so hooks and
  inherited variables cannot redirect Git to another repository.
- **Never compile credentials or local paths** from a remote URL into generated
  metadata. Report `nil` for a remote on the local machine.
- **Treat any trap as a crash**: force unwrapping (`!`), `try!`, `as!`, an
  out-of-range index or slice, and unchecked integer arithmetic. Prefer
  `guard let`, failable lookups, and thrown `GeneratorError` values over
  assertions, which belong in tests.
- **Add a focused regression test** for every crash, malformed-input, or
  wrong-metadata fix.

### Version Calculation

- **Base the version on the closest reset on the first-parent history**: a
  semantic version tag or a commit that changed `GitVersion.txt`, with the tag
  winning on the same commit. Increment the patch by first-parent commits since
  that reset.
- **Count first-parent merge commits**, not commits reachable only through other
  merge parents.
- **When `GitVersion.txt` is below the repository root, count only commits that
  changed its directory**, so a package in a monorepo is not affected by its
  neighbors. Tags still apply to the whole repository.
- **With no reset at all, start from `0.1.0` at the first commit**, and preserve
  a prerelease label from the base version.
- **Parse and normalize branch names and tags** so the generated version is
  always valid semantic versioning, never invalid or misleading.
- **Expose semantic-version components and both abbreviated and full commit
  identifiers** in generated metadata.
- **Preserve behavior** for tagged and untagged commits, detached checkouts, CI
  branch names, and dirty working trees.

### Build Plugin and Generated Source

- **Keep generated metadata internal** to the consuming target. A library that
  wants to publish its version declares its own public API.
- **Declare every input that can change the metadata** — `HEAD`, the index,
  reflogs, packed refs, tag refs, and `GitVersion.txt` — so commits, branch
  switches, new tags, and staged changes trigger regeneration.
- **Handle worktrees and submodules**, whose `.git` is a file pointing at the real
  Git directory, and packages below the repository root.
- **Keep generated source deterministic and valid Swift.** Escape repository
  values as Swift literals rather than interpolating them as code, and do not
  rewrite the output when it has not changed.
- **Follow the package's Swift tools version and existing naming and formatting**,
  and keep public APIs clear at the call site with documentation where names
  alone are not sufficient.
- **Update `README.md`** when package setup, generated API, or version behavior
  changes.

## Personal Configuration

Keep personal preferences and machine-specific guidance in git-ignored `*.local` files or directories (such as `AGENTS.local.md`), rather than in shared project instructions. Check for relevant local guidance before environment-specific work. You can create or update these files for details such as:

- Coding preferences
- Local build and development environment
- Personal shortcuts or workflows

See [REVIEW.md](REVIEW.md) for the project's review checklist.
