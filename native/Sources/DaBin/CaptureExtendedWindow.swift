import AppKit
import SwiftUI

private final class CaptureExtendedNativeWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) { performClose(sender) }
}

/// One reusable window. The originating detail view stays mounted, including
/// its scroll position; zoom is owned outside the tab content hierarchy.
@MainActor
final class CaptureExtendedWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    private let state: AppState
    private let theme: ThemeSettings
    private weak var returnWindow: NSWindow?
    private var shutDown = false
    private var hasPositioned = false
    private var zoomStates: [UUID: CaptureZoomState] = [:]
    private var recentCaptureIDs: [UUID] = []
    private(set) var captureID: UUID?
    private(set) var zoom = CaptureZoomState()
    private var alertReceipts: [TaskTimerCompletion] = []
    var onReturn: (() -> Void)?

    init(state: AppState, theme: ThemeSettings) {
        self.state = state
        self.theme = theme
        window = CaptureExtendedNativeWindow(contentRect: CGRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        super.init()
        window.title = "DaBin Extended View"
        window.minSize = CGSize(width: 480, height: 500)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.collectionBehavior = [.fullScreenAuxiliary]
        window.backgroundColor = .windowBackgroundColor
        window.level = .floating // Match the compact board so it cannot obscure this view.
        window.identifier = NSUserInterfaceItemIdentifier("dabin-extended-capture")
    }

    func show(capture: Capture, draft: CaptureDraft) {
        guard !shutDown, state.store.captures.contains(where: { $0 === capture }) else { return }
        if captureID != capture.id {
            zoom = zoomStates[capture.id] ?? CaptureZoomState()
            zoomStates[capture.id] = zoom
            recentCaptureIDs.removeAll { $0 == capture.id }
            recentCaptureIDs.append(capture.id)
            while recentCaptureIDs.count > 16 { zoomStates.removeValue(forKey: recentCaptureIDs.removeFirst()) }
        }
        captureID = capture.id
        let hasList = !alertReceipts.isEmpty
        let content = CaptureExtendedScreen(state: state, capture: capture, draft: draft,
            theme: theme, zoom: zoom, onClose: { [weak self] in self?.window.performClose(nil) },
            onReminderList: hasList ? { [weak self] in self?.showReminderListContent() } : nil)
        window.contentView = NSHostingView(rootView: content)
        present()
    }

    func showCompletedReminders(_ receipts: [TaskTimerCompletion]) {
        guard !shutDown, !receipts.isEmpty else { return }
        alertReceipts = receipts
        if receipts.count == 1 {
            state.openExtendedCapture(receipts[0].taskID)
        } else { showReminderListContent(); present() }
    }

    private func showReminderListContent() {
        captureID = nil
        window.contentView = NSHostingView(rootView: CompletedReminderList(state: state, receipts: alertReceipts,
            theme: theme, open: { [weak self] receipt in self?.state.openExtendedCapture(receipt.taskID) },
            close: { [weak self] in self?.window.performClose(nil) }))
    }

    private func present() {
        if !window.isVisible {
            returnWindow = NSApp.keyWindow
            let screen = returnWindow?.screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
            if let screen {
                let available = screen.visibleFrame.insetBy(dx: 16, dy: 16)
                if !hasPositioned {
                    let size = CGSize(width: min(980, available.width), height: min(720, available.height))
                    window.setFrame(CGRect(x: available.midX - size.width / 2, y: available.midY - size.height / 2,
                                           width: size.width, height: size.height), display: false)
                    hasPositioned = true
                } else {
                    // Keep the user's size/position; recover when its display disappears.
                    let target = NSScreen.screens.first { $0.visibleFrame.contains(window.frame.origin) }?.visibleFrame
                        ?? available
                    var frame = window.frame
                    frame.size.width = min(frame.width, target.width)
                    frame.size.height = min(frame.height, target.height)
                    frame.origin.x = max(target.minX, min(frame.minX, target.maxX - frame.width))
                    frame.origin.y = max(target.minY, min(frame.minY, target.maxY - frame.height))
                    window.setFrame(frame, display: false)
                }
            }
        }
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        state.persistDrafts()
        window.contentView = nil
        captureID = nil
        alertReceipts.removeAll()
        guard !shutDown else { return }
        if let returnWindow, returnWindow.isVisible { returnWindow.makeKeyAndOrderFront(nil) }
        else { onReturn?() }
    }

    func shutdown() {
        shutDown = true
        onReturn = nil
        window.close()
        window.contentView = nil
        zoomStates.removeAll()
        recentCaptureIDs.removeAll()
    }
}

@MainActor
struct CaptureExtendedScreen: View {
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    @ObservedObject var theme: ThemeSettings
    @ObservedObject var zoom: CaptureZoomState
    let onClose: () -> Void
    var onReminderList: (() -> Void)? = nil
    @State private var selection: CaptureDetailSection = .comments

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                Button(action: onClose) { Label("Back", systemImage: "chevron.backward") }
                    .buttonStyle(.bordered).accessibilityLabel("Back to capture page")
                    .accessibilityIdentifier("extended-close")
                VStack(alignment: .leading, spacing: 4) {
                    Text(capture.title).font(.system(size: 17, weight: .semibold, design: .rounded)).lineLimit(2)
                    Text(metadata).font(.system(size: 11)).foregroundStyle(Palette.muted).lineLimit(2)
                        .accessibilityIdentifier("extended-capture-metadata").buddyHelp(metadata)
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let onReminderList {
                    Button(action: onReminderList) { Image(systemName: "list.bullet").frame(width: 30, height: 30) }
                        .buttonStyle(.plain).accessibilityLabel("Completed reminders")
                        .buddyHelp("Return to completed reminders")
                }
            }.padding(14)
            Divider()
            GeometryReader { geometry in
                let wide = geometry.size.width >= 820
                let layout = wide ? AnyLayout(HStackLayout(spacing: 0)) : AnyLayout(VStackLayout(spacing: 0))
                layout {
                    canvas.frame(maxWidth: .infinity, maxHeight: .infinity)
                    Divider()
                    panel.frame(width: wide ? min(360, geometry.size.width * 0.34) : nil,
                                height: wide ? nil : min(310, max(190, geometry.size.height * 0.43)))
                }
            }
        }.background(Palette.background).foregroundStyle(Palette.foreground)
            .environment(\.daBinAccent, theme.accent).tint(theme.accent)
            .environment(\.daBinTooltipsEnabled, theme.showTooltips)
            .preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
            .accessibilityElement(children: .contain).accessibilityIdentifier("extended-capture-view")
            .onExitCommand(perform: onClose)
            .onDisappear { state.persistDrafts() }
    }

    private var metadata: String {
        var parts = [captureReceiptText(capture, includeWeekday: true), captureTypeLabel(capture.kind)]
        if let source = capture.sourceApplicationName, !source.isEmpty { parts.append(source) }
        else if let source = capture.sourceURL, !source.isEmpty { parts.append(source) }
        else if let source = capture.sourceFilePath, !source.isEmpty { parts.append(source) }
        return parts.joined(separator: " · ")
    }

    private var canvas: some View {
        VStack(spacing: 0) {
            CaptureZoomControls(zoom: zoom).padding(.horizontal, 10).padding(.vertical, 8)
            Divider()
            ExtendedCaptureCanvas(store: state.store, capture: capture, zoom: zoom)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("extended-capture-canvas")
        }
    }

    private var panel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                CaptureDetailPanels(state: state, capture: capture, draft: draft, selection: $selection)
                if let message = draft.visibleMessage {
                    Text(message).font(.system(size: 12)).foregroundStyle(draft.hasError ? Color.red : Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if draft.hasChanges {
                    Button("Save changes") { state.saveDetail(capture: capture, draft: draft) }
                        .buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                }
            }.padding(14)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("extended-capture-side-panel")
    }
}

@MainActor
private struct CompletedReminderList: View {
    @ObservedObject var state: AppState
    let receipts: [TaskTimerCompletion]
    @ObservedObject var theme: ThemeSettings
    let open: (TaskTimerCompletion) -> Void
    let close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("\(receipts.count) completed reminders", systemImage: "alarm")
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                Spacer()
                Button("Close", action: close)
            }
            Text("Acknowledged. Open a capture to review it or set another reminder.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
            ScrollView {
                LazyVStack(spacing: 10) {
                    ForEach(receipts) { receipt in
                        let capture = state.store.captures.first { $0.id == receipt.taskID }
                        Button { open(receipt) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: receipt.reminderRevision == nil ? "timer" : "alarm")
                                    .font(.system(size: 20)).foregroundStyle(theme.accent)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(capture?.title ?? receipt.title).font(.system(size: 15, weight: .medium)).lineLimit(3)
                                    if let date = receipt.dueAt {
                                        Text(date.formatted(date: .abbreviated, time: .shortened))
                                            .font(.system(size: 12)).foregroundStyle(Palette.muted)
                                    }
                                    if capture == nil { Text("Capture no longer available").font(.system(size: 12)) }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(Palette.muted)
                            }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
                                .background(Palette.soft, in: RoundedRectangle(cornerRadius: 12))
                                .contentShape(RoundedRectangle(cornerRadius: 12))
                        }.buttonStyle(.plain).disabled(capture == nil)
                            .accessibilityLabel("Open reminder: \(capture?.title ?? receipt.title)")
                    }
                }
            }
        }.padding(22).background(Palette.background).foregroundStyle(Palette.foreground)
            .environment(\.daBinAccent, theme.accent).preferredColorScheme(theme.darkModeEnabled ? .dark : .light)
            .accessibilityElement(children: .contain).accessibilityIdentifier("completed-reminder-list").onExitCommand(perform: close)
    }
}
