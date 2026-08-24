import SwiftUI

struct DiagnosticsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    eyebrow: "System check",
                    title: "Diagnostics",
                    subtitle: "Checks are read-only. Runtime start and stop actions are always explicit.",
                    state: model.readiness.serviceState
                )
                SurfaceCard {
                    row("Architecture", model.readiness.architecture, model.readiness.architecture == "arm64")
                    Divider().padding(.vertical, 7)
                    row("macOS", "\(model.readiness.macOSMajorVersion)", model.readiness.macOSMajorVersion >= 26)
                    Divider().padding(.vertical, 7)
                    row("Container CLI", model.readiness.containerPath ?? "Not installed", model.readiness.containerPath != nil)
                    Divider().padding(.vertical, 7)
                    row("Machine commands", model.readiness.containerMachineAvailable ? "Available" : "Unavailable", model.readiness.containerMachineAvailable)
                    Divider().padding(.vertical, 7)
                    row("QEMU fallback", model.legacyClient?.executableURL.path ?? "Not installed", model.legacyClient != nil)
                }
                SurfaceCard {
                    Text("Runtime response").font(.headline)
                    Text(model.readiness.serviceMessage)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .foregroundStyle(.secondary)
                        .padding(.top, 6)
                }
                HStack {
                    Button("Run checks again") { model.refresh() }
                        .buttonStyle(.borderedProminent).tint(MSLPalette.accent)
                    Spacer()
                    Link("Apple Container documentation", destination: URL(string: "https://github.com/apple/container")!)
                }
            }
            .padding(28)
            .frame(maxWidth: 1_000, alignment: .leading)
        }
    }

    private func row(_ label: String, _ value: String, _ good: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: good ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(good ? MSLPalette.accent : MSLPalette.warning)
            Text(label).fontWeight(.medium)
            Spacer()
            Text(value)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
    }
}
