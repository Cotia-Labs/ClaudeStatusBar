import AppKit
import SwiftUI

/// Live Activity no notch do MacBook, no estilo da Dynamic Island: compacta,
/// mostra o mascote do Claude Code e a porcentagem à direita do notch; com o
/// mouse em cima, desce um card com a sessão em barras, o reset e a semana.
/// O notch em si continua vazio — é hardware, nada desenhado ali aparece.
@MainActor
final class NotchOverlay {
    /// Só existe a orelha direita: os menus do app da frente crescem da
    /// esquerda até o notch, e qualquer coisa ali cobre algum deles. À direita
    /// os ícones de status começam da borda da tela, e o lado do notch fica livre.
    static let earWidth: CGFloat = 76
    static let expandedSize = NSSize(width: 340, height: 100)
    /// Tempo com o cursor parado no notch antes de abrir: passar a caminho do
    /// menu não deve disparar o card.
    private static let hoverDelay: TimeInterval = 0.15

    private let store: UsageStore
    private let onClick: (NSView) -> Void
    private let onMenu: (NSView) -> Void
    /// Avisa se a faixa está na tela: com ela visível o ícone da barra de
    /// menus sai, para a informação não aparecer em dois lugares.
    var onVisibilityChange: ((Bool) -> Void)?
    /// Com o painel completo aberto, o card não volta a abrir por cima dele.
    var canExpand: () -> Bool = { true }
    private let state = NotchState()
    private var panel: NSPanel?
    private var compactFrame = NSRect.zero
    private var expandedFrame = NSRect.zero
    private var collapseWork: DispatchWorkItem?
    private var expandWork: DispatchWorkItem?
    private var screenObserver: NSObjectProtocol?
    private var mouseMonitors: [Any] = []

    init(store: UsageStore,
         onClick: @escaping (NSView) -> Void,
         onMenu: @escaping (NSView) -> Void) {
        self.store = store
        self.onClick = onClick
        self.onMenu = onMenu
        // Monitor externo, tampa fechada, resolução nova: refaz a posição.
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.apply() }
        }
    }

    /// Há uma tela com notch conectada? Decide se o item do menu aparece.
    static var isAvailable: Bool { notchedScreen != nil }

    private static var notchedScreen: NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 && $0.auxiliaryTopLeftArea != nil }
    }

    /// Mostra ou esconde conforme a preferência e a tela atual.
    func apply() {
        guard Preferences.showInNotch, let screen = Self.notchedScreen,
              let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else {
            panel?.orderOut(nil)
            onVisibilityChange?(false)
            return
        }
        state.notchHeight = screen.safeAreaInsets.top
        state.notchWidth = right.minX - left.maxX
        let top = screen.frame.maxY
        let centerX = screen.frame.minX + (left.maxX + right.minX) / 2

        compactFrame = NSRect(x: screen.frame.minX + left.maxX, y: top - state.notchHeight,
                              width: state.notchWidth + Self.earWidth, height: state.notchHeight)
        let size = Self.expandedSize
        expandedFrame = NSRect(x: centerX - size.width / 2, y: top - state.notchHeight - size.height,
                               width: size.width, height: state.notchHeight + size.height)

        panel = panel ?? makePanel()
        setWindow(expanded: state.expanded)
        panel?.orderFrontRegardless()
        onVisibilityChange?(true)
        watchMouse()
    }

    /// Hover por posição do cursor, não por tracking area: o painel muda de
    /// tamanho embaixo do mouse e a tracking area deixava de disparar. Abre ao
    /// entrar no notch e só fecha ao sair do card inteiro. Monitorar
    /// `mouseMoved` não exige permissão de acessibilidade.
    private func watchMouse() {
        guard mouseMonitors.isEmpty else { return }
        let handler: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.mouseMoved() }
        }
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .mouseMoved, handler: handler) {
            mouseMonitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .mouseMoved, handler: { event in
            handler(event)
            return event
        }) {
            mouseMonitors.append(local)
        }
    }

    private func mouseMoved() {
        guard panel?.isVisible == true else { return }
        let point = NSEvent.mouseLocation
        if state.expanded {
            if !expandedFrame.contains(point) { setExpanded(false) }
        } else if compactFrame.contains(point) {
            guard expandWork == nil, canExpand() else { return }
            let work = DispatchWorkItem { [weak self] in
                guard let self else { return }
                self.expandWork = nil
                if self.compactFrame.contains(NSEvent.mouseLocation), self.canExpand() {
                    self.setExpanded(true)
                }
            }
            expandWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.hoverDelay, execute: work)
        } else {
            expandWork?.cancel()
            expandWork = nil
        }
    }

    /// Recolhe já, sem animação: o painel completo ancora na faixa e precisa
    /// dela no tamanho compacto, senão a seta aparece embaixo do card.
    private func collapseNow() {
        expandWork?.cancel()
        expandWork = nil
        collapseWork?.cancel()
        state.expanded = false
        setWindow(expanded: false)
    }

    private func setWindow(expanded: Bool) {
        state.windowExpanded = expanded
        panel?.setFrame(expanded ? expandedFrame : compactFrame, display: true)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: .zero,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false

        let host = NotchHostingView(rootView: NotchView(store: store, state: state))
        host.onClick = { [weak self, weak host] in
            guard let self, let host else { return }
            self.collapseNow()
            self.onClick(host)
        }
        host.onMenu = { [weak self, weak host] in
            guard let self, let host else { return }
            self.collapseNow()
            self.onMenu(host)
        }
        panel.contentView = host
        return panel
    }

    /// A janela cresce antes da animação de abrir e só encolhe depois da de
    /// fechar: uma janela grande parada ali roubaria cliques do que está embaixo.
    private func setExpanded(_ expanded: Bool) {
        guard expanded != state.expanded, panel != nil else { return }
        collapseWork?.cancel()
        if expanded {
            setWindow(expanded: true)
            withAnimation(Self.spring) { state.expanded = true }
        } else {
            withAnimation(Self.spring) { state.expanded = false }
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.state.expanded else { return }
                self.setWindow(expanded: false)
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: work)
        }
    }

    private static var spring: Animation? {
        Preferences.reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.78)
    }
}

/// Estado compartilhado entre o AppKit (hover, geometria) e a view.
@MainActor
final class NotchState: ObservableObject {
    @Published var expanded = false
    /// A janela ainda está no tamanho do card (abrindo ou fechando). Nela o
    /// formato compacto precisa ser deslocado para cair sobre a orelha.
    @Published var windowExpanded = false
    var notchWidth: CGFloat = 180
    var notchHeight: CGFloat = 32
}

/// O painel nunca fica key, então o clique precisa valer já no primeiro toque.
/// Clique direito (ou control-clique) abre o menu, como no ícone da barra.
private final class NotchHostingView: NSHostingView<NotchView> {
    var onClick: (() -> Void)?
    var onMenu: (() -> Void)?

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func mouseUp(with event: NSEvent) {
        event.modifierFlags.contains(.control) ? onMenu?() : onClick?()
    }

    override func rightMouseUp(with event: NSEvent) { onMenu?() }
}

/// Retângulo colado no topo da tela: cantos de cima retos, de baixo
/// arredondados, com o raio animável para crescer junto com o card.
private struct NotchShape: Shape {
    var radius: CGFloat
    var animatableData: CGFloat {
        get { radius }
        set { radius = newValue }
    }

    func path(in rect: CGRect) -> Path {
        let r = min(radius, rect.height / 2, rect.width / 2)
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY),
                          control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r),
                          control: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

private struct NotchView: View {
    @ObservedObject var store: UsageStore
    @ObservedObject var state: NotchState

    private static let ticks = 28

    private var isStale: Bool { store.usageError != nil }
    private var tint: Color { isStale ? .gray : .claudeOrange }
    private var session: UsageWindow? { store.usage?.session }

    /// A semana só aparece como linha extra se a sessão for a de 5 horas.
    private var weekly: UsageWindow? {
        store.usage?.fiveHour == nil ? nil : store.usage?.sevenDay
    }

    private func percent(_ window: UsageWindow?) -> String {
        window.map { "\(Int($0.utilization.rounded()))%" } ?? "–"
    }

    private var width: CGFloat {
        state.expanded ? NotchOverlay.expandedSize.width
            : state.notchWidth + NotchOverlay.earWidth
    }

    /// Centro do formato compacto em relação ao do notch, quando desenhado
    /// dentro da janela grande; na janela compacta ele já a preenche.
    private var offsetX: CGFloat {
        state.expanded || !state.windowExpanded ? 0 : NotchOverlay.earWidth / 2
    }

    private var height: CGFloat {
        state.notchHeight + (state.expanded ? NotchOverlay.expandedSize.height : 0)
    }

    var body: some View {
        VStack(spacing: 0) {
            ears.frame(height: state.notchHeight)
            if state.expanded {
                details
                    .padding(.horizontal, 22)
                    .padding(.top, 4)
                    .padding(.bottom, 14)
                    .transition(.opacity.combined(with: .scale(scale: 0.92, anchor: .top)))
            }
        }
        .frame(width: width, height: height, alignment: .top)
        .background(NotchShape(radius: state.expanded ? 26 : 10).fill(Color.black))
        .offset(x: offsetX)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: Compacto

    /// A orelha fica sempre no mesmo ponto, logo à direita do notch, aberto
    /// ou fechado: o card cresce em volta dela sem o mascote pular de lugar.
    private var ears: some View {
        let leading = state.expanded ? (NotchOverlay.expandedSize.width - state.notchWidth) / 2 : 0
        return HStack(spacing: 0) {
            Color.clear.frame(width: leading + state.notchWidth)
            HStack(spacing: 7) {
                ClaudeMascot(color: tint)
                // Aberto, o número grande do card já diz isso.
                Text(percent(session))
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundColor(tint)
                    .opacity(state.expanded ? 0 : 1)
            }
            .padding(.leading, 8)
            .frame(width: NotchOverlay.earWidth, alignment: .leading)
            Spacer(minLength: 0)
        }
    }

    // MARK: Expandido

    @ViewBuilder
    private var details: some View {
        if let error = store.usageError, session == nil {
            Text(error)
                .font(.system(size: 12))
                .foregroundColor(.gray)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(L("Current session"))
                        .foregroundColor(.white.opacity(0.6))
                    Spacer()
                    if let resetsAt = session?.resetsAt {
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            Text(L("Resets in %@", Formatters.countdown(to: resetsAt, now: context.date)))
                                .foregroundColor(.white.opacity(0.6))
                                .monospacedDigit()
                        }
                    }
                }
                .font(.system(size: 12, weight: .medium))

                HStack(alignment: .center, spacing: 14) {
                    Text(percent(session))
                        .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundColor(tint)
                        .frame(minWidth: 78, alignment: .leading)
                    ticks
                }

                if let weekly {
                    HStack(spacing: 8) {
                        Text(L("Weekly"))
                            .foregroundColor(.white.opacity(0.6))
                        Capsule()
                            .fill(Color.white.opacity(0.14))
                            .overlay(alignment: .leading) {
                                GeometryReader { proxy in
                                    Capsule()
                                        .fill(tint)
                                        .frame(width: max(4, proxy.size.width * weekly.fraction))
                                }
                            }
                            .frame(height: 4)
                        Text(percent(weekly))
                            .foregroundColor(.white)
                            .monospacedDigit()
                    }
                    .font(.system(size: 11, weight: .medium))
                }
            }
        }
    }

    /// Barras verticais, como o timer do Espresso: as cheias em laranja
    /// clareando da esquerda para a direita, as vazias em cinza.
    private var ticks: some View {
        let filled = Int(((session?.fraction ?? 0) * Double(Self.ticks)).rounded(.up))
        return HStack(spacing: 3) {
            ForEach(0..<Self.ticks, id: \.self) { index in
                Capsule()
                    .fill(index < filled
                          ? tint.opacity(0.45 + 0.55 * Double(index + 1) / Double(max(filled, 1)))
                          : Color.white.opacity(0.14))
                    .frame(width: 4, height: 22)
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(Preferences.reduceMotion ? nil : .easeOut(duration: 0.5), value: filled)
    }
}

/// O mascote do banner do Claude Code (`▐▛███▜▌` / `▝▜█████▛▘` / `▘▘ ▝▝`),
/// redesenhado em pixels: cada caractere de bloco vira 2×2 quadrantes, e como a
/// célula do terminal tem o dobro da altura, cada pixel é alto, não quadrado.
struct ClaudeMascot: View {
    private static let pixels = [
        "000111111111111000",
        "000110111111011000",
        "011111111111111110",
        "000111111111111000",
        "000010100001010000",
    ]

    var color: Color
    var pixel: CGFloat = 1.5
    private var pixelHeight: CGFloat { pixel * 2 }

    var body: some View {
        Canvas { context, _ in
            for (row, line) in Self.pixels.enumerated() {
                for (column, bit) in line.enumerated() where bit == "1" {
                    let rect = CGRect(x: CGFloat(column) * pixel, y: CGFloat(row) * pixelHeight,
                                      width: pixel, height: pixelHeight)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }
        .frame(width: CGFloat(Self.pixels[0].count) * pixel,
               height: CGFloat(Self.pixels.count) * pixelHeight)
    }
}
