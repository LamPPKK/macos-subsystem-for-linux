import Foundation
import MSLControlCore
import SwiftUI

struct CreateMachineView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var backend: RuntimeBackend = .appleContainer
    @State private var name = "dev"
    @State private var cpus = 4
    @State private var memoryGiB = 4
    @State private var image = CreateMachineRequest.defaultImageReference
    @State private var homeMount: HomeMount = .readWrite
    @State private var makeDefault = true
    @State private var nestedVirtualization = false
    @State private var kernelPath = ""
    @State private var diskGiB = 40
    @State private var sshPort = 2222
    @State private var guestUser = Self.defaultGuestUser

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("New Linux environment").font(.title2.bold())
                    Text("Create the environment now; open its shell in Terminal when ready.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .accessibilityLabel("Close")
            }
            .padding(22)

            Divider()
            Form {
                Picker("Runtime", selection: $backend) {
                    if model.appleClient != nil { Text("Apple Container").tag(RuntimeBackend.appleContainer) }
                    if model.legacyClient != nil { Text("QEMU / HVF").tag(RuntimeBackend.qemu) }
                }
                TextField("Name", text: $name)
                Stepper("CPU cores: \(cpus)", value: $cpus, in: 1...64)

                if backend == .appleContainer {
                    appleFields
                } else {
                    qemuFields
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            Divider()
            HStack {
                runtimeNote
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") { create() }
                    .buttonStyle(.borderedProminent)
                    .tint(MSLPalette.accent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || model.isBusy)
            }
            .padding(18)
        }
        .frame(width: 620, height: 650)
        .onAppear {
            if model.appleClient == nil && model.legacyClient != nil { backend = .qemu }
        }
    }

    private var appleFields: some View {
        Group {
            TextField("OCI image", text: $image)
            Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB, in: 1...512)
            Picker("macOS home", selection: $homeMount) {
                ForEach(HomeMount.allCases) { option in Text(option.title).tag(option) }
            }
            Toggle("Set as default machine", isOn: $makeDefault)
            DisclosureGroup("Advanced") {
                Toggle("Nested virtualization", isOn: $nestedVirtualization)
                TextField("Custom kernel path (optional)", text: $kernelPath)
                Text("The default Ubuntu systemd image is built automatically from the Containerfile bundled with MSL Settings the first time it is used. Custom images must contain `/sbin/init`.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var qemuFields: some View {
        Group {
            Stepper("Memory: \(memoryGiB) GiB", value: $memoryGiB, in: 1...1024)
            Stepper("Disk: \(diskGiB) GiB", value: $diskGiB, in: 4...16_384)
            Stepper("SSH port: \(sshPort)", value: $sshPort, in: 1024...65_535)
            TextField("Guest user", text: $guestUser)
            Text("The QEMU backend creates a Debian ARM64 cloud-image VM. Its first initialization may download the base image.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var runtimeNote: some View {
        if backend == .appleContainer && model.readiness.serviceState != .running {
            Label("Start Apple Container first", systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(MSLPalette.warning)
        } else {
            Text(backend.rawValue).font(.caption).foregroundStyle(.secondary)
        }
    }

    private var canCreate: Bool {
        guard !name.isEmpty else { return false }
        if backend == .appleContainer {
            return !image.isEmpty && model.readiness.serviceState == .running && model.readiness.containerMachineAvailable
        }
        return !guestUser.isEmpty
    }

    private func create() {
        if backend == .appleContainer {
            model.createAppleMachine(
                CreateMachineRequest(
                    name: name,
                    image: image,
                    cpus: cpus,
                    memoryGiB: memoryGiB,
                    homeMount: homeMount,
                    makeDefault: makeDefault,
                    nestedVirtualization: nestedVirtualization,
                    kernelPath: kernelPath.isEmpty ? nil : kernelPath
                )
            ) { success in if success { dismiss() } }
        } else {
            model.createLegacyMachine(
                LegacyCreateRequest(
                    name: name,
                    cpus: cpus,
                    memoryMiB: memoryGiB * 1024,
                    diskGiB: diskGiB,
                    sshPort: sshPort,
                    guestUser: guestUser
                )
            ) { success in if success { dismiss() } }
        }
    }

    private static var defaultGuestUser: String {
        let value = NSUserName()
        return value == "root" || value.isEmpty ? "developer" : value
    }
}
