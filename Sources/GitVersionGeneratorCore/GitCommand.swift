import Foundation

struct GitResult {
    let status: Int32
    let output: String
    let errorOutput: String
}

struct GitCommand {
    /// Variables that would point Git at a different repository, such as those Git sets inside a hook.
    private static let repositoryOverrides: Set<String> = [
        "GIT_ALTERNATE_OBJECT_DIRECTORIES", "GIT_COMMON_DIR", "GIT_DIR", "GIT_INDEX_FILE",
        "GIT_OBJECT_DIRECTORY", "GIT_PREFIX", "GIT_WORK_TREE"
    ]

    private let executable: URL
    private let environment: [String: String]

    /// Finds Git on the `PATH` in `environment`.
    init(environment: [String: String]) throws {
        #if os(Windows)
        let (pathSeparator, executableName): (Character, String) = (";", "git.exe")
        #else
        let (pathSeparator, executableName): (Character, String) = (":", "git")
        #endif

        let path = environment.first { $0.key.uppercased() == "PATH" }?.value ?? ""
        let candidates = path.split(separator: pathSeparator).map {
            URL(fileURLWithPath: String($0)).appendingPathComponent(executableName)
        }
        guard let executable = candidates.first(where: {
            FileManager.default.isExecutableFile(atPath: $0.path)
        }) else {
            throw GeneratorError.gitNotFound
        }

        self.executable = executable
        self.environment = environment
            .filter { !Self.repositoryOverrides.contains($0.key) }
            .merging(["GIT_LITERAL_PATHSPECS": "1", "GIT_OPTIONAL_LOCKS": "0"]) { _, new in new }
    }

    /// Runs Git and returns its exit status and separated output streams.
    func run(_ arguments: [String], in directory: URL) throws -> GitResult {
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.environment = environment
        process.standardOutput = output
        process.standardError = errorOutput

        do {
            try process.run()
        } catch {
            throw GeneratorError.gitCommandFailed(
                command: arguments.joined(separator: " "),
                reason: error.localizedDescription
            )
        }

        // Each stream is drained on its own so that a full pipe cannot block Git.
        let errorData = BackgroundRead(of: errorOutput.fileHandleForReading)
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorText = String(decoding: errorData.wait(), as: UTF8.self)
        process.waitUntilExit()

        return GitResult(
            status: process.terminationStatus,
            output: String(decoding: outputData, as: UTF8.self).trimmingCharacters(in: .newlines),
            errorOutput: errorText.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Runs Git and returns its output, throwing when Git reports a failure.
    func output(_ arguments: [String], in directory: URL) throws -> String {
        let result = try run(arguments, in: directory)
        guard result.status == 0 else {
            throw GeneratorError.gitCommandFailed(
                command: arguments.joined(separator: " "),
                reason: result.errorOutput
            )
        }
        return result.output
    }

    /// Runs a Git query that exits with status 1 when the value is absent.
    func optionalOutput(_ arguments: [String], in directory: URL) throws -> String? {
        let result = try run(arguments, in: directory)
        switch result.status {
        case 0:
            return result.output.isEmpty ? nil : result.output
        case 1:
            return nil
        default:
            throw GeneratorError.gitCommandFailed(
                command: arguments.joined(separator: " "),
                reason: result.errorOutput
            )
        }
    }
}

private final class BackgroundRead: @unchecked Sendable {
    private let group = DispatchGroup()
    private var data = Data()

    init(of handle: FileHandle) {
        group.enter()
        DispatchQueue.global().async {
            self.data = handle.readDataToEndOfFile()
            self.group.leave()
        }
    }

    func wait() -> Data {
        group.wait()
        return data
    }
}
