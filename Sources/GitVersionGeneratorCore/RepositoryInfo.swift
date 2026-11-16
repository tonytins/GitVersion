import Foundation

let versionFileName = "GitVersion.txt"
let versionOverrideVariable = "GITVERSION_VERSION"

public struct RepositoryInfo {
    let repositoryURL: String?
    let branch: String?
    let commit: String?
    let fullCommit: String?
    let commitDate: String?
    let commits: Int
    let tag: String?
    let baseTag: String?
    let isDirty: Bool
    let baseVersion: SemanticVersion
    let semanticVersion: SemanticVersion
    public let warning: String?
}

public enum GeneratorError: Error, CustomStringConvertible {
    case invalidArguments
    case gitNotFound
    case shallowRepository
    case gitCommandFailed(command: String, reason: String)
    case invalidVersionFile(URL)
    case unreadableVersionFile(URL, reason: String)
    case invalidVersionOverride(String)
    case versionOverflow
    case fileSystem(String)

    public var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: GitVersionGenerator --repository <path> --output <file>"
        case .gitNotFound:
            return "GitVersionGenerator found a Git repository but could not find the git executable on PATH."
        case .shallowRepository:
            return """
            GitVersion cannot count commits in a shallow clone, so the version would be wrong. \
            Fetch the full history (for GitHub Actions, set fetch-depth: 0 on actions/checkout) \
            or set \(versionOverrideVariable).
            """
        case .gitCommandFailed(let command, let reason):
            return "GitVersionGenerator could not read repository metadata with 'git \(command)': \(reason)"
        case .invalidVersionFile(let url):
            return "\(url.path) must contain a semantic version such as 1.2.3 or 1.2.3-preview.1."
        case .unreadableVersionFile(let url, let reason):
            return "GitVersionGenerator could not read \(url.path): \(reason)"
        case .invalidVersionOverride(let value):
            return "\(versionOverrideVariable) must be a semantic version such as 1.2.3, but was '\(value)'."
        case .versionOverflow:
            return "The patch version overflowed while adding commits since the version baseline."
        case .fileSystem(let message):
            return "GitVersionGenerator could not write generated source: \(message)"
        }
    }
}

/// Collects the metadata for the package at `package`.
///
/// `GITVERSION_VERSION` replaces all repository metadata. Without it, a package
/// outside any repository reports an unknown version and a warning. A repository
/// that exists but cannot be read always throws.
public func collectInfo(package: URL, environment: [String: String]) throws -> RepositoryInfo {
    if let override = environment[versionOverrideVariable], !override.isEmpty {
        return try overriddenInfo(override)
    }
    guard isInsideRepository(package) else {
        return try unknownInfo(package: package)
    }
    return try repositoryInfo(package: package, environment: environment)
}

/// Removes credentials from a remote URL, and returns `nil` for a remote on the local machine.
func publicRemoteURL(_ remote: String) -> String? {
    if let schemeRange = remote.range(of: "://") {
        guard remote[..<schemeRange.lowerBound].lowercased() != "file" else { return nil }
        let afterScheme = remote[schemeRange.upperBound...]
        let authorityEnd = afterScheme.firstIndex(of: "/") ?? afterScheme.endIndex
        guard let credentialsEnd = afterScheme[..<authorityEnd].lastIndex(of: "@") else { return remote }
        return String(remote[..<schemeRange.upperBound]) + afterScheme[afterScheme.index(after: credentialsEnd)...]
    }

    // scp-style remotes have a host before the first colon and no slash ahead of it.
    guard let colon = remote.firstIndex(of: ":"),
          !remote[..<colon].contains("/"),
          remote.distance(from: remote.startIndex, to: colon) > 1 else {
        return nil
    }
    return remote
}

/// Finds the branch a CI service checked out as a detached commit.
///
/// A service's variables only count when they describe `commit`, so a dependency
/// checked out during a build does not report the branch of the package building it.
func continuousIntegrationBranch(in environment: [String: String], commit: String) -> String? {
    func value(_ name: String) -> String? {
        environment[name].flatMap { $0.isEmpty ? nil : $0 }
    }

    if value("GITHUB_SHA") == commit {
        if let branch = value("GITHUB_HEAD_REF") { return branch }
        if value("GITHUB_REF_TYPE") == "branch" { return value("GITHUB_REF_NAME") }
    }
    if value("CI_COMMIT_SHA") == commit, value("CI_COMMIT_TAG") == nil {
        return value("CI_COMMIT_REF_NAME")
    }
    if value("BUILD_SOURCEVERSION") == commit,
       let reference = value("BUILD_SOURCEBRANCH"),
       reference.hasPrefix("refs/heads/") {
        return String(reference.dropFirst("refs/heads/".count))
    }
    if value("GIT_COMMIT") == commit, let branch = value("GIT_BRANCH") {
        return branch.hasPrefix("origin/") ? String(branch.dropFirst("origin/".count)) : branch
    }
    return nil
}

/// Converts a branch name to dot-separated build metadata identifiers.
func normalizedIdentifier(_ value: String) -> String? {
    let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
    let identifiers = value.lowercased()
        .components(separatedBy: allowed.inverted)
        .filter { !$0.isEmpty }
    return identifiers.isEmpty ? nil : identifiers.joined(separator: ".")
}

private func overriddenInfo(_ override: String) throws -> RepositoryInfo {
    guard let version = SemanticVersion(parsing: override, allowsBuildMetadata: true) else {
        throw GeneratorError.invalidVersionOverride(override)
    }
    return detachedInfo(
        baseVersion: SemanticVersion(
            major: version.major,
            minor: version.minor,
            patch: version.patch,
            label: version.label
        ),
        semanticVersion: version,
        warning: nil
    )
}

private func unknownInfo(package: URL) throws -> RepositoryInfo {
    let file = package.appendingPathComponent(versionFileName)
    let baseVersion = FileManager.default.fileExists(atPath: file.path)
        ? try readVersionFile(file)
        : SemanticVersion(major: 0, minor: 0, patch: 0)
    let version = SemanticVersion(
        major: baseVersion.major,
        minor: baseVersion.minor,
        patch: baseVersion.patch,
        label: baseVersion.label,
        buildMetadata: "unknown"
    )
    return detachedInfo(
        baseVersion: baseVersion,
        semanticVersion: version,
        warning: """
        GitVersion found no Git repository for \(package.path), so the version is only a baseline: \
        \(version). Set \(versionOverrideVariable) to provide the real version.
        """
    )
}

private func detachedInfo(
    baseVersion: SemanticVersion,
    semanticVersion: SemanticVersion,
    warning: String?
) -> RepositoryInfo {
    RepositoryInfo(
        repositoryURL: nil,
        branch: nil,
        commit: nil,
        fullCommit: nil,
        commitDate: nil,
        commits: 0,
        tag: nil,
        baseTag: nil,
        isDirty: false,
        baseVersion: baseVersion,
        semanticVersion: semanticVersion,
        warning: warning
    )
}

private func isInsideRepository(_ package: URL) -> Bool {
    var directory = package.standardizedFileURL
    while true {
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) {
            return true
        }
        let parent = directory.deletingLastPathComponent()
        guard parent.path != directory.path else { return false }
        directory = parent
    }
}

private func readVersionFile(_ url: URL) throws -> SemanticVersion {
    let contents: String
    do {
        contents = try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw GeneratorError.unreadableVersionFile(url, reason: error.localizedDescription)
    }
    guard let line = contents.components(separatedBy: .newlines).first(where: {
        !$0.trimmingCharacters(in: .whitespaces).isEmpty
    }), let version = SemanticVersion(parsing: line) else {
        throw GeneratorError.invalidVersionFile(url)
    }
    return version
}

private struct VersionFile {
    /// The directory holding the file, relative to the repository root. Empty at the root.
    let directory: String
    let path: String
    let version: SemanticVersion
}

/// Searches from the package directory up to the repository root and uses the first file found.
private func findVersionFile(root: URL, packagePrefix: String) throws -> VersionFile? {
    let components = packagePrefix.split(separator: "/").map(String.init)
    for depth in stride(from: components.count, through: 0, by: -1) {
        let directory = components.prefix(depth).joined(separator: "/")
        let path = directory.isEmpty ? versionFileName : "\(directory)/\(versionFileName)"
        let url = root.appendingPathComponent(path)
        if FileManager.default.fileExists(atPath: url.path) {
            return VersionFile(directory: directory, path: path, version: try readVersionFile(url))
        }
    }
    return nil
}

private struct VersionTag {
    let name: String
    let commit: String
    let version: SemanticVersion?
}

private func readTags(git: GitCommand, root: URL) throws -> [VersionTag] {
    let listing = try git.output(
        [
            "for-each-ref", "--merged", "HEAD",
            "--format=%(objectname) %(*objectname) %(refname:strip=2)", "refs/tags"
        ],
        in: root
    )
    return listing.split(separator: "\n").compactMap { line in
        let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false)
        guard fields.count == 3 else { return nil }
        let name = String(fields[2])
        return VersionTag(
            name: name,
            commit: String(fields[1].isEmpty ? fields[0] : fields[1]),
            version: SemanticVersion(parsing: name, allowsBuildMetadata: true)
        )
    }
}

private struct Reset {
    /// The commit that the version counts from.
    let start: String
    let version: SemanticVersion
}

/// Returns the version encoded in a branch name, such as `release/1.2.3`.
private func branchVersion(_ branch: String) -> SemanticVersion? {
    let candidate = branch.lastIndex(where: { $0 == "/" || $0 == "\\" })
        .map { branch[branch.index(after: $0)...] } ?? branch[...]
    return SemanticVersion(parsing: String(candidate))
}

/// Resolves the branch a version branch forked from.
private func defaultBranch(git: GitCommand, root: URL) throws -> String? {
    if let head = try git.optionalOutput(
        ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"],
        in: root
    ), !head.isEmpty,
       try git.optionalOutput(["rev-parse", "--verify", "--quiet", head], in: root) != nil {
        return head
    }
    for name in ["main", "master"] {
        if try git.optionalOutput(
            ["rev-parse", "--verify", "--quiet", "refs/heads/\(name)"],
            in: root
        ) != nil {
            return name
        }
        if try git.optionalOutput(
            ["rev-parse", "--verify", "--quiet", "refs/remotes/origin/\(name)"],
            in: root
        ) != nil {
            return "origin/\(name)"
        }
    }
    return nil
}

/// Whether a switch is set. Only recognized positive values enable it.
private func isTruthy(_ value: String?) -> Bool {
    guard let value else { return false }
    return ["1", "true", "yes", "on"].contains(
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    )
}

/// The path that version counting is limited to, relative to the repository root.
///
/// A version file scopes the count to its directory. Without one, a package
/// below the root scopes the count to the package, and a package at the root
/// scopes it to the whole repository. An empty result means the whole repository.
private func projectScope(versionFile: VersionFile?, packagePrefix: String) -> String {
    if let versionFile {
        return versionFile.directory
    }
    return packagePrefix.hasSuffix("/") ? String(packagePrefix.dropLast()) : packagePrefix
}

private func repositoryInfo(package: URL, environment: [String: String]) throws -> RepositoryInfo {
    let git = try GitCommand(environment: environment)
    let rootPath = try git.output(["rev-parse", "--show-toplevel"], in: package)
    let packagePrefix = try git.output(["rev-parse", "--show-prefix"], in: package)
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)

    guard try git.output(["rev-parse", "--is-shallow-repository"], in: root) != "true" else {
        throw GeneratorError.shallowRepository
    }

    let commit = try git.output(["rev-parse", "--verify", "--short=12", "HEAD"], in: root)
    let fullCommit = try git.output(["rev-parse", "--verify", "HEAD"], in: root)
    let commitDate = try git.output(["show", "-s", "--no-show-signature", "--format=%cI", "HEAD"], in: root)
    let remote = try git.optionalOutput(["config", "--get", "remote.origin.url"], in: root)
    let branch = try git.optionalOutput(["symbolic-ref", "--quiet", "--short", "HEAD"], in: root)
        ?? continuousIntegrationBranch(in: environment, commit: fullCommit)

    // The first-parent history is ordered from HEAD, so a smaller index is a closer tag.
    let history = try git.output(["rev-list", "--first-parent", "HEAD"], in: root)
        .split(separator: "\n")
        .map(String.init)
    let historyIndexes = Dictionary(
        history.enumerated().map { ($0.element, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )

    let tags = try readTags(git: git, root: root)
    var closestTag: (tag: VersionTag, index: Int, version: SemanticVersion)?
    for tag in tags {
        guard let version = tag.version, let index = historyIndexes[tag.commit] else { continue }
        guard let current = closestTag else {
            closestTag = (tag, index, version)
            continue
        }
        if index < current.index
            || (index == current.index && current.version.hasLowerPrecedence(than: version)) {
            closestTag = (tag, index, version)
        }
    }

    let versionFile = try findVersionFile(root: root, packagePrefix: packagePrefix)
    let scope = projectScope(versionFile: versionFile, packagePrefix: packagePrefix)

    var warning: String?
    var baseTag: String?
    var reset: Reset?

    // A version branch wins over a tag, the version file, and the default.
    if !isTruthy(environment["GITVERSION_IGNORE_BRANCH_VERSION"]),
       let branch,
       let version = branchVersion(branch) {
        let defaultBranch = try defaultBranch(git: git, root: root)
        if let defaultBranch {
            let forkPoint = try git.run(["merge-base", "--fork-point", defaultBranch, "HEAD"], in: root)
            if forkPoint.status == 0, !forkPoint.output.isEmpty {
                reset = Reset(start: forkPoint.output, version: version)
            } else {
                warning = """
                GitVersion could not determine where branch '\(branch)' forked from '\(defaultBranch)', \
                so it did not use \(version) as the base version.
                """
            }
        } else {
            warning = """
            GitVersion could not find a default branch to compare with '\(branch)', \
            so it did not use \(version) as the base version.
            """
        }
    }

    if reset == nil, let closestTag {
        reset = Reset(start: closestTag.tag.commit, version: closestTag.version)
        baseTag = closestTag.tag.name
    }

    if reset == nil, let versionFile {
        let lastChange = try git.output(
            ["rev-list", "-1", "--first-parent", "HEAD", "--", versionFile.path],
            in: root
        )
        // A file with no committed history takes effect at HEAD.
        reset = Reset(start: lastChange.isEmpty ? fullCommit : lastChange, version: versionFile.version)
    }

    let baseReset: Reset
    if let reset {
        baseReset = reset
    } else if scope.isEmpty, let initialCommit = history.last {
        baseReset = Reset(
            start: initialCommit,
            version: SemanticVersion(major: 0, minor: 1, patch: 0)
        )
    } else if scope.isEmpty {
        throw GeneratorError.gitCommandFailed(
            command: "rev-list --first-parent HEAD",
            reason: "Git returned no commits."
        )
    } else {
        // The oldest commit that touched the package is where its history starts.
        let firstTouching = try git.output(
            ["rev-list", "--first-parent", "HEAD", "--", scope],
            in: root
        ).split(separator: "\n").last.map(String.init)
        baseReset = Reset(
            start: firstTouching ?? fullCommit,
            version: SemanticVersion(major: 0, minor: 1, patch: 0)
        )
    }

    let baseVersion = SemanticVersion(
        major: baseReset.version.major,
        minor: baseReset.version.minor,
        patch: baseReset.version.patch,
        label: baseReset.version.label
    )

    var countArguments = ["rev-list", "--first-parent", "--count", "\(baseReset.start)..HEAD"]
    if !scope.isEmpty {
        countArguments += ["--", scope]
    }
    guard let commitCount = Int(try git.output(countArguments, in: root)) else {
        throw GeneratorError.gitCommandFailed(
            command: countArguments.joined(separator: " "),
            reason: "Git did not return a number."
        )
    }
    let (patch, patchOverflow) = baseVersion.patch.addingReportingOverflow(commitCount)
    guard !patchOverflow else {
        throw GeneratorError.versionOverflow
    }

    let status = try git.output(["status", "--porcelain", "--untracked-files=normal"], in: root)
    let isDirty = !status.isEmpty
    let metadata = [branch.flatMap(normalizedIdentifier), commit, isDirty ? "dirty" : nil]
        .compactMap { $0 }
        .joined(separator: ".")

    let tagsAtHead = tags.filter { $0.commit == fullCommit }
    let exactTag = closestTag.flatMap { $0.index == 0 ? $0.tag.name : nil }
        ?? tagsAtHead.first?.name

    return RepositoryInfo(
        repositoryURL: remote.flatMap(publicRemoteURL),
        branch: branch,
        commit: commit,
        fullCommit: fullCommit,
        commitDate: commitDate,
        commits: commitCount,
        tag: exactTag,
        baseTag: baseTag,
        isDirty: isDirty,
        baseVersion: baseVersion,
        semanticVersion: SemanticVersion(
            major: baseVersion.major,
            minor: baseVersion.minor,
            patch: patch,
            label: baseVersion.label,
            buildMetadata: metadata
        ),
        warning: warning
    )
}
