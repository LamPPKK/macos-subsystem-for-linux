import Foundation
@testable import MSLControlCore
import XCTest

final class MSLControlCoreTests: XCTestCase {
    func testDecodesAppleMachineList() throws {
        let runner = StubRunner(outputs: [
            CommandResult(status: 0, output: """
            [{
              "id":"dev",
              "status":"running",
              "default":true,
              "ipAddress":"192.168.64.3",
              "cpus":6,
              "memory":8589934592,
              "diskSize":21474836480,
              "createdDate":"2026-08-21T10:30:00Z"
            }]
            """),
        ])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        let machines = try client.listMachines()

        XCTAssertEqual(machines.count, 1)
        XCTAssertEqual(machines[0].id, "dev")
        XCTAssertEqual(machines[0].state, .running)
        XCTAssertEqual(machines[0].cpus, 6)
        XCTAssertEqual(machines[0].memoryGiB, 8)
        XCTAssertTrue(machines[0].isDefault)
        XCTAssertEqual(runner.commands[0].arguments, ["machine", "list", "--format", "json"])
    }

    func testDecodesAppleMachineListWhenCommandWritesWarningToStderr() throws {
        let runner = StubRunner(outputs: [
            CommandResult(
                status: 0,
                stdout: """
                [{"id":"dev","status":"stopped","default":false,"cpus":2,"memory":2147483648}]
                """,
                stderr: "warning: using a compatibility path"
            ),
        ])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        let machines = try client.listMachines()

        XCTAssertEqual(machines.map(\.id), ["dev"])
    }

    func testCommandFailureIncludesStderrDiagnostic() {
        let result = CommandResult(status: 1, stdout: "", stderr: "service is unavailable")

        XCTAssertThrowsError(
            try result.requireSuccess(
                executable: URL(fileURLWithPath: "/fake/container"),
                arguments: ["machine", "list"]
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("service is unavailable"))
        }
    }

    func testDecodesAppleMachineInspect() throws {
        let runner = StubRunner(outputs: [
            CommandResult(status: 0, output: """
            [{
              "id":"work",
              "image":{"reference":"local/ubuntu-machine:24.04"},
              "platform":{"os":"linux","architecture":"arm64"},
              "status":"stopped",
              "startedDate":null,
              "createdDate":"2026-08-21T10:30:00Z",
              "cpus":4,
              "memory":4294967296,
              "homeMount":"ro",
              "diskSize":10737418240,
              "ipAddress":null
            }]
            """),
        ])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        let detail = try client.inspectMachine("work")

        XCTAssertEqual(detail.image, "local/ubuntu-machine:24.04")
        XCTAssertEqual(detail.platform, "linux/arm64")
        XCTAssertEqual(detail.homeMount, .readOnly)
        XCTAssertEqual(detail.summary.state, .stopped)
    }

    func testCreateUsesDocumentedMachineArguments() throws {
        let runner = StubRunner(outputs: [CommandResult(status: 0, output: "created")])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)
        let request = CreateMachineRequest(
            name: "dev-box",
            image: "alpine:3.22",
            cpus: 8,
            memoryGiB: 16,
            homeMount: .readOnly,
            makeDefault: true,
            nestedVirtualization: true,
            kernelPath: "/opt/vmlinux"
        )

        try client.createMachine(request)

        XCTAssertEqual(runner.commands[0].arguments, [
            "machine", "create", "--name", "dev-box", "--no-boot",
            "--cpus", "8", "--memory", "16G", "--home-mount", "ro",
            "--set-default", "--virtualization", "--kernel", "/opt/vmlinux", "alpine:3.22",
        ])
    }

    func testEnsureImageBuildsBundledMachineImageWhenMissing() throws {
        let context = FileManager.default.temporaryDirectory
            .appendingPathComponent("msl-image-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: context, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: context) }
        try Data("FROM ubuntu:24.04\n".utf8).write(to: context.appendingPathComponent("Containerfile"))

        let runner = StubRunner(outputs: [
            CommandResult(status: 1, stdout: "", stderr: "not found"),
            CommandResult(status: 0, stdout: "built", stderr: ""),
        ])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        try client.ensureImage(reference: CreateMachineRequest.defaultImageReference, buildContext: context)

        XCTAssertEqual(runner.commands.map(\.arguments), [
            ["image", "inspect", CreateMachineRequest.defaultImageReference],
            ["build", "--tag", CreateMachineRequest.defaultImageReference, context.path],
        ])
    }

    func testEnsureImageSkipsBuildWhenImageAlreadyExists() throws {
        let context = FileManager.default.temporaryDirectory
            .appendingPathComponent("msl-image-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: context, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: context) }
        try Data("FROM ubuntu:24.04\n".utf8).write(to: context.appendingPathComponent("Containerfile"))

        let runner = StubRunner(outputs: [CommandResult(status: 0, stdout: "{}", stderr: "")])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        try client.ensureImage(reference: CreateMachineRequest.defaultImageReference, buildContext: context)

        XCTAssertEqual(runner.commands.map(\.arguments), [
            ["image", "inspect", CreateMachineRequest.defaultImageReference],
        ])
    }

    func testUpdateDoesNotOverwriteAdvancedSettingsByDefault() throws {
        let runner = StubRunner(outputs: [CommandResult(status: 0, output: "")])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        try client.updateMachine(
            "dev",
            update: MachineUpdate(cpus: 4, memoryGiB: 6, homeMount: .readWrite)
        )

        XCTAssertEqual(runner.commands[0].arguments, [
            "machine", "set", "--name", "dev", "cpus=4", "memory=6G", "home-mount=rw",
        ])
    }

    func testRejectsUnsafeMachineNameBeforeExecution() {
        let runner = StubRunner(outputs: [])
        let client = AppleContainerClient(executableURL: URL(fileURLWithPath: "/fake/container"), runner: runner)

        XCTAssertThrowsError(try client.stopMachine("dev; reboot"))
        XCTAssertTrue(runner.commands.isEmpty)
    }

    func testLegacyListParsing() throws {
        let runner = StubRunner(outputs: [
            CommandResult(status: 0, output: "dev                      running (PID 123)\nbuild                    stopped\n"),
        ])
        let client = LegacyQEMUClient(executableURL: URL(fileURLWithPath: "/fake/msl-arm"), runner: runner)

        let machines = try client.listMachines()

        XCTAssertEqual(machines.map(\.id), ["dev", "build"])
        XCTAssertEqual(machines.map(\.state), [.running, .stopped])
    }
}

private final class StubRunner: CommandRunning {
    struct Invocation {
        let executable: URL
        let arguments: [String]
    }

    private var outputs: [CommandResult]
    private(set) var commands: [Invocation] = []

    init(outputs: [CommandResult]) {
        self.outputs = outputs
    }

    func run(executable: URL, arguments: [String]) throws -> CommandResult {
        commands.append(Invocation(executable: executable, arguments: arguments))
        guard !outputs.isEmpty else {
            return CommandResult(status: 0, output: "")
        }
        return outputs.removeFirst()
    }
}
