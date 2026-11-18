# GitVersion

GitVersion is a SwiftPM build-tool plugin that makes Git repository metadata
available to Swift code. It generates a `GitVersion` namespace containing a
snapshot of the repository when SwiftPM builds the target.

## Add GitVersion to a package

Add the GitVersion package as a dependency, then attach its plugin to each
target that should receive generated metadata:

```swift
dependencies: [
    .package(url: "https://github.com/tonytins/GitVersion.git", from: "0.3.0")
],
targets: [
    .executableTarget(
        name: "MyApp",
        dependencies: [.product(name: "GitVersion", package: "GitVersion")],
        plugins: [.plugin(name: "GitVersionPlugin", package: "GitVersion")]
    )
]
```

The generated API is available in that target:

```swift
print(GitVersion.version)
print(GitVersion.major, GitVersion.minor, GitVersion.patch)
print(GitVersion.commit ?? "no commit")
print(GitVersion.fullCommit ?? "no commit")
print(GitVersion.current.branch ?? "detached")
```

`GitVersion.current` exposes the repository URL, branch, abbreviated and full
commit identifiers, commit date, commit count, exact and base tags, dirty state,
base version, and calculated semantic version. The generated `GitVersion`
namespace also provides direct `major`, `minor`, `patch`, `commit`,
`fullCommit`, and `version` accessors.

The generated `GitVersion` type is internal to each target. A library that wants
to publish its version needs to declare its own public API for it.

## How the version is calculated

GitVersion tries four sources in order and uses the first that applies:

| Order | Source | Count starts at |
| ----- | ------ | --------------- |
| 1     | Branch name | The commit where the branch forked from the default branch |
| 2     | Nearest version tag | The tagged commit |
| 3     | `GitVersion.txt` | The commit that last changed the file |
| 4     | Default | The oldest commit that touched the project |

The version keeps the base version's `major.minor` and prerelease label, and
sets the patch to the base patch plus the number of first-parent commits after
the reset. Merge commits on the first-parent history count; commits reachable
only from a merge's other parent do not.

### Branch versions

A branch whose last path segment is a version supplies the base version:

| Branch | Base version |
| ------ | ------------ |
| `release/1.2.3` | `1.2.3` |
| `feature/2.0` | `2.0.0` |
| `preview-3.0.0` | `3.0.0-preview` |

Counting starts at the commit where the branch forked from the default branch.
GitVersion finds that branch as `origin/HEAD`, then `main`, `origin/main`,
`master`, or `origin/master`, and uses `git merge-base --fork-point`. If there
is no default branch or no fork point, GitVersion prints a warning and uses the
next source instead.

Set `GITVERSION_IGNORE_BRANCH_VERSION=1` to skip branch versions. The values
`true`, `yes`, and `on` also work, in any case.

### Tags

The nearest tag on the first-parent history supplies the base version. The last
path segment of the tag name is the version, so `v1.2.3`, `1.2.3`, and
`release/v1.2.3` all work. Tags whose last segment is not a version are ignored.

A tag always beats `GitVersion.txt`, even when the file changed later. To start
a new major or minor line, tag the release commit or use a version branch.

### `GitVersion.txt`

`GitVersion.txt` holds a base version such as `1.2.3` or `1.2.3-preview.1`.
GitVersion searches from the package directory up to the repository root and
uses the first file it finds. The file supplies the base only when no version
branch or tag applies, and the count starts at the commit that last changed it.

For projects coming from [GitInfo](https://github.com/devlooped/GitInfo),
`GitInfo.txt` works the same way. When a directory holds both files,
`GitVersion.txt` wins; a closer file always beats one further up.

### Default version

With no branch, tag, or file, the version starts at `0.1.0` at the oldest commit
that touched the project. A package with no committed history reports `0.1.0`
with zero commits.

### Accepted versions

- An optional `v` or `V`.
- `1.2` or `1.2.3`. A missing patch is zero.
- A trailing label, such as `1.2.3-preview.1`.
- A leading label, such as `preview-1.2.3`, which becomes `1.2.3-preview`.
- Build metadata such as `+fedora.1` in tags and `GITVERSION_VERSION` only.

Anything else fails the build instead of producing a misleading version.

### Example

| History | Version |
| ------- | ------- |
| First commit touches the project | `0.1.0` |
| Two more commits touch it | `0.1.2` |
| `v5.0.0` tagged on that commit | `5.0.0` |
| One commit later | `5.0.1` |
| `GitVersion.txt` changed to `6.0.0` | `5.0.2` |
| One commit on `release/7.0.0` forked from there | `7.0.1` |

### Monorepos

Counting is limited to one scope:

- The directory containing the version file GitVersion found.
- Otherwise, the package directory when the package is below the repository
  root.
- Otherwise, the whole repository.

Tags and branch versions apply to the whole repository, but only commits that
touched the scope advance the patch. A package beside another package's
`GitVersion.txt` does not use that file, and does not count its commits.

## Build metadata

The version adds the normalized branch and abbreviated commit as build metadata,
for example `1.2.3+release.1.2.3.a1b2c3d4e5f6`. The commit is 12 characters by
default. Set `GITVERSION_ABBREV` to a whole number from 4 to 40 to change it:

```sh
GITVERSION_ABBREV=8 swift build
```

An invalid value fails the build, and the full commit identifier stays 40
characters.

A dirty working tree does not change the version. `GitVersion.current.isDirty`
reports tracked and untracked changes; use it in your own release checks.

GitVersion reads `origin` for the repository URL, removes any credentials, and
reports `nil` for a remote on the local machine. SwiftPM clones dependencies from
a local cache, so a dependency's URL is `nil`.

A detached checkout has a `nil` branch unless a CI service names one for that
exact commit. GitVersion recognizes GitHub Actions, GitLab CI, Azure Pipelines,
and Jenkins. Tag builds have no branch.

## When metadata updates

SwiftPM runs the generator when Git's record of the checkout or
`GitVersion.txt` changes: commits, branch switches, new tags, and staged changes.
Unstaged edits and untracked files are not visible to the plugin, so **`isDirty`
can lag** after an unstaged edit or a new untracked file. The next commit or
staged change corrects it. Run a clean build, or check `git status` in your
release process, if a release must prove it is clean.

`GITVERSION_VERSION` and `GITVERSION_ABBREV` are read when the generator runs and
are not plugin inputs. Changing either requires a clean build.

## Builds without full history

**Shallow clones fail the build**, because the commit count would be wrong. On
GitHub Actions, set `fetch-depth: 0` on `actions/checkout`.

**Source archives and other builds with no repository** succeed with a warning.
The version is the package's `GitVersion.txt`, or `0.0.0` without one, marked
`+unknown` because there is no commit count to add:

```text
1.2.0+unknown
```

Repository fields are `nil`, `commits` is `0`, and `isDirty` is `false`. A
repository that exists but cannot be read still fails the build.

**To set the version directly**, for example in a distro package or a Docker
build, use `GITVERSION_VERSION`:

```sh
GITVERSION_VERSION=1.2.7 swift build
```

It replaces everything: Git is not run, and repository fields report as they do
with no repository. Build metadata such as `1.2.7+fedora.1` is kept. An invalid
value fails the build.

An archive unpacked inside another Git repository, such as a packaging repository,
reads that repository's metadata. Set `GITVERSION_VERSION` in that case.

## Demo

The `Demo` directory is a separate package that attaches the plugin. Run it to
print the generated version:

```sh
swift run --package-path Demo GitVersionDemo
```

## License

I license the source code under the BSD-3-Clause license - see [LICENSE](LICENSE) for details.

## Acknowledgements

GitVersion is inspired by [GitInfo](https://github.com/devlooped/GitInfo), whose
approach to making Git metadata available to code during builds provided the
starting point for this SwiftPM implementation.
