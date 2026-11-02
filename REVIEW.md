# Review Guide

Use this checklist when reviewing a change to GitVersion.

## Before reviewing

- Read the change description and the relevant code and tests.
- Identify the metadata or versioning behavior the change is intended to
  address, including any documented GitInfo behavior it aims to match.
- Check available build, test, and CI results. Run `swift build` or
  `swift test` when the change or its verification warrants it; for plugin or
  generator changes, also build a consuming package inside a Git repository.
  Report checks that could not be run.

## Review checklist

- Does generated metadata match the current repository state for a clean
  checkout, a dirty working tree, a tagged commit, an untagged commit, and a
  detached checkout?
- Are branch names, tags, and semantic-version components parsed and normalized
  without producing invalid or misleading version strings?
- Does the plugin declare the correct generated output and rebuild when
  repository metadata changes?
- Is generated Swift valid and safely escaped for unusual branch, tag, or remote
  values?
- Are Git command failures and invalid `GitVersion.txt` contents surfaced
  clearly instead of yielding success-shaped fallback metadata?
- Are public API names, documentation, and defaults clear and consistent with
  the package's intended behavior?
- Do focused tests cover the changed behavior, and is an actual consumer build
  needed in addition to headless tests?

## Writing review comments

- Report concrete correctness, compatibility, reliability, or missing-test
  concerns; do not block changes on personal style preferences.
- Make each comment specific, constructive, and actionable. Point to the
  smallest relevant location and explain the impact and a useful next step.
- Prioritize findings by impact:
  - **Blocking**: prevents the package from building or causes severe,
    unavoidable failure in normal use.
  - **High**: breaks an existing public behavior or a common package workflow.
  - **Medium**: causes a limited but meaningful behavior or reliability issue.
  - **Low**: a small edge case or non-blocking improvement.
- If no actionable issues remain, say so and note any important checks that
  were not run.
