import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Floating “Read” chip — draggable, auto-minimizes when idle, expands on hover.
@MainActor
final class ReadPromptController: ObservableObject {
    @Published var isMinimized = false
    @Published var isHovering = false

    private var panel: NSPanel?
    private unowned var appState: AppState
    private var minimizeWork: DispatchWorkItem?
    /// After the user drags, keep that origin for the session (and disk).
    private var stickyOrigin: NSPoint?
    private var dragStartOrigin: NSPoint?
    private var cancellables = Set<AnyCancellable>()

    private let expandedSize = NSSize(width: 176, height: 40)
    private let miniSize = NSSize(width: 40, height: 40)

    private static let posXKey = "readPromptPosX"
    private static let posYKey = "readPromptPosY"

    init(appState: AppState) {
        self.appState = appState
        appState.flowReader.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func showNearCursor() {
        ensurePanel()
        isMinimized = false
        resizePanel(animated: false)
        if let sticky = stickyOrigin {
            panel?.setFrameOrigin(clamped(sticky))
        } else if let saved = savedOrigin() {
            stickyOrigin = saved
            panel?.setFrameOrigin(clamped(saved))
        } else {
            positionNearCursor()
        }
        panel?.orderFrontRegardless()
        panel?.ignoresMouseEvents = false
        scheduleAutoMinimize(after: 3.0)
    }

    func hide() {
        cancelAutoMinimize()
        isMinimized = false
        isHovering = false
        panel?.orderOut(nil)
    }

    var isVisible: Bool {
        panel?.isVisible == true
    }

    // MARK: - Minimize

    func setMinimized(_ on: Bool, animated: Bool = true) {
        guard isMinimized != on else {
            if !on { scheduleAutoMinimize(after: 4.0) }
            return
        }
        isMinimized = on
        resizePanel(animated: animated)
        if !on {
            scheduleAutoMinimize(after: 4.0)
        }
    }

    func userInteracted() {
        setMinimized(false, animated: true)
        scheduleAutoMinimize(after: 5.0)
    }

    private func scheduleAutoMinimize(after delay: TimeInterval) {
        cancelAutoMinimize()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if self.isHovering { return }
            if case .loading = self.appState.flowReader.state { return }
            guard self.appState.pendingReadText != nil || self.appState.phase == .reading else { return }
            self.setMinimized(true, animated: true)
        }
        minimizeWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private func cancelAutoMinimize() {
        minimizeWork?.cancel()
        minimizeWork = nil
    }

    // MARK: - Drag

    func beginDragIfNeeded() {
        guard dragStartOrigin == nil else { return }
        dragStartOrigin = panel?.frame.origin
        cancelAutoMinimize()
    }

    func updateDrag(translation: CGSize) {
        beginDragIfNeeded()
        guard let start = dragStartOrigin else { return }
        // SwiftUI: +y is down. AppKit window origin: +y is up.
        let next = NSPoint(
            x: start.x + translation.width,
            y: start.y - translation.height
        )
        let clampedOrigin = clamped(next)
        panel?.setFrameOrigin(clampedOrigin)
        stickyOrigin = clampedOrigin
    }

    func endDrag() {
        if let origin = panel?.frame.origin {
            stickyOrigin = origin
            saveOrigin(origin)
        }
        dragStartOrigin = nil
        scheduleAutoMinimize(after: 4.0)
    }

    // MARK: - Panel

    private func ensurePanel() {
        if panel != nil { return }
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: expandedSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = false
        panel.isReleasedWhenClosed = false
        panel.becomesKeyOnlyIfNeeded = true
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.contentView = NSHostingView(
            rootView: ReadPromptView(appState: appState, controller: self)
        )
        self.panel = panel
    }

    private func resizePanel(animated: Bool) {
        guard let panel else { return }
        let size = isMinimized ? miniSize : expandedSize
        var frame = panel.frame
        let topY = frame.origin.y + frame.size.height
        frame.size = size
        frame.origin.y = topY - size.height
        frame.origin = clamped(frame.origin, size: size)
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func positionNearCursor() {
        guard let panel else { return }
        let mouse = NSEvent.mouseLocation
        let size = panel.frame.size
        panel.setFrameOrigin(clamped(NSPoint(x: mouse.x + 10, y: mouse.y + 10), size: size))
    }

    private func clamped(_ origin: NSPoint, size: NSSize? = nil) -> NSPoint {
        let sz = size ?? panel?.frame.size ?? expandedSize
        let screen = NSScreen.screens.first { NSMouseInRect(origin, $0.frame, false) }
            ?? NSScreen.main
        let visible = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        return NSPoint(
            x: max(visible.minX + 4, min(origin.x, visible.maxX - sz.width - 4)),
            y: max(visible.minY + 4, min(origin.y, visible.maxY - sz.height - 4))
        )
    }

    private func savedOrigin() -> NSPoint? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: Self.posXKey) != nil,
              defaults.object(forKey: Self.posYKey) != nil else { return nil }
        return NSPoint(
            x: defaults.double(forKey: Self.posXKey),
            y: defaults.double(forKey: Self.posYKey)
        )
    }

    private func saveOrigin(_ origin: NSPoint) {
        UserDefaults.standard.set(origin.x, forKey: Self.posXKey)
        UserDefaults.standard.set(origin.y, forKey: Self.posYKey)
    }
}

// MARK: - View

struct ReadPromptView: View {
    @ObservedObject var appState: AppState
    @ObservedObject var controller: ReadPromptController

    private var reader: FlowReader { appState.flowReader }
    private var isReading: Bool { appState.phase == .reading }
    private var isMinimized: Bool { controller.isMinimized }

    private let accent = Color(red: 0.50, green: 0.80, blue: 1.0)

    var body: some View {
        Group {
            if isMinimized {
                miniChip
            } else {
                expandedChip
            }
        }
        .padding(2)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
        .onHover { hovering in
            controller.isHovering = hovering
            if hovering {
                controller.setMinimized(false, animated: true)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                    if !controller.isHovering {
                        controller.setMinimized(true, animated: true)
                    }
                }
            }
        }
        .simultaneousGesture(dragGesture)
        .animation(.easeInOut(duration: 0.16), value: isMinimized)
        .animation(.easeInOut(duration: 0.12), value: isReading)
    }

    // MARK: Mini

    private var miniChip: some View {
        Button {
            controller.userInteracted()
            if isReading {
                togglePlayPause()
            } else {
                appState.confirmPendingRead()
            }
        } label: {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.32))
                    .background { Circle().fill(.ultraThinMaterial.opacity(0.4)) }
                    .overlay { Circle().strokeBorder(Color.white.opacity(0.2), lineWidth: 0.5) }
                    .frame(width: 32, height: 32)
                    .shadow(color: .black.opacity(0.2), radius: 4, y: 1)

                if case .loading = reader.state {
                    ProgressView().controlSize(.mini).tint(.white)
                } else if isReading {
                    Image(systemName: reader.state == .playing ? "pause.fill" : "play.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.92))
                        .offset(x: reader.state == .playing ? 0 : 0.5)
                } else {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.92))
                }
            }
        }
        .buttonStyle(.plain)
        .help(isReading
              ? "Click: pause/play · Drag: move · Hover: expand"
              : "Click: Read · Drag: move · Hover: expand")
    }

    // MARK: Expanded

    private var expandedChip: some View {
        HStack(spacing: 4) {
            Image(systemName: "line.3.horizontal")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: 12, height: 18)
                .help("Drag to move")

            if isReading {
                playingControls
            } else {
                readyControls
            }

            Button {
                controller.setMinimized(true, animated: true)
            } label: {
                Image(systemName: "arrow.down.right.and.arrow.up.left")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundStyle(.white.opacity(0.45))
                    .frame(width: 16, height: 16)
            }
            .buttonStyle(.plain)
            .help("Minimize")
        }
        .padding(.horizontal, 5)
        .padding(.vertical, 4)
        .background { chipBackground }
    }

    private var readyControls: some View {
        HStack(spacing: 4) {
            Button {
                controller.userInteracted()
                appState.confirmPendingRead()
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "speaker.wave.2.fill")
                        .font(.system(size: 9, weight: .semibold))
                    Text("Read")
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(.white.opacity(0.95))
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background {
                    Capsule(style: .continuous).fill(accent.opacity(0.55))
                }
            }
            .buttonStyle(.plain)

            dismissButton
        }
    }

    private var playingControls: some View {
        HStack(spacing: 4) {
            Button {
                controller.userInteracted()
                togglePlayPause()
            } label: {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.50))
                        .frame(width: 22, height: 22)
                    if case .loading = reader.state {
                        ProgressView().controlSize(.mini).tint(.white)
                    } else {
                        Image(systemName: reader.state == .playing ? "pause.fill" : "play.fill")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.white.opacity(0.95))
                            .offset(x: reader.state == .playing ? 0 : 0.5)
                    }
                }
            }
            .buttonStyle(.plain)
            .help(reader.state == .playing ? "Pause (Space)" : "Resume (Space)")

            Text(statusLabel)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)

            Button {
                controller.userInteracted()
                appState.stopFlowRead()
            } label: {
                Image(systemName: "stop.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .frame(width: 20, height: 20)
                    .background(Circle().fill(Color.white.opacity(0.12)))
            }
            .buttonStyle(.plain)
            .help("Stop (Esc)")

            dismissButton
        }
    }

    private var statusLabel: String {
        switch reader.state {
        case .paused: return "Paused"
        case .loading: return "…"
        default: return "Reading"
        }
    }

    private var dismissButton: some View {
        Button {
            if isReading {
                appState.stopFlowRead()
            } else {
                appState.dismissReadPrompt()
            }
        } label: {
            Image(systemName: "xmark")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(.white.opacity(0.55))
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
        .help("Dismiss (Esc)")
    }

    private var chipBackground: some View {
        Capsule(style: .continuous)
            .fill(Color.black.opacity(0.28))
            .background {
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial.opacity(0.35))
            }
            .overlay {
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
            }
            .shadow(color: .black.opacity(0.18), radius: 6, y: 1)
    }

    private var dragGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                controller.updateDrag(translation: value.translation)
            }
            .onEnded { _ in
                controller.endDrag()
            }
    }

    private func togglePlayPause() {
        switch reader.state {
        case .playing: reader.pause()
        case .paused: reader.resume()
        case .loading: break
        default:
            if !reader.text.isEmpty {
                reader.speak(reader.text)
            } else {
                appState.confirmPendingRead()
            }
        }
    }
}
