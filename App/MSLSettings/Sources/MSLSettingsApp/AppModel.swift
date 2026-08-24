import AppKit
import Foundation
import MSLControlCore

@MainActor
final class AppModel: ObservableObject {
    @Published var readiness: HostReadiness
    @Published var appleMachines: [MachineSummary] = []
    @Published var legacyMachines: [LegacyMachine] = []
    @Published var appleDetail: MachineDetail?
    @Published var legacyDetail: LegacyMachine?
    @Published var activityLabel: String?
    @Published var alertMessage: String?
    @Published var logsTitle = ""
    @Published var logsText: String?

    nonisolated let appleClient: AppleContainerClient?
    nonisolated let legacyClient: LegacyQEMUClient?
    nonisolated private let operationQueue = DispatchQueue(label: "dev.lamppkk.msl-settings.runtime", qos: .userInitiated)
    private let terminalLauncher = TerminalLauncher()

    init() {
        let appleURL = AppleContainerClient.locateExecutable()
        let legacyURL = LegacyQEMUClient.locateExecutable(bundleResourceURL: Bundle.main.resourceURL)
        appleClient = appleURL.map { AppleContainerClient(executableURL: $0) }
        legacyClient = legacyURL.map { LegacyQEMUClient(executableURL: $0) }
        readiness = HostReadiness(
            architecture: Self.hostArchitecture,
            macOSMajorVersion: ProcessInfo.processInfo.operatingSystemVersion.majorVersion,
            containerPath: appleURL?.path,
            containerMachineAvailable: false,
            serviceState: .unknown,
            serviceMessage: "Not checked yet."
        )
    }

    var isBusy: Bool { activityLabel != nil }

    func refresh() {
        guard !isBusy else { return }
        activityLabel = "Refreshing runtimes…"
        let apple = appleClient
        let legacy = legacyClient
        let architecture = Self.hostArchitecture
        let osMajor = ProcessInfo.processInfo.operatingSystemVersion.majorVersion

        operationQueue.async {
            var supportsMachine = false
            var serviceState: RuntimeState = .unknown
            var serviceMessage = apple == nil ? "Apple Container CLI is not installed." : "Not available."
            var appleMachines: [MachineSummary] = []
            var legacyMachines: [LegacyMachine] = []
            var nonfatalMessages: [String] = []

            if let apple {
                supportsMachine = apple.supportsMachineCommands()
                (serviceState, serviceMessage) = apple.serviceStatus()
                if serviceState == .running && supportsMachine {
                    do { appleMachines = try apple.listMachines() }
                    catch { nonfatalMessages.append(error.localizedDescription) }
                }
            }
            if let legacy {
                do { legacyMachines = try legacy.listMachines() }
                catch { nonfatalMessages.append("QEMU: \(error.localizedDescription)") }
            }

            let report = HostReadiness(
                architecture: architecture,
                macOSMajorVersion: osMajor,
                containerPath: apple?.executableURL.path,
                containerMachineAvailable: supportsMachine,
                serviceState: serviceState,
                serviceMessage: serviceMessage
            )
            let result = RuntimeRefreshResult(
                readiness: report,
                appleMachines: appleMachines,
                legacyMachines: legacyMachines,
                messages: nonfatalMessages
            )
            DispatchQueue.main.async {
                self.readiness = result.readiness
                self.appleMachines = result.appleMachines
                self.legacyMachines = result.legacyMachines
                self.activityLabel = nil
                if !result.messages.isEmpty {
                    self.alertMessage = result.messages.joined(separator: "\n\n")
                }
            }
        }
    }

    func loadAppleDetail(_ id: String) {
        guard let appleClient else { return }
        let existingSummary = appleMachines.first(where: { $0.id == id })
        activityLabel = "Loading \(id)…"
        operationQueue.async {
            do {
                var detail = try appleClient.inspectMachine(id)
                if let summary = existingSummary {
                    detail = MachineDetail(
                        summary: MachineSummary(
                            id: detail.summary.id,
                            state: detail.summary.state,
                            isDefault: summary.isDefault,
                            ipAddress: detail.summary.ipAddress,
                            cpus: detail.summary.cpus,
                            memoryBytes: detail.summary.memoryBytes,
                            diskBytes: detail.summary.diskBytes,
                            createdAt: detail.summary.createdAt
                        ),
                        image: detail.image,
                        homeMount: detail.homeMount,
                        platform: detail.platform,
                        startedAt: detail.startedAt
                    )
                }
                let resolvedDetail = detail
                DispatchQueue.main.async {
                    self.appleDetail = resolvedDetail
                    self.activityLabel = nil
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.finishWithErrorMessage(message) }
            }
        }
    }

    func loadLegacyDetail(_ id: String) {
        guard let legacyClient else { return }
        activityLabel = "Loading \(id)…"
        operationQueue.async {
            do {
                let detail = try legacyClient.inspectMachine(id)
                DispatchQueue.main.async {
                    self.legacyDetail = detail
                    self.activityLabel = nil
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.finishWithErrorMessage(message) }
            }
        }
    }

    func startService() {
        perform("Starting Apple Container…") { try self.appleClientOrThrow().startService() }
    }

    func stopService() {
        perform("Stopping Apple Container…") { try self.appleClientOrThrow().stopService() }
    }

    func createAppleMachine(
        _ request: CreateMachineRequest,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        let imageBuildContext = Bundle.main.resourceURL?
            .appendingPathComponent("images/ubuntu-machine", isDirectory: true)
        perform("Creating \(request.name)…", completion: completion) {
            let client = try self.appleClientOrThrow()
            if request.image == CreateMachineRequest.defaultImageReference {
                guard let imageBuildContext else {
                    throw MSLControlError.invalidValue("The bundled Ubuntu machine Containerfile is missing.")
                }
                try client.ensureImage(reference: request.image, buildContext: imageBuildContext)
            }
            try client.createMachine(request)
        }
    }

    func updateAppleMachine(_ id: String, update: MachineUpdate) {
        perform("Applying settings to \(id)…") {
            try self.appleClientOrThrow().updateMachine(id, update: update)
        }
    }

    func stopAppleMachine(_ id: String) {
        perform("Stopping \(id)…") { try self.appleClientOrThrow().stopMachine(id) }
    }

    func deleteAppleMachine(_ id: String) {
        perform("Deleting \(id)…") { try self.appleClientOrThrow().deleteMachine(id) }
    }

    func setDefaultAppleMachine(_ id: String) {
        perform("Setting default machine…") { try self.appleClientOrThrow().setDefaultMachine(id) }
    }

    func showLogs(for id: String) {
        guard let appleClient else { return }
        activityLabel = "Reading logs…"
        operationQueue.async {
            do {
                let logs = try appleClient.logs(for: id)
                DispatchQueue.main.async {
                    self.logsTitle = "\(id) logs"
                    self.logsText = logs.isEmpty ? "No logs were returned." : logs
                    self.activityLabel = nil
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { self.finishWithErrorMessage(message) }
            }
        }
    }

    func openAppleTerminal(_ id: String) {
        do {
            let client = try appleClientOrThrow()
            try terminalLauncher.open(
                executable: client.executableURL,
                arguments: try client.terminalArguments(for: id),
                title: "MSL — \(id)",
                scriptID: "apple-\(id)"
            )
        } catch { finishWithError(error) }
    }

    func createLegacyMachine(
        _ request: LegacyCreateRequest,
        completion: @escaping @MainActor @Sendable (Bool) -> Void
    ) {
        perform("Creating \(request.name) with QEMU…", completion: completion) {
            try self.legacyClientOrThrow().createMachine(request)
        }
    }

    func startLegacyMachine(_ id: String) {
        perform("Starting \(id)…") { try self.legacyClientOrThrow().startMachine(id) }
    }

    func stopLegacyMachine(_ id: String) {
        perform("Stopping \(id)…") { try self.legacyClientOrThrow().stopMachine(id) }
    }

    func openLegacyTerminal(_ id: String) {
        if legacyMachines.first(where: { $0.id == id })?.state == .running {
            launchLegacyTerminal(id)
            return
        }
        perform("Starting \(id)…", completion: { success in
            if success { self.launchLegacyTerminal(id) }
        }) {
            try self.legacyClientOrThrow().startMachine(id)
        }
    }

    private func perform(
        _ label: String,
        completion: @escaping @MainActor @Sendable (Bool) -> Void = { _ in },
        operation: @escaping @Sendable () throws -> Void
    ) {
        guard !isBusy else { return }
        activityLabel = label
        operationQueue.async {
            do {
                try operation()
                DispatchQueue.main.async {
                    self.activityLabel = nil
                    completion(true)
                    self.refresh()
                }
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async {
                    self.finishWithErrorMessage(message)
                    completion(false)
                }
            }
        }
    }

    nonisolated private func appleClientOrThrow() throws -> AppleContainerClient {
        guard let appleClient else { throw MSLControlError.executableNotFound("container") }
        return appleClient
    }

    nonisolated private func legacyClientOrThrow() throws -> LegacyQEMUClient {
        guard let legacyClient else { throw MSLControlError.executableNotFound("msl-arm") }
        return legacyClient
    }

    private func launchLegacyTerminal(_ id: String) {
        do {
            let client = try legacyClientOrThrow()
            try terminalLauncher.open(
                executable: client.executableURL,
                arguments: try client.terminalArguments(for: id),
                title: "MSL — \(id)",
                scriptID: "qemu-\(id)"
            )
        } catch { finishWithError(error) }
    }

    private func finishWithError(_ error: Error) {
        finishWithErrorMessage(error.localizedDescription)
    }

    private func finishWithErrorMessage(_ message: String) {
        activityLabel = nil
        alertMessage = message
    }

    private static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }
}

private struct RuntimeRefreshResult: Sendable {
    let readiness: HostReadiness
    let appleMachines: [MachineSummary]
    let legacyMachines: [LegacyMachine]
    let messages: [String]
}
