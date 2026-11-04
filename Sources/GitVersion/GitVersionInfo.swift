/// Semantic version components collected from a Git repository.
public struct GitSemanticVersion: Sendable, Equatable, CustomStringConvertible {
    /// The major version component.
    public let major: Int

    /// The minor version component.
    public let minor: Int

    /// The patch version component.
    public let patch: Int

    /// The prerelease label, if present.
    public let label: String?

    /// The build metadata, if present.
    public let buildMetadata: String?

    /// The complete semantic version string.
    public var description: String {
        var value = "\(major).\(minor).\(patch)"
        if let label {
            value += "-\(label)"
        }
        if let buildMetadata {
            value += "+\(buildMetadata)"
        }
        return value
    }

    /// Creates a semantic version from its components.
    public init(
        major: Int,
        minor: Int,
        patch: Int,
        label: String? = nil,
        buildMetadata: String? = nil
    ) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.label = label
        self.buildMetadata = buildMetadata
    }
}

/// Git metadata captured when a Swift package is built.
///
/// Repository fields are `nil`, ``commits`` is `0`, and ``isDirty`` is `false`
/// when the build had no repository to read or `GITVERSION_VERSION` was set.
public struct GitVersionInfo: Sendable, Equatable {
    /// The URL of the repository's `origin` remote without credentials.
    ///
    /// This is `nil` when there is no remote or the remote is on the local machine.
    public let repositoryURL: String?

    /// The current branch, or the branch named by a CI service for a detached checkout.
    ///
    /// This is `nil` for any other detached checkout.
    public let branch: String?

    /// The abbreviated identifier of the current commit.
    public let commit: String?

    /// The full identifier of the current commit.
    public let fullCommit: String?

    /// The committer date of the current commit in ISO 8601 format.
    public let commitDate: String?

    /// The number of first-parent commits since the version baseline.
    ///
    /// When `GitVersion.txt` is below the repository root, only commits that
    /// changed its directory are counted.
    public let commits: Int

    /// The tag pointing directly at the current commit, if any.
    public let tag: String?

    /// The nearest semantic version tag on the first-parent history, if any.
    ///
    /// This tag is not the version baseline when `GitVersion.txt` changed more recently.
    public let baseTag: String?

    /// Whether the repository has tracked or untracked changes.
    public let isDirty: Bool

    /// The version at the baseline, before commits and build metadata are added.
    public let baseVersion: GitSemanticVersion

    /// The calculated semantic version for this build.
    public let semanticVersion: GitSemanticVersion

    /// The major component of the calculated semantic version.
    public var major: Int { semanticVersion.major }

    /// The minor component of the calculated semantic version.
    public var minor: Int { semanticVersion.minor }

    /// The patch component of the calculated semantic version.
    public var patch: Int { semanticVersion.patch }

    /// The semantic version string generated for this build.
    public var version: String { semanticVersion.description }

    /// Creates a snapshot of Git metadata.
    public init(
        repositoryURL: String?,
        branch: String?,
        commit: String?,
        fullCommit: String?,
        commitDate: String?,
        commits: Int,
        tag: String?,
        baseTag: String?,
        isDirty: Bool,
        baseVersion: GitSemanticVersion,
        semanticVersion: GitSemanticVersion
    ) {
        self.repositoryURL = repositoryURL
        self.branch = branch
        self.commit = commit
        self.fullCommit = fullCommit
        self.commitDate = commitDate
        self.commits = commits
        self.tag = tag
        self.baseTag = baseTag
        self.isDirty = isDirty
        self.baseVersion = baseVersion
        self.semanticVersion = semanticVersion
    }
}
