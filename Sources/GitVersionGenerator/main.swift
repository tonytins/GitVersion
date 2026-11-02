import Foundation

private struct SemanticVersion {
    let major: Int
    let minor: Int
    let patch: Int
    let label: String?
    let buildMetadata: String?

    init(major: Int, minor: Int, patch: Int, label: String?, buildMetadata: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.label = label
        self.buildMetadata = buildMetadata
    }
}

private struct RepositoryInfo {
    let repositoryURL: String?
    let branch: String
    let commit: String
    let fullCommit: String
    let commitDate: String
    let commits: Int
    let tag: String?
    let baseTag: String?
    let isDirty: Bool
    let baseVersion: SemanticVersion
    let semanticVersion: SemanticVersion
}

private enum GeneratorError: Error, CustomStringConvertible {
    case invalidArguments
    case gitNotFound
    case notRepository
    case gitCommandFailed(String)
    case invalidVersionFile(URL)
    case fileSystem(String)

    var description: String {
        switch self {
        case .invalidArguments:
            return "Usage: GitVersionGenerator --repository <path> --output <file>"
        case .gitNotFound:
            return "GitVersionGenerator could not find the git executable on PATH."
        case .notRepository:
            return "The selected package directory is not inside a Git repository."
        case .gitCommandFailed(let command):
            return "GitVersionGenerator could not read required repository metadata: \(command)"
        case .invalidVersionFile(let url):
            return "\(url.lastPathComponent) must contain a semantic version such as 1.2.3 or 1.2.3-preview.1."
        case .fileSystem(let message):
            return "GitVersionGenerator could not write generated source: \(message)"
        }
    }
}

private struct GitCommand {
    private let executable: URL

    init() throws {
        let paths = ProcessInfo.processInfo.environment["PATH", default: ""]
            .split(separator: ":")
            .map(String.init)
        let candidates = paths.map { URL(fileURLWithPath: $0).appendingPathComponent("git") }
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw GeneratorError.gitNotFound
        }
        self.executable = executable
    }

    func run(_ arguments: [String], in directory: URL) throws -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output

        do {
            try process.run()
        } catch {
            throw GeneratorError.gitCommandFailed(arguments.joined(separator: " "))
        }

        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        let text = String(decoding: data, as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard process.terminationStatus == 0 else { return nil }
        return text
    }

    func runRequired(_ arguments: [String], in directory: URL) throws -> String {
        guard let output = try run(arguments, in: directory) else {
            throw GeneratorError.gitCommandFailed(arguments.joined(separator: " "))
        }
        return output
    }
}

private func parseSemanticVersion(_ value: String) -> SemanticVersion? {
    var version = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if version.hasPrefix("v") {
        version.removeFirst()
    }

    guard !version.contains("+") else { return nil }
    let parts = version.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false)
    let numbers = parts[0].split(separator: ".", omittingEmptySubsequences: false)
    guard numbers.count == 3,
          let major = parseVersionNumber(numbers[0]),
          let minor = parseVersionNumber(numbers[1]),
          let patch = parseVersionNumber(numbers[2]) else {
        return nil
    }

    let label = parts.count == 2 ? String(parts[1]) : nil
    if let label {
        let identifiers = label.split(separator: ".", omittingEmptySubsequences: false)
        guard !identifiers.isEmpty else { return nil }
        for identifier in identifiers {
            guard identifier.unicodeScalars.allSatisfy({
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-")
                    .contains($0)
            }) else {
                return nil
            }
            if identifier.allSatisfy(\.isNumber),
               identifier.count > 1,
               identifier.hasPrefix("0") {
                return nil
            }
        }
    }
    return SemanticVersion(major: major, minor: minor, patch: patch, label: label)
}

private func parseVersionNumber(_ value: Substring) -> Int? {
    guard !value.isEmpty,
          value.allSatisfy({ $0.isASCII && $0.isNumber }),
          value.count == 1 || !value.hasPrefix("0") else {
        return nil
    }
    return Int(value)
}

private func normalizedIdentifier(_ value: String) -> String {
    var result = ""
    var needsSeparator = false
    for scalar in value.lowercased().unicodeScalars {
        if CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-").contains(scalar) {
            if needsSeparator, !result.isEmpty, !result.hasSuffix(".") {
                result.append(".")
            }
            result.unicodeScalars.append(scalar)
            needsSeparator = false
        } else {
            needsSeparator = true
        }
    }
    while result.hasSuffix(".") {
        result.removeLast()
    }
    return result.isEmpty ? "unknown" : result
}

private func optionalString(_ value: String?) -> String {
    guard let value else { return "nil" }
    return "Optional(\(String(reflecting: value)))"
}

private func semanticVersionSource(_ version: SemanticVersion) -> String {
    """
    GitSemanticVersion(
        major: \(version.major),
        minor: \(version.minor),
        patch: \(version.patch),
        label: \(optionalString(version.label)),
        buildMetadata: \(optionalString(version.buildMetadata))
    )
    """
}

private func collectInfo(repository: URL, git: GitCommand) throws -> RepositoryInfo {
    guard let rootPath = try git.run(["rev-parse", "--show-toplevel"], in: repository) else {
        throw GeneratorError.notRepository
    }
    let root = URL(fileURLWithPath: rootPath, isDirectory: true)
    let commit = try git.runRequired(["rev-parse", "--short=12", "HEAD"], in: root)
    let fullCommit = try git.runRequired(["rev-parse", "HEAD"], in: root)
    let commitDate = try git.runRequired(["show", "-s", "--format=%cI", "HEAD"], in: root)
    let exactTag = try git.run(["describe", "--tags", "--exact-match", "HEAD"], in: root)
    let baseTag = try git.run(
        ["describe", "--tags", "--match", "[0-9]*", "--match", "v[0-9]*", "--abbrev=0", "HEAD"],
        in: root
    )
    let repositoryURL = try git.run(["config", "--get", "remote.origin.url"], in: root)

    let environment = ProcessInfo.processInfo.environment
    let ciBranch = [
        environment["GITHUB_HEAD_REF"],
        environment["GITHUB_REF_NAME"],
        environment["CI_COMMIT_REF_NAME"],
        environment["BUILD_SOURCEBRANCHNAME"],
        environment["GIT_BRANCH"]
    ].compactMap { $0 }.first { !$0.isEmpty }
    let branch = try git.run(["branch", "--show-current"], in: root)
        .flatMap { $0.isEmpty ? nil : $0 }
        ?? ciBranch
        ?? commit

    let configURL = root.appendingPathComponent("GitVersion.txt")
    let versionFileValue: String?
    if FileManager.default.fileExists(atPath: configURL.path) {
        let contents: String
        do {
            contents = try String(contentsOf: configURL, encoding: .utf8)
        } catch {
            throw GeneratorError.fileSystem(error.localizedDescription)
        }
        guard let value = contents.components(separatedBy: .newlines)
            .first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw GeneratorError.invalidVersionFile(configURL)
        }
        versionFileValue = value
    } else {
        versionFileValue = nil
    }

    let baseVersion: SemanticVersion
    if let versionFileValue {
        guard let parsed = parseSemanticVersion(versionFileValue) else {
            throw GeneratorError.invalidVersionFile(configURL)
        }
        baseVersion = parsed
    } else if let baseTag, let parsed = parseSemanticVersion(baseTag) {
        baseVersion = parsed
    } else {
        baseVersion = SemanticVersion(major: 0, minor: 1, patch: 0, label: nil)
    }

    let countRange = baseTag.map { "\($0)..HEAD" } ?? "HEAD"
    let commitCountText = try git.run(
        ["rev-list", "--count", countRange],
        in: root
    )
    guard let commitCountText else {
        throw GeneratorError.gitCommandFailed("rev-list --count \(countRange)")
    }
    guard let commitCount = Int(commitCountText) else {
        throw GeneratorError.gitCommandFailed("rev-list --count \(countRange)")
    }

    let status = try git.runRequired(["status", "--porcelain"], in: root)
    let isDirty = !status.isEmpty
    let label: String?
    if commitCount > 0 {
        let branchLabel = "\(normalizedIdentifier(branch)).\(commitCount)"
        label = [baseVersion.label, branchLabel].compactMap { $0 }.joined(separator: ".")
    } else {
        label = baseVersion.label
    }
    let metadata = "\(normalizedIdentifier(branch)).\(commit)"
    let semanticVersion = SemanticVersion(
        major: baseVersion.major,
        minor: baseVersion.minor,
        patch: baseVersion.patch,
        label: label,
        buildMetadata: metadata + (isDirty ? ".dirty" : "")
    )

    return RepositoryInfo(
        repositoryURL: repositoryURL,
        branch: branch,
        commit: commit,
        fullCommit: fullCommit,
        commitDate: commitDate,
        commits: commitCount,
        tag: exactTag,
        baseTag: baseTag,
        isDirty: isDirty,
        baseVersion: baseVersion,
        semanticVersion: semanticVersion
    )
}

private func generatedSource(for info: RepositoryInfo) -> String {
    """
    // Generated by GitVersion. Do not edit.
    import GitVersion

    public enum GitVersion {
        public static let current = GitVersionInfo(
            repositoryURL: \(optionalString(info.repositoryURL)),
            branch: \(String(reflecting: info.branch)),
            commit: \(String(reflecting: info.commit)),
            fullCommit: \(String(reflecting: info.fullCommit)),
            commitDate: \(String(reflecting: info.commitDate)),
            commits: \(info.commits),
            tag: \(optionalString(info.tag)),
            baseTag: \(optionalString(info.baseTag)),
            isDirty: \(info.isDirty),
            baseVersion: \(semanticVersionSource(info.baseVersion)),
            semanticVersion: GitSemanticVersion(
                major: \(info.semanticVersion.major),
                minor: \(info.semanticVersion.minor),
                patch: \(info.semanticVersion.patch),
                label: \(optionalString(info.semanticVersion.label)),
                buildMetadata: \(optionalString(info.semanticVersion.buildMetadata))
            )
        )

        public static let major = current.major
        public static let minor = current.minor
        public static let patch = current.patch
        public static let commit = current.commit
        public static let fullCommit = current.fullCommit
        public static let version = current.version
    }
    """
}

private func parseArguments(_ arguments: [String]) throws -> (repository: URL, outputFile: URL) {
    guard arguments.count == 4,
          arguments[0] == "--repository",
          arguments[2] == "--output" else {
        throw GeneratorError.invalidArguments
    }
    return (
        URL(fileURLWithPath: arguments[1], isDirectory: true),
        URL(fileURLWithPath: arguments[3])
    )
}

do {
    let arguments = try parseArguments(Array(CommandLine.arguments.dropFirst()))
    let git = try GitCommand()
    let info = try collectInfo(repository: arguments.repository, git: git)
    do {
        try FileManager.default.createDirectory(
            at: arguments.outputFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let source = generatedSource(for: info)
        let currentSource = FileManager.default.fileExists(atPath: arguments.outputFile.path)
            ? try String(contentsOf: arguments.outputFile, encoding: .utf8)
            : nil
        if currentSource != source {
            try source.write(to: arguments.outputFile, atomically: true, encoding: .utf8)
        }
    } catch {
        throw GeneratorError.fileSystem(error.localizedDescription)
    }
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(EXIT_FAILURE)
}
