import Foundation

public enum RuntimeBackend: String, Codable, CaseIterable, Identifiable, Sendable {
    case appleContainer = "Apple Container"
    case qemu = "QEMU / HVF"

    public var id: String { rawValue }
}

public enum RuntimeState: String, Codable, Sendable {
    case running
    case stopped
    case starting
    case stopping
    case unknown

    public init(cliValue: String) {
        switch cliValue.lowercased() {
        case "running": self = .running
        case "stopped", "exited": self = .stopped
        case "starting": self = .starting
        case "stopping": self = .stopping
        default: self = .unknown
        }
    }
}

public enum HomeMount: String, Codable, CaseIterable, Identifiable, Sendable {
    case readWrite = "rw"
    case readOnly = "ro"
    case none

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .readWrite: return "Read & Write"
        case .readOnly: return "Read only"
        case .none: return "Not mounted"
        }
    }
}

public struct MachineSummary: Identifiable, Hashable, Codable, Sendable {
    public let id: String
    public let state: RuntimeState
    public let isDefault: Bool
    public let ipAddress: String?
    public let cpus: Int
    public let memoryBytes: UInt64
    public let diskBytes: UInt64?
    public let createdAt: Date?

    public init(
        id: String,
        state: RuntimeState,
        isDefault: Bool,
        ipAddress: String?,
        cpus: Int,
        memoryBytes: UInt64,
        diskBytes: UInt64?,
        createdAt: Date?
    ) {
        self.id = id
        self.state = state
        self.isDefault = isDefault
        self.ipAddress = ipAddress
        self.cpus = cpus
        self.memoryBytes = memoryBytes
        self.diskBytes = diskBytes
        self.createdAt = createdAt
    }

    public var memoryGiB: Int {
        max(1, Int(memoryBytes / 1_073_741_824))
    }
}

public struct MachineDetail: Hashable, Sendable {
    public let summary: MachineSummary
    public let image: String
    public let homeMount: HomeMount
    public let platform: String
    public let startedAt: Date?

    public init(
        summary: MachineSummary,
        image: String,
        homeMount: HomeMount,
        platform: String,
        startedAt: Date?
    ) {
        self.summary = summary
        self.image = image
        self.homeMount = homeMount
        self.platform = platform
        self.startedAt = startedAt
    }
}

public struct LegacyMachine: Identifiable, Hashable, Sendable {
    public let id: String
    public let state: RuntimeState
    public let cpus: Int?
    public let memoryMiB: Int?
    public let diskSize: String?
    public let sshPort: Int?
    public let guestUser: String?

    public init(
        id: String,
        state: RuntimeState,
        cpus: Int? = nil,
        memoryMiB: Int? = nil,
        diskSize: String? = nil,
        sshPort: Int? = nil,
        guestUser: String? = nil
    ) {
        self.id = id
        self.state = state
        self.cpus = cpus
        self.memoryMiB = memoryMiB
        self.diskSize = diskSize
        self.sshPort = sshPort
        self.guestUser = guestUser
    }
}

public struct HostReadiness: Equatable, Sendable {
    public let architecture: String
    public let macOSMajorVersion: Int
    public let containerPath: String?
    public let containerMachineAvailable: Bool
    public let serviceState: RuntimeState
    public let serviceMessage: String

    public init(
        architecture: String,
        macOSMajorVersion: Int,
        containerPath: String?,
        containerMachineAvailable: Bool,
        serviceState: RuntimeState,
        serviceMessage: String
    ) {
        self.architecture = architecture
        self.macOSMajorVersion = macOSMajorVersion
        self.containerPath = containerPath
        self.containerMachineAvailable = containerMachineAvailable
        self.serviceState = serviceState
        self.serviceMessage = serviceMessage
    }

    public var supportsAppleContainer: Bool {
        architecture == "arm64" && macOSMajorVersion >= 26
    }
}

public struct CreateMachineRequest: Equatable, Sendable {
    public static let defaultImageReference = "local/msl-ubuntu-machine:24.04"

    public var name: String
    public var image: String
    public var cpus: Int
    public var memoryGiB: Int
    public var homeMount: HomeMount
    public var makeDefault: Bool
    public var nestedVirtualization: Bool
    public var kernelPath: String?

    public init(
        name: String,
        image: String = CreateMachineRequest.defaultImageReference,
        cpus: Int = 4,
        memoryGiB: Int = 4,
        homeMount: HomeMount = .readWrite,
        makeDefault: Bool = true,
        nestedVirtualization: Bool = false,
        kernelPath: String? = nil
    ) {
        self.name = name
        self.image = image
        self.cpus = cpus
        self.memoryGiB = memoryGiB
        self.homeMount = homeMount
        self.makeDefault = makeDefault
        self.nestedVirtualization = nestedVirtualization
        self.kernelPath = kernelPath
    }
}

public struct MachineUpdate: Equatable, Sendable {
    public var cpus: Int
    public var memoryGiB: Int
    public var homeMount: HomeMount
    public var nestedVirtualization: Bool?
    public var kernelPath: String?

    public init(
        cpus: Int,
        memoryGiB: Int,
        homeMount: HomeMount,
        nestedVirtualization: Bool? = nil,
        kernelPath: String? = nil
    ) {
        self.cpus = cpus
        self.memoryGiB = memoryGiB
        self.homeMount = homeMount
        self.nestedVirtualization = nestedVirtualization
        self.kernelPath = kernelPath
    }
}

public struct LegacyCreateRequest: Equatable, Sendable {
    public var name: String
    public var cpus: Int
    public var memoryMiB: Int
    public var diskGiB: Int
    public var sshPort: Int
    public var guestUser: String

    public init(
        name: String,
        cpus: Int = 4,
        memoryMiB: Int = 4096,
        diskGiB: Int = 40,
        sshPort: Int = 2222,
        guestUser: String
    ) {
        self.name = name
        self.cpus = cpus
        self.memoryMiB = memoryMiB
        self.diskGiB = diskGiB
        self.sshPort = sshPort
        self.guestUser = guestUser
    }
}

public enum MSLControlError: LocalizedError, Equatable, Sendable {
    case executableNotFound(String)
    case invalidValue(String)
    case commandFailed(command: String, status: Int32, output: String)
    case invalidResponse(String)

    public var errorDescription: String? {
        switch self {
        case .executableNotFound(let name):
            return "Could not find executable: \(name)"
        case .invalidValue(let message):
            return message
        case .commandFailed(let command, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            return detail.isEmpty
                ? "Command failed (\(status)): \(command)"
                : "\(detail)\n\nCommand: \(command)"
        case .invalidResponse(let message):
            return "Invalid runtime response: \(message)"
        }
    }
}

public enum Validation {
    public static func machineName(_ value: String) throws -> String {
        guard !value.isEmpty, value.count <= 63 else {
            throw MSLControlError.invalidValue("Name must contain 1–63 characters.")
        }
        let pattern = "^[A-Za-z0-9][A-Za-z0-9_.-]*$"
        guard value.range(of: pattern, options: .regularExpression) != nil else {
            throw MSLControlError.invalidValue("Name may contain letters, numbers, dot, underscore and hyphen, and must start with a letter or number.")
        }
        return value
    }

    public static func imageReference(_ value: String) throws -> String {
        guard !value.isEmpty,
              !value.hasPrefix("-"),
              value.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw MSLControlError.invalidValue("Image must be a non-empty OCI reference without whitespace.")
        }
        return value
    }

    public static func resources(cpus: Int, memoryGiB: Int) throws {
        guard (1...64).contains(cpus) else {
            throw MSLControlError.invalidValue("CPU count must be between 1 and 64.")
        }
        guard (1...512).contains(memoryGiB) else {
            throw MSLControlError.invalidValue("Memory must be between 1 and 512 GiB.")
        }
    }
}
