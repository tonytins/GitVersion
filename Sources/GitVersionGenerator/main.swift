import Foundation
import GitVersionGeneratorCore

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
    let info = try collectInfo(package: arguments.repository, environment: ProcessInfo.processInfo.environment)
    if let warning = info.warning {
        FileHandle.standardError.write(Data("warning: \(warning)\n".utf8))
    }
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
