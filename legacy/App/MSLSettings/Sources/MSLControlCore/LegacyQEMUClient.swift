import Foundation

public final class LegacyQEMUClient: @unchecked Sendable {
    public let executableURL: URL
    private let runner: CommandRunning

    public init(executableURL: URL, runner: CommandRunning = ProcessCommandRunner()) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public static func locateExecutable(bundleResourceURL: URL? = nil) -> URL? {
        var candidates = [
            "/usr/local/bin/msl-arm",
            "/opt/homebrew/bin/msl-arm",
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/msl-arm").path,
        ]
        if let bundleResourceURL {
            candidates.insert(bundleResourceURL.appendingPathComponent("bin/msl-arm").path, at: 0)
        }
        return ExecutableLocator.locate(
            overrideEnvironmentKey: "MSL_ARM_BIN",
            candidates: candidates
        )
    }

    public func listMachines() throws -> [LegacyMachine] {
        let output = try execute(["list"])
        return output.split(whereSeparator: \.isNewline).compactMap { line in
            let fields = line.split(whereSeparator: \.isWhitespace)
            guard fields.count >= 2 else { return nil }
            return LegacyMachine(
                id: String(fields[0]),
                state: RuntimeState(cliValue: String(fields[1]))
            )
        }
    }

    public func inspectMachine(_ id: String) throws -> LegacyMachine {
        let name = try Validation.machineName(id)
        let output = try execute(["config", name])
        var config: [String: String] = [:]
        for line in output.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 { config[String(parts[0])] = String(parts[1]) }
        }
        let stateResult = try runner.run(executable: executableURL, arguments: ["status", name])
        return LegacyMachine(
            id: name,
            state: stateResult.status == 0 ? .running : .stopped,
            cpus: config["CPUS"].flatMap(Int.init),
            memoryMiB: config["MEMORY_MB"].flatMap(Int.init),
            diskSize: config["DISK_SIZE"],
            sshPort: config["SSH_PORT"].flatMap(Int.init),
            guestUser: config["GUEST_USER"]
        )
    }

    public func createMachine(_ request: LegacyCreateRequest) throws {
        let name = try Validation.machineName(request.name)
        guard (1...64).contains(request.cpus),
              (512...1_048_576).contains(request.memoryMiB),
              (1...16_384).contains(request.diskGiB),
              (1...65_535).contains(request.sshPort) else {
            throw MSLControlError.invalidValue("Legacy VM resource values are out of range.")
        }
        _ = try execute([
            "init", name,
            "--cpus", String(request.cpus),
            "--memory", String(request.memoryMiB),
            "--disk", "\(request.diskGiB)G",
            "--ssh-port", String(request.sshPort),
            "--user", request.guestUser,
        ])
    }

    public func startMachine(_ id: String) throws {
        _ = try execute(["start", try Validation.machineName(id), "--detach"])
    }

    public func stopMachine(_ id: String) throws {
        _ = try execute(["stop", try Validation.machineName(id)])
    }

    public func terminalArguments(for id: String) throws -> [String] {
        ["ssh", try Validation.machineName(id)]
    }

    private func execute(_ arguments: [String]) throws -> String {
        let result = try runner.run(executable: executableURL, arguments: arguments)
        return try result.requireSuccess(executable: executableURL, arguments: arguments)
    }
}
