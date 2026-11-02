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
print(GitVersion.current.version)
```

`GitVersion.current` exposes the repository URL, branch, abbreviated commit,
commit date, commit count, exact and base tags, dirty state, base version, and
calculated semantic version. Metadata is collected for every build, so changes
to the current checkout are reflected without requiring a clean build.

## Base version

Place a `GitVersion.txt` file in the repository root to set the base version.
Use a semantic version such as `1.2.3` or `1.2.3-preview.1`. If the file is
absent, GitVersion uses the nearest reachable semantic version tag, then falls
back to `0.1.0`.

The generated semantic version adds a prerelease label from the branch and
number of commits after the nearest semantic version tag when applicable. It
also adds the normalized branch and commit as build metadata, and appends
`.dirty` when the working tree has changes.

GitVersion reads `origin` for the repository URL and recognizes common GitHub,
GitLab, and Azure Pipelines branch environment variables for detached CI builds.
Git must be installed and the consuming package must be inside a Git repository.
