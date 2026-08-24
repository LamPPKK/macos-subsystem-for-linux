import Foundation

public final class AppleContainerClient: @unchecked Sendable {
    public let executableURL: URL
    private let runner: CommandRunning

    public init(executableURL: URL, runner: CommandRunning = ProcessCommandRunner()) {
        self.executableURL = executableURL
        self.runner = runner
    }

    public static func locateExecutable() -> URL? {
        ExecutableLocator.locate(
            overrideEnvironmentKey: "MSL_CONTAINER_BIN",
            candidates: [
                "/usr/local/bin/container",
                "/opt/homebrew/bin/container",
                "/usr/bin/container",
            ]
        )
    }

    public func supportsMachineCommands() -> Bool {
        guard let result = try? runner.run(executable: executableURL, arguments: ["machine", "--help"]) else {
            return false
        }
        return result.status == 0 && result.output.contains("machine")
    }

    public func serviceStatus() -> (RuntimeState, String) {
        guard let result = try? runner.run(
            executable: executableURL,
            arguments: ["system", "status", "--format", "json"]
        ) else {
            return (.unknown, "Unable to query Apple Container service.")
        }
        if result.status == 0 {
            return (.running, result.output.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let message = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        return (.stopped, message.isEmpty ? "Apple Container service is stopped." : message)
    }

    public func version() throws -> String {
        try execute(["system", "version"])
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public func startService() throws {
        _ = try execute(["system", "start", "--enable-kernel-install"])
    }

    public func stopService() throws {
        _ = try execute(["system", "stop"])
    }

    public func listMachines() throws -> [MachineSummary] {
        let output = try execute(["machine", "list", "--format", "json"])
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode([MachineListItem].self, from: Data(output.utf8)).map(\.summary)
        } catch {
            throw MSLControlError.invalidResponse("Could not decode `container machine list`: \(error.localizedDescription)")
        }
    }

    public func inspectMachine(_ id: String) throws -> MachineDetail {
        let name = try Validation.machineName(id)
        let output = try execute(["machine", "inspect", name])
        do {
            let root = try JSONSerialization.jsonObject(with: Data(output.utf8))
            guard let entries = root as? [[String: Any]], let item = entries.first else {
                throw MSLControlError.invalidResponse("Expected an array from `container machine inspect`.")
            }
            return try parseMachineDetail(item, fallbackID: name)
        } catch let error as MSLControlError {
            throw error
        } catch {
            throw MSLControlError.invalidResponse("Could not decode `container machine inspect`: \(error.localizedDescription)")
        }
    }

    public func createMachine(_ request: CreateMachineRequest) throws {
        let name = try Validation.machineName(request.name)
        let image = try Validation.imageReference(request.image)
        try Validation.resources(cpus: request.cpus, memoryGiB: request.memoryGiB)

        var arguments = [
            "machine", "create",
            "--name", name,
            "--no-boot",
            "--cpus", String(request.cpus),
            "--memory", "\(request.memoryGiB)G",
            "--home-mount", request.homeMount.rawValue,
        ]
        if request.makeDefault { arguments.append("--set-default") }
        if request.nestedVirtualization { arguments.append("--virtualization") }
        if let kernel = request.kernelPath?.trimmingCharacters(in: .whitespacesAndNewlines), !kernel.isEmpty {
            arguments += ["--kernel", kernel]
        }
        arguments.append(image)
        _ = try execute(arguments)
    }

    public func ensureImage(reference: String, buildContext: URL) throws {
        let image = try Validation.imageReference(reference)
        let containerfile = buildContext.appendingPathComponent("Containerfile")
        guard FileManager.default.fileExists(atPath: containerfile.path) else {
            throw MSLControlError.invalidValue("Machine image build context is missing: \(buildContext.path)")
        }
        let inspection = try runner.run(executable: executableURL, arguments: ["image", "inspect", image])
        if inspection.status == 0 { return }
        _ = try execute(["build", "--tag", image, buildContext.path])
    }

    public func updateMachine(_ id: String, update: MachineUpdate) throws {
        let name = try Validation.machineName(id)
        try Validation.resources(cpus: update.cpus, memoryGiB: update.memoryGiB)
        var settings = [
            "cpus=\(update.cpus)",
            "memory=\(update.memoryGiB)G",
            "home-mount=\(update.homeMount.rawValue)",
        ]
        if let virtualization = update.nestedVirtualization {
            settings.append("virtualization=\(virtualization ? "true" : "false")")
        }
        if let kernel = update.kernelPath {
            guard !kernel.contains("\n") && !kernel.contains("\r") else {
                throw MSLControlError.invalidValue("Kernel path cannot contain a newline.")
            }
            settings.append("kernel=\(kernel)")
        }
        _ = try execute(["machine", "set", "--name", name] + settings)
    }

    public func setDefaultMachine(_ id: String) throws {
        _ = try execute(["machine", "set-default", try Validation.machineName(id)])
    }

    public func stopMachine(_ id: String) throws {
        _ = try execute(["machine", "stop", try Validation.machineName(id)])
    }

    public func deleteMachine(_ id: String) throws {
        _ = try execute(["machine", "delete", try Validation.machineName(id)])
    }

    public func logs(for id: String, lines: Int = 120) throws -> String {
        let safeLines = min(max(lines, 1), 2_000)
        return try execute(["machine", "logs", "-n", String(safeLines), try Validation.machineName(id)])
    }

    public func terminalArguments(for id: String) throws -> [String] {
        ["machine", "run", "--name", try Validation.machineName(id)]
    }

    private func execute(_ arguments: [String]) throws -> String {
        let result = try runner.run(executable: executableURL, arguments: arguments)
        return try result.requireSuccess(executable: executableURL, arguments: arguments)
    }

    private func parseMachineDetail(_ item: [String: Any], fallbackID: String) throws -> MachineDetail {
        let id = item["id"] as? String ?? fallbackID
        let summary = MachineSummary(
            id: id,
            state: RuntimeState(cliValue: item["status"] as? String ?? "unknown"),
            isDefault: false,
            ipAddress: item["ipAddress"] as? String,
            cpus: integer(item["cpus"]) ?? 1,
            memoryBytes: unsignedInteger(item["memory"]) ?? 1_073_741_824,
            diskBytes: unsignedInteger(item["diskSize"]),
            createdAt: date(item["createdDate"])
        )
        return MachineDetail(
            summary: summary,
            image: imageReference(from: item["image"]) ?? "Unknown image",
            homeMount: HomeMount(rawValue: item["homeMount"] as? String ?? "rw") ?? .readWrite,
            platform: platformDescription(from: item["platform"]),
            startedAt: date(item["startedDate"])
        )
    }

    private func integer(_ value: Any?) -> Int? {
        if let number = value as? NSNumber { return number.intValue }
        if let text = value as? String { return Int(text) }
        return nil
    }

    private func unsignedInteger(_ value: Any?) -> UInt64? {
        if let number = value as? NSNumber { return number.uint64Value }
        if let text = value as? String { return UInt64(text) }
        return nil
    }

    private func date(_ value: Any?) -> Date? {
        guard let text = value as? String else { return nil }
        return ISO8601DateFormatter().date(from: text)
    }

    private func imageReference(from value: Any?) -> String? {
        if let text = value as? String { return text }
        guard let dictionary = value as? [String: Any] else { return nil }
        for key in ["reference", "name", "description"] {
            if let text = dictionary[key] as? String { return text }
        }
        for nested in dictionary.values {
            if let found = imageReference(from: nested), found.contains(":") { return found }
        }
        return nil
    }

    private func platformDescription(from value: Any?) -> String {
        if let text = value as? String { return text }
        guard let dictionary = value as? [String: Any] else { return "linux/arm64" }
        let os = dictionary["os"] as? String ?? "linux"
        let architecture = dictionary["architecture"] as? String ?? "arm64"
        return "\(os)/\(architecture)"
    }
}

private struct MachineListItem: Decodable {
    let id: String
    let status: String
    let `default`: Bool
    let ipAddress: String?
    let cpus: Int
    let memory: UInt64
    let diskSize: UInt64?
    let createdDate: Date?

    var summary: MachineSummary {
        MachineSummary(
            id: id,
            state: RuntimeState(cliValue: status),
            isDefault: `default`,
            ipAddress: ipAddress,
            cpus: cpus,
            memoryBytes: memory,
            diskBytes: diskSize,
            createdAt: createdDate
        )
    }
}
