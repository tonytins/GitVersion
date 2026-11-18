# GitVersion Changelog

## 0.3.2

- **`GITVERSION_IGNORE_TAG_VERSION` skips tags**, so the version file alone sets
  the base, as GitInfo's `GitIgnoreTagVersion` does. The tag on `HEAD` is still
  reported.
- **`GitVersion.env` keeps switches with the repository.** It holds
  `GITVERSION_IGNORE_TAG_VERSION`, `GITVERSION_IGNORE_BRANCH_VERSION`, and
  `GITVERSION_ABBREV` as `NAME=value` lines, found like a version file, so every
  build gets them. The environment wins over the file, and anything else in it
  fails the build.

## 0.3.1

- **`GitInfo.txt` is read as a version file.** Projects coming from GitInfo can
  keep their existing file. It follows the same rules as `GitVersion.txt`, which
  wins when both are in the same directory.

## 0.3.0

- **Base versions follow a strict cascade.** GitVersion now reads a version from
  the branch name, then the nearest semantic version tag on first-parent
  history, then `GitVersion.txt`, and finally the default `0.1.0`. The version
  file no longer overrides a tag, so tags serve as release boundaries instead of
  bookkeeping to make a version stick.
- **Version branches count from their fork point.** A branch such as
  `release/1.2.3` uses the text after the last `/` as its base and counts commits
  since the branch forked from the default branch. When GitVersion cannot find
  that fork point, it reports a warning and uses the tag or file instead.
  `GITVERSION_IGNORE_BRANCH_VERSION` disables the branch source.
- **Monorepos count each package separately.** Counting is limited to one scope:
  the directory of the found version file, otherwise the package directory when
  below the repository root, otherwise the whole repository. The default version
  starts at the first commit that touched that scope.
- **The version grammar is more permissive.** Optional `v`/`V`, two-part
  versions (`1.2` becomes `1.2.0`), trailing labels (`1.2-preview`), leading
  labels (`preview-1.2.3` becomes `1.2.3-preview`), and path-prefixed tags
  (`release/v1.2.3`) are accepted. Build metadata remains limited to tags and
  `GITVERSION_VERSION`.
- **`GITVERSION_ABBREV` sets the commit abbreviation.** Defaults to 12 hex
  characters; accepts 4 to 40. Invalid values fail the build. The full commit
  hash remains 40 characters.
- **`.dirty` is removed from the version string.** Working tree changes no longer
  modify the generated version. `GitVersion.current.isDirty` remains available
  for release validation.
- **The demo is a separate package.** Moved to `Demo/` so it is not bundled as a
  product of the root package.

## 0.2.0

- **Generated metadata is internal.** Generated `GitVersion` types are scoped
  internally to each consuming target.
- **Closest reset on first-parent history.** Versions reset from the closest
  semantic version tag or `GitVersion.txt` commit on first-parent history.
- **Hierarchical version file search.** GitVersion searches upward from the
  package directory to the repository root.
- **Shallow clones fail explicitly.** Builds in shallow clones fail with a clear
  error rather than calculating an incorrect commit count.
- **Safe fallback without a repository.** Builds without a `.git` directory
  succeed with a warning, version suffix `+unknown`, and `nil` repository fields.
- **Comprehensive build inputs.** The build-tool plugin watches reflogs, packed
  refs, tags, HEAD, the index, and `GitVersion.txt`.
- **Sanitized repository URLs.** Local file paths and embedded credentials are
  stripped from remote URLs.

## 0.1.2

- **First-parent commit counting.** Commits are counted along the first-parent
  history, excluding side branch commits merged in.
- **Version components and full commit hash.** Exposed `major`, `minor`, `patch`,
  and `fullCommit` properties on `GitVersion`.

## 0.1.0

- **Initial release.** SwiftPM build-tool plugin generating `GitVersion` metadata
  snapshot during target builds.
