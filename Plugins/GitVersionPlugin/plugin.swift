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
                inputFiles: [],
                outputFiles: [outputFile]
            )
        ]
    }
}
