import MSLControlCore
import SwiftUI

private enum AdvancedSetting: String, CaseIterable, Identifiable {
    case unchanged = "No change"
    case enabled = "Enable"
    case disabled = "Disable"
    var id: String { rawValue }
}

struct AppleMachineView: View {
    @EnvironmentObject private var model: AppModel
    let machine: MachineSummary
    @State private var cpus = 4
    @State private var memoryGiB = 4
    @State private var homeMount: HomeMount = .readWrite
    @State private var virtualization: AdvancedSetting = .unchanged
    @State private var kernelPath = ""
    @State private var confirmsDelete = false

    private var detail: MachineDetail? {
        guard model.appleDetail?.summary.id == machine.id else { return nil }
        return model.appleDetail
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: machine.isDefault ? "Default Apple machine" : "Apple Container machine",
                    title: machine.id,
                    subtitle: detail?.image ?? "Loading machine configuration…",
                    state: machine.state
                )
                actionBar
                HStack(spacing: 12) {
                    MetricTile(label: "Processors", value: "\(machine.cpus)", systemImage: "cpu")
                    MetricTile(label: "Memory", value: machine.memoryBytes.mslFileSize, systemImage: "memorychip")
                    MetricTile(label: "Storage", value: machine.diskBytes?.mslFileSize ?? "Managed", systemImage: "internaldrive")
                    MetricTile(label: "Address", value: machine.ipAddress ?? "—", systemImage: "network")
                }
                settingsCard
                metadataCard
            }
            .padding(28)
            .frame(maxWidth: 1_120, alignment: .leading)
        }
        .onAppear {
            seedEditor(from: machine)
            model.loadAppleDetail(machine.id)
        }
        .onChange(of: model.appleDetail) { newValue in
            guard let newValue, newValue.summary.id == machine.id else { return }
            seedEditor(from: newValue)
        }
        .confirmationDialog(
            "Delete \(machine.id)?",
            isPresented: $confirmsDelete,
            titleVisibility: .visible
        ) {
            Button("Delete machine and its persistent storage", role: .destructive) {
                model.deleteAppleMachine(machine.id)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Stop the machine and export anything you need first.")
        }
    }

    private var actionBar: some View {
        HStack(spacing: 10) {
            Button { model.openAppleTerminal(machine.id) } label: {
                Label("Open Terminal", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
            .tint(MSLPalette.accent)
            if machine.state == .running {
                Button { model.stopAppleMachine(machine.id) } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
            }
            Button { model.showLogs(for: machine.id) } label: {
                Label("Logs", systemImage: "doc.text.magnifyingglass")
            }
            Spacer()
            Menu {
                if !machine.isDefault {
                    Button("Set as default") { model.setDefaultAppleMachine(machine.id) }
                }
                Divider()
                Button("Delete machine…", role: .destructive) { confirmsDelete = true }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .disabled(model.isBusy)
    }

    private var settingsCard: some View {
        SurfaceCard {
            Text("Machine resources").font(.title3.bold())
            Text("Changes are written with `container machine set` and take effect after the next stop and start.")
                .font(.callout).foregroundStyle(.secondary).padding(.top, 2)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 14) {
                GridRow {
                    Text("CPU cores")
                    Stepper("\(cpus)", value: $cpus, in: 1...64).labelsHidden()
                    Text("\(cpus)").font(.body.monospaced()).frame(width: 36, alignment: .trailing)
                }
                GridRow {
                    Text("Memory")
                    Stepper("\(memoryGiB) GiB", value: $memoryGiB, in: 1...512).labelsHidden()
                    Text("\(memoryGiB) GiB").font(.body.monospaced()).frame(width: 72, alignment: .trailing)
                }
                GridRow {
                    Text("macOS home")
                    Picker("Home mount", selection: $homeMount) {
                        ForEach(HomeMount.allCases) { option in Text(option.title).tag(option) }
                    }.labelsHidden()
                    EmptyView()
                }
            }
            .padding(.vertical, 14)
            DisclosureGroup("Advanced") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Nested virtualization", selection: $virtualization) {
                        ForEach(AdvancedSetting.allCases) { Text($0.rawValue).tag($0) }
                    }
                    TextField("Custom kernel path (blank means no change)", text: $kernelPath)
                    Text("Nested virtualization needs an M3-or-newer Mac and a guest kernel built with KVM support.")
                        .font(.caption).foregroundStyle(.secondary)
                }.padding(.top, 10)
            }
            HStack {
                Spacer()
                Button("Apply settings") { applySettings() }
                    .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
                    .disabled(model.isBusy)
            }.padding(.top, 12)
        }
    }

    private var metadataCard: some View {
        SurfaceCard {
            Text("Runtime details").font(.headline)
            LabeledContent("Platform", value: detail?.platform ?? "linux/arm64")
            LabeledContent("Home mount", value: detail?.homeMount.title ?? "—")
            LabeledContent("Created", value: detail?.summary.createdAt?.formatted() ?? "—")
            LabeledContent("Last started", value: detail?.startedAt?.formatted() ?? "—")
        }
    }

    private func seedEditor(from summary: MachineSummary) {
        cpus = summary.cpus
        memoryGiB = summary.memoryGiB
    }

    private func seedEditor(from detail: MachineDetail) {
        seedEditor(from: detail.summary)
        homeMount = detail.homeMount
    }

    private func applySettings() {
        let nested: Bool?
        switch virtualization {
        case .unchanged: nested = nil
        case .enabled: nested = true
        case .disabled: nested = false
        }
        let kernel = kernelPath.isEmpty ? nil : kernelPath
        model.updateAppleMachine(
            machine.id,
            update: MachineUpdate(
                cpus: cpus,
                memoryGiB: memoryGiB,
                homeMount: homeMount,
                nestedVirtualization: nested,
                kernelPath: kernel
            )
        )
    }
}
