import SwiftUI

/// Popover content: one animated bar per rate-limit window, plus the
/// service status of the Anthropic platform.
struct UsagePanel: View {
    @ObservedObject var store: UsageStore
    var onRefresh: () -> Void
    var onOpenMenu: (NSView) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if let usage = store.usage {
                VStack(spacing: 12) {
                    ForEach(Array(usage.rows.enumerated()), id: \.offset) { index, row in
                        UsageRow(title: row.title,
                                 subtitle: row.subtitle,
                                 window: row.window,
                                 delay: Double(index) * 0.07)
                    }
                }
                .opacity(store.usageError == nil ? 1 : 0.55)
            } else if store.usageError == nil {
                ProgressView().controlSize(.small).frame(maxWidth: .infinity)
            }

            if let error = store.usageError {
                errorBox(error)
            }

            Divider()
            statusFooter
        }
        .padding(16)
        .frame(width: 300)
    }

    private var header: some View {
        HStack {
            Text("Limites de uso do plano")
                .font(.system(size: 13, weight: .semibold))
            Spacer()
            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                    .animation(store.isRefreshing
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false)
                               : .default,
                               value: store.isRefreshing)
            }
            .buttonStyle(.plain)
            .help("Atualizar agora")

            MenuButton(action: onOpenMenu)
                .frame(width: 16, height: 16)
        }
    }

    private func errorBox(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(message).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
                if let lastGood = store.lastGoodUpdate, store.usage != nil {
                    Text("Mostrando dados de \(Formatters.absolute(from: lastGood)).")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }

    private var statusFooter: some View {
        VStack(alignment: .leading, spacing: 6) {
            serviceStatus
            HStack(spacing: 4) {
                Text(AppInfo.displayName)
                Text(AppInfo.signature)
                Spacer()
                Text(AppInfo.versionLabel)
            }
            .font(.system(size: 10))
            .foregroundStyle(.tertiary)
            .contentShape(Rectangle())
            .onTapGesture { NSWorkspace.shared.open(AppInfo.publisherURL) }
            .help("Abrir o repositório da \(AppInfo.publisher)")
        }
    }

    private var serviceStatus: some View {
        HStack(spacing: 6) {
            let severity = store.status.map { Severity.fromIndicator($0.status.indicator) } ?? .unknown
            Circle()
                .fill(severity.swiftUIColor)
                .frame(width: 7, height: 7)
            Text(store.status?.status.description ?? "Status indisponível")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer()
            if let lastUpdate = store.lastUpdate {
                Text(Formatters.absolute(from: lastUpdate))
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { NSWorkspace.shared.open(URL(string: "https://status.anthropic.com")!) }
    }
}

/// A single window: label, live countdown, and a bar that animates to the
/// new utilization whenever a refresh lands.
private struct UsageRow: View {
    let title: String
    let subtitle: String
    let window: UsageWindow
    let delay: Double

    @State private var shown: Double = 0

    private var level: UsageLevel { UsageLevel(fraction: window.fraction) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 12, weight: .medium))
                Spacer()
                Text("\(Int(window.utilization.rounded()))% usado")
                    .font(.system(size: 11, weight: .semibold).monospacedDigit())
                    .foregroundStyle(level.swiftUIColor)
                    .contentTransition(.numericText())
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))
                    Capsule()
                        .fill(level.gradient)
                        .frame(width: max(3, geometry.size.width * shown))
                }
            }
            .frame(height: 6)

            HStack {
                Text(subtitle).font(.system(size: 10)).foregroundStyle(.tertiary)
                Spacer()
                if let resetsAt = window.resetsAt {
                    ResetLabel(date: resetsAt)
                }
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.7, dampingFraction: 0.8).delay(delay)) {
                shown = window.fraction
            }
        }
        .onChange(of: window.fraction) { newValue in
            withAnimation(.spring(response: 0.6, dampingFraction: 0.85)) { shown = newValue }
        }
    }
}

/// Ticks every second so the "Reinicia em 2 h 46 min" countdown stays live.
private struct ResetLabel: View {
    let date: Date

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let remaining = date.timeIntervalSince(context.date)
            Text(remaining > 0 && remaining < 12 * 3600
                 ? "Reinicia em \(Formatters.countdown(to: date, now: context.date))"
                 : "Reinicia \(Formatters.absolute(from: date))")
                .font(.system(size: 10).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}

/// Bridges the settings NSMenu, which needs a real NSView to anchor to.
private struct MenuButton: NSViewRepresentable {
    let action: (NSView) -> Void

    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(image: NSImage(systemSymbolName: "ellipsis.circle",
                                             accessibilityDescription: "Opções")!,
                              target: context.coordinator,
                              action: #selector(Coordinator.fire(_:)))
        button.isBordered = false
        button.toolTip = "Opções"
        return button
    }

    func updateNSView(_ nsView: NSButton, context: Context) {
        context.coordinator.action = action
    }

    func makeCoordinator() -> Coordinator { Coordinator(action: action) }

    final class Coordinator {
        var action: (NSView) -> Void
        init(action: @escaping (NSView) -> Void) { self.action = action }
        @objc func fire(_ sender: NSButton) { action(sender) }
    }
}

extension UsageLevel {
    var swiftUIColor: Color {
        switch self {
        case .comfortable: return .green
        case .watch: return .yellow
        case .tight: return .orange
        case .critical: return .red
        }
    }

    var gradient: LinearGradient {
        LinearGradient(colors: [swiftUIColor.opacity(0.75), swiftUIColor],
                       startPoint: .leading, endPoint: .trailing)
    }
}

extension Severity {
    var swiftUIColor: Color {
        switch self {
        case .operational: return .green
        case .degraded: return .yellow
        case .partialOutage: return .orange
        case .majorOutage: return .red
        case .maintenance: return .blue
        case .unknown: return .gray
        }
    }
}
