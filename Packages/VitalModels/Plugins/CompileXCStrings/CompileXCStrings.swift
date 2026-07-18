import Foundation
import PackagePlugin

@main
struct CompileXCStrings: BuildToolPlugin {
    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let target = target as? SourceModuleTarget else { return [] }

        let xcstringsFiles = target.sourceFiles.filter { $0.url.pathExtension == "xcstrings" }
        guard !xcstringsFiles.isEmpty else { return [] }

        let outputDirectoryURL = context.pluginWorkDirectoryURL

        return xcstringsFiles.map { file in
            .prebuildCommand(
                displayName: "Compile \(file.url.lastPathComponent)",
                executable: URL(fileURLWithPath: "/usr/bin/xcrun"),
                arguments: [
                    "xcstringstool",
                    "compile",
                    file.url.path,
                    "--output-directory",
                    outputDirectoryURL.path,
                ],
                outputFilesDirectory: outputDirectoryURL
            )
        }
    }
}
