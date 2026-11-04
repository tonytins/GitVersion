import Foundation
import PackagePlugin

@main
struct GitVersionPlugin: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        let generator = try context.tool(named: "GitVersionGenerator")
        let outputFile = context.pluginWorkDirectory.appending("GitVersion.generated.swift")

        return [
            .buildCommand(
                displayName: "Generating GitVersion metadata for \(target.name)",
                executable: generator.path,
                arguments: [
                    "--repository", context.package.directory.string,
                    "--output", outputFile.string
                ],
                inputFiles: metadataInputs(forPackageAt: context.package.directory.string),
                outputFiles: [outputFile]
            )
        ]
    }

    /// Lists the files whose changes mean the generated metadata may be out of date.
    ///
    /// Every input must exist when the build is planned, or the build fails. Working tree
    /// edits that Git has not recorded are not visible here, so they do not trigger a run.
    private func metadataInputs(forPackageAt packagePath: String) -> [Path] {
        let package = URL(fileURLWithPath: packagePath, isDirectory: true).standardizedFileURL
        var searched: [URL] = []
        var directory = package
        var inputs: [URL]?

        while inputs == nil {
            searched.append(directory)
            if let gitDirectory = gitDirectory(in: directory) {
                inputs = gitStateFiles(gitDirectory: gitDirectory)
            }
            let parent = directory.deletingLastPathComponent()
            if parent.path == directory.path {
                break
            }
            directory = parent
        }

        // Inside a repository the closest version file up to its root is used.
        // Outside one, only the package's own file is.
        let versionFileDirectories = inputs == nil ? [package] : searched
        let versionFile = versionFileDirectories
            .map { $0.appendingPathComponent("GitVersion.txt") }
            .first { FileManager.default.fileExists(atPath: $0.path) }

        return ((inputs ?? []) + (versionFile.map { [$0] } ?? []))
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            .map { Path($0.path) }
    }

    /// Finds the Git directory for `directory`. Worktrees and submodules use a `.git` file that points to it.
    private func gitDirectory(in directory: URL) -> URL? {
        let entry = directory.appendingPathComponent(".git")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: entry.path, isDirectory: &isDirectory) else {
            return nil
        }
        if isDirectory.boolValue {
            return entry
        }

        guard let contents = try? String(contentsOf: entry, encoding: .utf8),
              contents.hasPrefix("gitdir:") else {
            return nil
        }
        let path = contents.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespacesAndNewlines)
        return URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
    }

    private func gitStateFiles(gitDirectory: URL) -> [URL] {
        // Worktrees keep refs in a shared directory named by their `commondir` file.
        var commonDirectory = gitDirectory
        if let path = try? String(contentsOf: gitDirectory.appendingPathComponent("commondir"), encoding: .utf8) {
            commonDirectory = URL(
                fileURLWithPath: path.trimmingCharacters(in: .whitespacesAndNewlines),
                relativeTo: gitDirectory
            ).standardizedFileURL
        }
        return [
            gitDirectory.appendingPathComponent("HEAD"),
            gitDirectory.appendingPathComponent("index"),
            gitDirectory.appendingPathComponent("logs/HEAD"),
            commonDirectory.appendingPathComponent("packed-refs"),
            commonDirectory.appendingPathComponent("refs/tags")
        ]
    }
}
