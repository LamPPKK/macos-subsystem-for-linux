import MSLControlCore
import SwiftUI

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var showsCreateSheet: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "Linux environments",
                    title: "Subsystem control center",
                    subtitle: "Configure persistent Linux machines here, then open a real login shell in Terminal.",
                    state: model.readiness.serviceState
                )
                HStack(spacing: 12) {
                    MetricTile(label: "Apple machines", value: "\(model.appleMachines.count)", systemImage: "shippingbox")
                    MetricTile(label: "Running", value: "\(runningCount)", systemImage: "bolt.horizontal.circle")
                    MetricTile(label: "Legacy VMs", value: "\(model.legacyMachines.count)", systemImage: "server.rack")
                }
                runtimeCard
                HStack(alignment: .top, spacing: 14) {
                    infoCard("Terminal-first", "terminal.fill", "Open Terminal boots the selected machine when needed and opens its login shell.")
                    infoCard("Compatible fallback", "arrow.triangle.branch", "Existing QEMU/HVF machines remain available on macOS releases before 26.")
                }
                recentMachines
            }
            .padding(28)
            .frame(maxWidth: 1_120, alignment: .leading)
        }
    }

    private var runtimeCard: some View {
        SurfaceCard {
            HStack(alignment: .top, spacing: 18) {
                Image(systemName: "shippingbox.fill")
                    .font(.system(size: 25))
                    .foregroundStyle(MSLPalette.accent)
                    .frame(width: 54, height: 54)
                    .background(MSLPalette.accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 13))
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Apple Container").font(.title3.bold())
                        StatusPill(state: model.readiness.serviceState)
                    }
                    Text(containerSummary).foregroundStyle(.secondary)
                    runtimeActions.padding(.top, 4)
                }
            }
        }
    }

    @ViewBuilder private var runtimeActions: some View {
        if model.readiness.serviceState == .running {
            HStack {
                Button("New environment") { showsCreateSheet = true }
                    .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
                Button("Stop service") { model.stopService() }
            }
        } else if model.appleClient != nil {
            Button("Start service") { model.startService() }
                .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
        } else {
            Link("Get Apple Container", destination: URL(string: "https://github.com/apple/container/releases/latest")!)
                .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
        }
    }

    @ViewBuilder private var recentMachines: some View {
        if !model.appleMachines.isEmpty {
            Text("RECENT ENVIRONMENTS").font(.caption2.bold()).tracking(1.3).foregroundStyle(.secondary)
            ForEach(model.appleMachines.prefix(3)) { machine in
                SurfaceCard {
                    HStack {
                        StatusPill(state: machine.state, compact: true)
                        Text(machine.id).font(.headline)
                        Text("\(machine.cpus) CPU · \(machine.memoryBytes.mslFileSize)")
                            .font(.caption.monospaced()).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Terminal") { model.openAppleTerminal(machine.id) }
                    }
                }
            }
        }
    }

    private var runningCount: Int {
        model.appleMachines.filter { $0.state == .running }.count
            + model.legacyMachines.filter { $0.state == .running }.count
    }

    private var containerSummary: String {
        if !model.readiness.supportsAppleContainer {
            return "Apple Container requires Apple Silicon and macOS 26 or later. The QEMU/HVF backend remains available."
        }
        if model.appleClient == nil { return "Install Apple's signed Container package, then start its system service." }
        if !model.readiness.containerMachineAvailable { return "Update Container to a release with persistent machine support." }
        return "Persistent Linux machines backed by Apple's virtualization stack and OCI images."
    }

    private func infoCard(_ title: String, _ symbol: String, _ text: String) -> some View {
        SurfaceCard {
            Label(title, systemImage: symbol).font(.headline)
            Text(text).foregroundStyle(.secondary).padding(.top, 6)
        }
    }
}
