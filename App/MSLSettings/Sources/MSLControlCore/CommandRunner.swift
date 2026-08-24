import Foundation

public struct CommandResult: Equatable, Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String

    public var output: String {
        [stdout, stderr].filter { !$0.isEmpty }.joined(separator: "\n")
    }

    public init(status: Int32, output: String) {
        self.status = status
        self.stdout = output
        self.stderr = ""
    }

    public init(status: Int32, stdout: String, stderr: String) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
    }
}

public protocol CommandRunning {
    func run(executable: URL, arguments: [String]) throws -> CommandResult
}

public struct ProcessCommandRunner: CommandRunning {
    public init() {}

    public func run(executable: URL, arguments: [String]) throws -> CommandResult {
        guard FileManager.default.isExecutableFile(atPath: executable.path) else {
            throw MSLControlError.executableNotFound(executable.path)
        }

        let commandID = UUID().uuidString
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("msl-command-\(commandID).stdout")
        let errorURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("msl-command-\(commandID).stderr")
        guard FileManager.default.createFile(
            atPath: outputURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ), FileManager.default.createFile(
            atPath: errorURL.path,
            contents: nil,
            attributes: [.posixPermissions: 0o600]
        ) else {
            throw MSLControlError.invalidResponse("Unable to create command output file.")
        }
        defer {
            try? FileManager.default.removeItem(at: outputURL)
            try? FileManager.default.removeItem(at: errorURL)
        }

        let outputHandle = try FileHandle(forWritingTo: outputURL)
        let errorHandle = try FileHandle(forWritingTo: errorURL)
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = outputHandle
        process.standardError = errorHandle

        do {
            try process.run()
            process.waitUntilExit()
            try outputHandle.close()
            try errorHandle.close()
        } catch {
            try? outputHandle.close()
            try? errorHandle.close()
            throw error
        }

        let outputData = try Data(contentsOf: outputURL)
        let errorData = try Data(contentsOf: errorURL)
        return CommandResult(
            status: process.terminationStatus,
            stdout: String(decoding: outputData, as: UTF8.self),
            stderr: String(decoding: errorData, as: UTF8.self)
        )
    }
}

public enum ExecutableLocator {
    public static func locate(
        overrideEnvironmentKey: String,
        candidates: [String],
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> URL? {
        if let override = environment[overrideEnvironmentKey],
           FileManager.default.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        for path in candidates where FileManager.default.isExecutableFile(atPath: path) {
            return URL(fileURLWithPath: path)
        }

        if let path = environment["PATH"] {
            for directory in path.split(separator: ":") {
                let candidate = URL(fileURLWithPath: String(directory))
                    .appendingPathComponent(candidates.first.map { URL(fileURLWithPath: $0).lastPathComponent } ?? "")
                if FileManager.default.isExecutableFile(atPath: candidate.path) {
                    return candidate
                }
            }
        }
        return nil
    }
}

public extension CommandResult {
    func requireSuccess(executable: URL, arguments: [String]) throws -> String {
        guard status == 0 else {
            let rendered = ([executable.path] + arguments).map(Self.quoteForDisplay).joined(separator: " ")
            throw MSLControlError.commandFailed(command: rendered, status: status, output: output)
        }
        return stdout
    }

    private static func quoteForDisplay(_ value: String) -> String {
        if value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\""
    }
}
