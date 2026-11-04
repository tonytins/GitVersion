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
    let historyIndex: Int
    let version: SemanticVersion
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

    // The first-parent history is ordered from HEAD, so a smaller index is a closer reset.
    let history = try git.output(["rev-list", "--first-parent", "HEAD"], in: root)
        .split(separator: "\n")
        .map(String.init)
    let historyIndexes = Dictionary(
        history.enumerated().map { ($0.element, $0.offset) },
        uniquingKeysWith: { first, _ in first }
    )

    let tags = try readTags(git: git, root: root)
    var closestTag: (tag: VersionTag, reset: Reset)?
    for tag in tags {
        guard let version = tag.version, let index = historyIndexes[tag.commit] else { continue }
        guard let current = closestTag else {
            closestTag = (tag, Reset(historyIndex: index, version: version))
            continue
        }
        if index < current.reset.historyIndex
            || (index == current.reset.historyIndex && current.reset.version.hasLowerPrecedence(than: version)) {
            closestTag = (tag, Reset(historyIndex: index, version: version))
        }
    }

    let versionFile = try findVersionFile(root: root, packagePrefix: packagePrefix)
    var fileReset: Reset?
    if let versionFile {
        let lastChange = try git.output(
            ["rev-list", "-1", "--first-parent", "HEAD", "--", versionFile.path],
            in: root
        )
        // A file with no committed history takes effect at HEAD.
        fileReset = Reset(historyIndex: historyIndexes[lastChange] ?? 0, version: versionFile.version)
    }

    let reset: Reset
    switch (closestTag?.reset, fileReset) {
    case let (tagReset?, fileReset?):
        reset = tagReset.historyIndex <= fileReset.historyIndex ? tagReset : fileReset
    case let (tagReset?, nil):
        reset = tagReset
    case let (nil, fileReset?):
        reset = fileReset
    case (nil, nil):
        reset = Reset(historyIndex: history.count - 1, version: SemanticVersion(major: 0, minor: 1, patch: 0))
    }
    let baseVersion = SemanticVersion(
        major: reset.version.major,
        minor: reset.version.minor,
        patch: reset.version.patch,
        label: reset.version.label
    )

    var countArguments = ["rev-list", "--first-parent", "--count", "\(history[reset.historyIndex])..HEAD"]
    if let directory = versionFile?.directory, !directory.isEmpty {
        countArguments += ["--", directory]
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
    let exactTag = closestTag.flatMap { $0.reset.historyIndex == 0 ? $0.tag.name : nil }
        ?? tagsAtHead.first?.name

    return RepositoryInfo(
        repositoryURL: remote.flatMap(publicRemoteURL),
        branch: branch,
        commit: commit,
        fullCommit: fullCommit,
        commitDate: commitDate,
        commits: commitCount,
        tag: exactTag,
        baseTag: closestTag?.tag.name,
        isDirty: isDirty,
        baseVersion: baseVersion,
        semanticVersion: SemanticVersion(
            major: baseVersion.major,
            minor: baseVersion.minor,
            patch: patch,
            label: baseVersion.label,
            buildMetadata: metadata
        ),
        warning: nil
    )
}
