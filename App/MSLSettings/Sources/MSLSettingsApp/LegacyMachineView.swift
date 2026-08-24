import MSLControlCore
import SwiftUI

struct LegacyMachineView: View {
    @EnvironmentObject private var model: AppModel
    let machine: LegacyMachine

    private var detail: LegacyMachine {
        guard model.legacyDetail?.id == machine.id else { return machine }
        return model.legacyDetail ?? machine
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Compatibility backend",
                    title: machine.id,
                    subtitle: "Debian ARM64 on QEMU with Apple Hypervisor Framework acceleration.",
                    state: machine.state
                )
                HStack(spacing: 10) {
                    Button { model.openLegacyTerminal(machine.id) } label: {
                        Label("Open Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
                    if machine.state == .running {
                        Button("Stop") { model.stopLegacyMachine(machine.id) }
                    } else {
                        Button("Start") { model.startLegacyMachine(machine.id) }
                    }
                    Spacer()
                }
                .disabled(model.isBusy)

                HStack(spacing: 12) {
                    MetricTile(label: "Processors", value: detail.cpus.map(String.init) ?? "—", systemImage: "cpu")
                    MetricTile(label: "Memory", value: detail.memoryMiB.map { "\($0) MiB" } ?? "—", systemImage: "memorychip")
                    MetricTile(label: "Disk", value: detail.diskSize ?? "—", systemImage: "internaldrive")
                    MetricTile(label: "SSH", value: detail.sshPort.map { "127.0.0.1:\($0)" } ?? "—", systemImage: "network")
                }

                SurfaceCard {
                    Label("Managed by the existing msl-arm CLI", systemImage: "terminal.fill")
                        .font(.headline)
                    Text("This backend stays available for macOS before 26 and for existing qcow2 VMs. Apple Container machines use a separate native store, so no disk conversion happens behind your back.")
                        .foregroundStyle(.secondary).padding(.top, 6)
                    if let user = detail.guestUser {
                        LabeledContent("Guest user", value: user).padding(.top, 12)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 1_120, alignment: .leading)
        }
        .onAppear { model.loadLegacyDetail(machine.id) }
    }
}
