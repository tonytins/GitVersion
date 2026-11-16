# Review Guide

Use this checklist when reviewing a change to GitVersion. It is adapted from the
contributor and review practices in [NVIDIA FLARE's contribution guide](https://github.com/NVIDIA/NVFlare/blob/main/CONTRIBUTING.md),
by way of [Hudini](https://github.com/tonytins/Hudini), with checks tailored to
this Swift package and build-tool plugin. The rules it checks against are in
[AGENTS.md](AGENTS.md).

## Before Reviewing

- Read the change description and the relevant code and tests.
- Identify the metadata or versioning behavior the change is intended to
  address, including any documented GitInfo behavior it aims to match.
- Check available build, test, and CI results. Run `swift build` or `swift test`
  when the change or its verification warrants it; for plugin or generator
  changes, also build a consuming package inside a Git repository. Report checks
  that could not be run.

## Review Checklist

- Does generated metadata match the current repository state for a clean
  checkout, a dirty working tree, a tagged commit, an untagged commit, and a
  detached checkout?
- Does the patch advance from the closest reset, either a semantic version tag
  or a `GitVersion.txt` change, using first-parent history, counting merge
  commits but excluding commits reachable only through other merge parents?
- Are branch names, tags, and semantic-version components parsed and normalized
  without producing invalid or misleading version strings?
- Does the plugin declare the correct generated output and rebuild when
  repository metadata changes, including in worktrees, submodules, and packages
  below the repository root?
- Are major, minor, and patch consistent with the generated semantic version,
  and are both abbreviated and full commit identifiers correct?
- Is generated Swift valid and safely escaped for unusual branch, tag, or remote
  values, and is it left untouched when the metadata has not changed?
- Are Git command failures, shallow clones, and invalid `GitVersion.txt` contents
  surfaced clearly instead of yielding success-shaped fallback metadata? Is a
  build with no repository the only fallback, and is it marked `+unknown` with a
  warning?
- Can repository contents reach a trap? Check `!`, `try!`, `as!`, string
  indexes and slices, and integer arithmetic; malformed values must produce a
  `GeneratorError`, not a crash.
- Is the generated API still internal, and are credentials and local paths kept
  out of the repository URL?
- Are public API names, documentation, and defaults clear and consistent with
  the package's intended behavior?
- Does the change follow the package's Swift tools version and existing naming
  and formatting, and avoid unnecessary public API changes?
- Do focused tests cover the changed behavior, and is an actual consumer build
  needed in addition to headless tests?

## Writing Review Comments

- Report concrete correctness, compatibility, reliability, or missing-test
  concerns; do not block changes on personal style preferences.
- Make each comment specific, constructive, and actionable. Point to the
  smallest relevant location and explain the impact and a useful next step.
- Prioritize findings by impact:
  - **Blocking**: prevents the package from building or causes severe,
    unavoidable failure in normal use, or reports metadata that is silently
    wrong.
  - **High**: breaks an existing public behavior or a common package workflow,
    or leaves a metadata or version boundary unvalidated.
  - **Medium**: causes a limited but meaningful behavior or reliability issue, or
    leaves docs describing something that isn't true.
  - **Low**: a small edge case or non-blocking improvement.
- If no actionable issues remain, say so and note any important checks that
  were not run.
