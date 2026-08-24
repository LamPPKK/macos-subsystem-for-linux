import AppKit
import Foundation
import MSLControlCore

struct TerminalLauncher {
    func open(executable: URL, arguments: [String], title: String, scriptID: String) throws {
        let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MSL Settings/Terminal", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        let safeID = scriptID.replacingOccurrences(
            of: "[^A-Za-z0-9_.-]",
            with: "-",
            options: .regularExpression
        )
        let scriptURL = directory.appendingPathComponent("\(safeID).command")
        let command = ([executable.path] + arguments).map(shellQuote).joined(separator: " ")
        let script = """
        #!/bin/zsh
        printf '\\033]0;%s\\007' \(shellQuote(title))
        exec \(command)

        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: scriptURL.path)
        guard NSWorkspace.shared.open(scriptURL) else {
            throw MSLControlError.invalidResponse("Terminal could not open the generated command.")
        }
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}
