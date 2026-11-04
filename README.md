# GitVersion

GitVersion is a SwiftPM build-tool plugin that makes Git repository metadata
available to Swift code. It generates a `GitVersion` namespace containing a
snapshot of the repository when SwiftPM builds the target.

## Add GitVersion to a package

Add the GitVersion package as a dependency, then attach its plugin to each
target that should receive generated metadata:

```swift
dependencies: [
    .package(url: "https://github.com/tonytins/GitVersion.git", from: "0.2.0")
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

## Base version

The version comes from the closest reset on the first-parent history, plus the
number of first-parent commits since that reset. A reset is either of these:

- A semantic version tag such as `v1.2.3` or `1.2.3`. Other tags are ignored.
- A commit that changed `GitVersion.txt`, which holds a semantic version such as
  `1.2.3` or `1.2.3-preview.1`.

A tag wins when both land on the same commit. With no reset at all, the version
starts from `0.1.0` at the first commit.

| History                                | Version |
| -------------------------------------- | ------- |
| File set to `0.1.0`, 2 commits later   | `0.1.2` |
| Then `v5.0.0` tagged on that commit    | `5.0.0` |
| 1 commit after the tag                 | `5.0.1` |
| File then changed to `6.0.0`           | `6.0.0` |

Merge commits on the first-parent history count; commits reachable only from a
merge's other parent do not. A prerelease label in the base version is
preserved.

GitVersion searches for `GitVersion.txt` from the package directory up to the
repository root and uses the first one it finds. When that file is below the
root, only commits that changed its directory are counted, so a package in a
monorepo is not affected by its neighbors. Tags apply to the whole repository,
so a version tag still resets a package with its own file.

## Build metadata

The generated version adds the normalized branch and abbreviated commit as build
metadata, such as `1.2.3+feature.login.a1b2c3d4e5f6`, and appends `.dirty` when
the working tree has changes. Keep `.build` ignored, and commit or ignore
`Package.resolved`, or every build reports as dirty.

GitVersion reads `origin` for the repository URL, removes any credentials, and
reports `nil` for a remote on the local machine. SwiftPM clones dependencies from
a local cache, so a dependency's URL is `nil`.

A detached checkout has a `nil` branch unless a CI service names one for that
exact commit. GitVersion recognizes GitHub Actions, GitLab CI, Azure Pipelines,
and Jenkins. Tag builds have no branch.

## When metadata updates

SwiftPM only runs the generator when one of its inputs changes. GitVersion
watches Git's record of the checkout and `GitVersion.txt`, so commits, branch
switches, new tags, and staged changes all update the metadata on the next build.

Git does not record working tree edits until they are staged, so **`isDirty` and
the `.dirty` suffix can lag** after an unstaged edit or a new untracked file. The
next commit or staged change corrects them. Run a clean build, or check
`git status` in your release process, if a release must prove it is clean.

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
value fails the build. Changing it requires a clean build.

An archive unpacked inside another Git repository, such as a packaging repository,
reads that repository's metadata. Set `GITVERSION_VERSION` in that case.

## Demo

Run the included program from the repository root to print its generated version:

```sh
swift run GitVersionDemo
```

## License

I license the source code under the BSD-3-Clause license - see [LICENSE](LICENSE) for details.

## Acknowledgements

GitVersion is inspired by [GitInfo](https://github.com/devlooped/GitInfo), whose
approach to making Git metadata available to code during builds provided the
starting point for this SwiftPM implementation.