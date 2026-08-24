import MSLControlCore
import SwiftUI

enum NavigationItem: Hashable {
    case overview
    case appleMachine(String)
    case legacyMachine(String)
    case diagnostics
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: NavigationItem? = .overview
    @State private var showsCreateSheet = false

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 230, ideal: 270, max: 330)
        } detail: {
            detail
                .background {
                    LinearGradient(
                        colors: [Color(nsColor: .windowBackgroundColor), MSLPalette.accent.opacity(0.035)],
                        startPoint: .top,
                        endPoint: .bottomTrailing
                    )
                    .ignoresSafeArea()
                }
        }
        .toolbar {
            ToolbarItemGroup {
                if let activity = model.activityLabel {
                    ProgressView().controlSize(.small).help(activity)
                }
                Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                    .disabled(model.isBusy)
                Button { showsCreateSheet = true } label: { Label("New environment", systemImage: "plus") }
                    .disabled(model.isBusy)
                    .keyboardShortcut("n", modifiers: .command)
            }
        }
        .sheet(isPresented: $showsCreateSheet) {
            CreateMachineView()
                .environmentObject(model)
        }
        .sheet(isPresented: Binding(
            get: { model.logsText != nil },
            set: { if !$0 { model.logsText = nil } }
        )) {
            LogsView(title: model.logsTitle, text: model.logsText ?? "")
        }
        .alert("MSL Settings", isPresented: Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "")
        }
        .onAppear { model.refresh() }
    }

    private var sidebar: some View {
        List(selection: $selection) {
            Label("Overview", systemImage: "square.grid.2x2")
                .tag(NavigationItem.overview)

            Section("Apple Container") {
                if model.appleMachines.isEmpty {
                    Label("No machines", systemImage: "shippingbox")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(model.appleMachines) { machine in
                        HStack(spacing: 9) {
                            StatusPill(state: machine.state, compact: true)
                            Text(machine.id).lineLimit(1)
                            Spacer(minLength: 4)
                            if machine.isDefault {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(MSLPalette.warning)
                                    .accessibilityLabel("Default")
                            }
                        }
                        .tag(NavigationItem.appleMachine(machine.id))
                    }
                }
            }

            if !model.legacyMachines.isEmpty {
                Section("QEMU / HVF") {
                    ForEach(model.legacyMachines) { machine in
                        HStack(spacing: 9) {
                            StatusPill(state: machine.state, compact: true)
                            Text(machine.id).lineLimit(1)
                        }
                        .tag(NavigationItem.legacyMachine(machine.id))
                    }
                }
            }

            Section {
                Label("Diagnostics", systemImage: "stethoscope")
                    .tag(NavigationItem.diagnostics)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 8) {
                StatusPill(state: model.readiness.serviceState, compact: true)
                Text("Apple Container")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(12)
            .background(.bar)
        }
        .navigationTitle("MSL Settings")
    }

    @ViewBuilder
    private var detail: some View {
        switch selection ?? .overview {
        case .overview:
            OverviewView(showsCreateSheet: $showsCreateSheet)
        case .appleMachine(let id):
            if let machine = model.appleMachines.first(where: { $0.id == id }) {
                AppleMachineView(machine: machine)
                    .id("apple-\(id)")
            } else {
                MissingSelectionView()
            }
        case .legacyMachine(let id):
            if let machine = model.legacyMachines.first(where: { $0.id == id }) {
                LegacyMachineView(machine: machine)
                    .id("qemu-\(id)")
            } else {
                MissingSelectionView()
            }
        case .diagnostics:
            DiagnosticsView()
        }
    }
}

private struct MissingSelectionView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 42))
                .foregroundStyle(.secondary)
            Text("Environment not found").font(.title2.bold())
            Text("Refresh the runtime list and select another environment.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct LogsView: View {
    @Environment(\.dismiss) private var dismiss
    let title: String
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(title).font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            ScrollView([.horizontal, .vertical]) {
                Text(text)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
            }
            .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(22)
        .frame(minWidth: 760, minHeight: 500)
    }
}
