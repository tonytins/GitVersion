# GitVersion

GitVersion is a SwiftPM build-tool plugin that makes Git repository metadata
available to Swift code. It generates a `GitVersion` namespace containing a
snapshot of the repository when SwiftPM builds the target.

## Add GitVersion to a package

Add the GitVersion package as a dependency, then attach its plugin to each
target that should receive generated metadata:

```swift
dependencies: [
    .package(url: "https://github.com/tonytins/GitVersion.git", from: "0.1.0")
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
print(GitVersion.current.branch)
print(GitVersion.current.commit)
print(GitVersion.current.fullCommit)
print(GitVersion.major, GitVersion.minor, GitVersion.patch)
print(GitVersion.current.version)
```

`GitVersion.current` exposes the repository URL, branch, abbreviated and full
commit identifiers, commit date, commit count, exact and base tags, dirty state,
base version, and calculated semantic version. The generated `GitVersion`
namespace also provides direct `major`, `minor`, `patch`, `commit`, and
`fullCommit` accessors. Metadata is collected for every build, so changes to
the current checkout are reflected without requiring a clean build.

## Base version

Place a `GitVersion.txt` file in the repository root to set the base version.
Use a semantic version such as `1.2.3` or `1.2.3-preview.1`. GitVersion finds
the latest first-parent commit that changed this file and adds the number of
first-parent commits since that baseline to the patch component. Merge commits
on the first-parent history count; commits reachable only from a merge's other
parent do not.

If `GitVersion.txt` is absent, GitVersion uses the nearest semantic version tag
on the first-parent history as the base. If there is no such tag, it starts from
`0.1.0` at the first commit in the first-parent history. An explicit prerelease
label in the base version is preserved. The generated version also adds the
normalized branch and commit as build metadata, and appends `.dirty` when the
working tree has changes.

GitVersion reads `origin` for the repository URL and recognizes common GitHub,
GitLab, and Azure Pipelines branch environment variables for detached CI builds.
Git must be installed and the consuming package must be inside a Git repository.

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