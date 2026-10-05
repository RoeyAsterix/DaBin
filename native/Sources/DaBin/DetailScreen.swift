import AppKit
import SwiftUI

/// Size from the visible viewport, never from the unbounded scroll content.
/// Resizing changes metrics without replacing editors, playback, or PDF state.
struct DetailLayout {
    let viewport: CGSize
    var factor: CGFloat = 1
    private var zoom: WorkspaceZoomLayout { WorkspaceZoomLayout(factor: factor) }
    private var logicalWidth: CGFloat { viewport.width / zoom.factor }
    var horizontalInset: CGFloat { zoom.value(min(24, max(16, 16 + (logicalWidth - 380) * 0.025))) }
    var contentWidth: CGFloat { max(0, viewport.width - horizontalInset * 2) }
    var previewHeight: CGFloat { max(zoom.value(100), min(viewport.height - 70, contentWidth * 0.85)) }
    var commentHeight: CGFloat { min(zoom.value(260), max(zoom.value(108), viewport.height * 0.25)) }
    // Responsive typography follows the physical viewport, so zooming a fixed
    // window cannot shrink its font by reducing the logical layout width.
    // Keep the existing reading sizes as upper bounds even in expanded views.
    var titleSize: CGFloat { min(28, zoom.fontSize(min(28, max(21, 21 + (viewport.width - 380) / 110)))) }
    var bodySize: CGFloat { min(17, zoom.fontSize(min(17, max(15, 15 + (viewport.width - 380) / 360)))) }
    var usesTaskColumns: Bool { contentWidth / zoom.factor >= 860 }
    var sectionSpacing: CGFloat { zoom.value(usesTaskColumns ? 20 : 14) }
    private var taskColumnWidth: CGFloat { usesTaskColumns ? (contentWidth - sectionSpacing) / 2 : contentWidth }
    var attachmentMinimumWidth: CGFloat { min(zoom.value(220), max(zoom.value(125), taskColumnWidth * 0.3)) }
    var attachmentHeight: CGFloat { min(zoom.value(200), max(zoom.value(100), taskColumnWidth * 0.28)) }
}

/// OCR is a reading surface, not metadata. Keep its native text container at
/// the actual content width and use the same body typography as the capture.
/// A bounded scroll viewport avoids growing the whole page for a long index.
@MainActor
struct CaptureRecognizedTextPanel: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var capture: Capture
    let layout: DetailLayout
    var copied = false
    let onCopy: () -> Void
    @State private var showAll = false

    private var inset: CGFloat { zoom.value(12) }
    private var readerWidth: CGFloat { max(0, layout.contentWidth - inset * 2) }
    private var preview: String { String(capture.indexedText.prefix(2_000)) }
    private var readingText: String { showAll ? capture.indexedText : preview }
    private var readerHeight: CGFloat {
        let measured = (preview as NSString).boundingRect(
            with: CGSize(width: max(1, readerWidth - 8), height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: [.font: NSFont.systemFont(ofSize: layout.bodySize)])
        let maximum = min(320, max(120, layout.viewport.height * 0.35))
        return min(maximum, max(40, ceil(measured.height) + 16))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Recognized text", systemImage: "text.viewfinder")
                .font(.system(size: zoom.fontSize(13), weight: .medium)).foregroundStyle(accent)
            CaptureRecognizedTextReader(text: readingText, fontSize: layout.bodySize,
                                        width: readerWidth, height: readerHeight)
                .frame(maxWidth: .infinity).frame(height: readerHeight)
            if capture.indexedText.count > 2_000 {
                Text(showAll ? "All \(capture.indexedText.count.formatted()) characters"
                     : "Preview · first 2,000 of \(capture.indexedText.count.formatted()) characters")
                    .font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            BuddyActionFlow {
                BuddyIconButton(symbol: copied ? "checkmark" : "doc.on.doc",
                                title: "Copy all recognized text", visualLabel: copied ? "Copied" : "Copy all text",
                                action: onCopy)
                    .accessibilityIdentifier("recognized-text-copy")
                if capture.indexedText.count > 2_000 {
                    BuddyIconButton(symbol: showAll ? "chevron.up" : "chevron.down",
                                    title: showAll ? "Show recognized text preview" : "Show all recognized text",
                                    visualLabel: showAll ? "Show preview" : "Show all text") { showAll.toggle() }
                        .accessibilityIdentifier("recognized-text-toggle")
                }
            }
        }
        .padding(inset)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("recognized-text-panel")
        .onChange(of: capture.id) { _, _ in showAll = false }
    }
}

/// NSTextView wraps long tokens and mixed scripts within a finite container.
/// Its identity stays mounted through resize, zoom, and preview expansion.
@MainActor
private struct CaptureRecognizedTextReader: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let text: String
    let fontSize: CGFloat
    let width: CGFloat
    let height: CGFloat

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        let reader = NSTextView(frame: scroll.contentView.bounds)
        reader.isEditable = false
        reader.isSelectable = true
        reader.isRichText = false
        reader.drawsBackground = false
        reader.isVerticallyResizable = true
        reader.isHorizontallyResizable = false
        reader.autoresizingMask = [.width]
        reader.minSize = .zero
        reader.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        reader.textContainerInset = NSSize(width: 4, height: 4)
        reader.textContainer?.lineFragmentPadding = 0
        reader.textContainer?.widthTracksTextView = true
        reader.textContainer?.heightTracksTextView = false
        reader.textContainer?.containerSize = NSSize(width: max(1, width - 8), height: .greatestFiniteMagnitude)
        reader.setAccessibilityIdentifier("recognized-text-body")
        reader.setAccessibilityLabel("Recognized text")
        scroll.documentView = reader
        updateNSView(scroll, context: context)
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let reader = scroll.documentView as? NSTextView else { return }
        // Mounted inactive panes retain selection and reading position, but
        // cannot keep receiving keyboard input after navigation.
        if !isEnabled, let window = reader.window, window.firstResponder === reader {
            window.makeFirstResponder(nil)
        }
        let position = scroll.contentView.bounds.origin
        let selections = reader.selectedRanges
        let font = NSFont.systemFont(ofSize: fontSize)
        if reader.string != text || reader.font?.pointSize != fontSize {
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineBreakMode = .byWordWrapping
            paragraph.lineSpacing = fontSize * 0.2
            reader.textStorage?.setAttributedString(NSAttributedString(string: text,
                attributes: [.font: font, .foregroundColor: NSColor(Palette.foreground), .paragraphStyle: paragraph]))
            let count = (text as NSString).length
            reader.selectedRanges = selections.map { value in
                let range = value.rangeValue, start = min(count, range.location)
                return NSValue(range: NSRange(location: start, length: min(range.length, count - start)))
            }
        }
        reader.textColor = NSColor(Palette.foreground)
        if let container = reader.textContainer { reader.layoutManager?.ensureLayout(for: container) }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: min(position.y, max(0, reader.frame.height - scroll.contentView.bounds.height))))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
}

/// AppKit owns both wrapping and the field editor. A finite preferred width and
/// explicit two-line cell keep the unfocused title readable at normal zoom;
/// editing still uses the native field editor with its undo/IME/selection state.
@MainActor
private struct CaptureTaskTitleField: NSViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    @Binding var text: String
    let fontSize: CGFloat
    @Binding var isFocused: Bool

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeNSView(context: Context) -> CaptureTaskTitleTextField {
        let field = CaptureTaskTitleTextField()
        field.isEditable = true; field.isSelectable = true
        field.isBordered = false; field.isBezeled = false; field.drawsBackground = false
        field.focusRingType = .none; field.usesSingleLineMode = false
        field.maximumNumberOfLines = 2
        field.cell?.wraps = true; field.cell?.isScrollable = false
        field.cell?.lineBreakMode = .byWordWrapping
        field.cell?.truncatesLastVisibleLine = true
        field.placeholderString = "Task title"
        field.identifier = NSUserInterfaceItemIdentifier("detail-title")
        field.setAccessibilityElement(true); field.setAccessibilityRole(.textField)
        field.setAccessibilityIdentifier("detail-title"); field.setAccessibilityLabel("Task title")
        field.delegate = context.coordinator
        field.onWindowChanged = { [weak field, weak coordinator = context.coordinator] in
            guard let field else { return }; coordinator?.applyFocus(to: field)
        }
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        updateNSView(field, context: context)
        return field
    }

    func updateNSView(_ field: CaptureTaskTitleTextField, context: Context) {
        context.coordinator.parent = self
        let editor = field.currentEditor() as? NSTextView
        if editor?.hasMarkedText() != true, field.stringValue != text, editor?.string != text {
            let selection = editor?.selectedRange()
            field.stringValue = text
            if let editor, let selection {
                let count = (text as NSString).length, start = min(selection.location, count)
                editor.setSelectedRange(NSRange(location: start, length: min(selection.length, count - start)))
            }
        }
        let system = NSFont.systemFont(ofSize: fontSize, weight: .semibold)
        let font = system.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: fontSize) } ?? system
        if field.font != font {
            if let editor, field.window?.firstResponder === editor {
                // Updating NSControl.font may end field editing. Update the
                // public cell while the native editor owns input instead, and
                // keep its selection when typography changes during resize.
                if !editor.hasMarkedText() {
                    let selections = editor.selectedRanges
                    field.cell?.font = font; editor.font = font
                    let count = (editor.string as NSString).length
                    editor.selectedRanges = selections.map { value in
                        let range = value.rangeValue, start = min(count, range.location)
                        return NSValue(range: NSRange(location: start, length: min(range.length, count - start)))
                    }
                    field.invalidateIntrinsicContentSize()
                }
            } else { field.font = font }
        }
        field.textColor = NSColor(Palette.foreground)
        if field.isEnabled != isEnabled { field.isEnabled = isEnabled }
        field.setAccessibilityHelp(text)
        context.coordinator.applyFocus(to: field)
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView field: CaptureTaskTitleTextField,
                      context: Context) -> CGSize? {
        guard let width = proposal.width, width.isFinite, width > 0 else { return nil }
        if abs(field.preferredMaxLayoutWidth - width) > 0.25 { field.preferredMaxLayoutWidth = width }
        let font = field.font ?? .systemFont(ofSize: fontSize, weight: .semibold)
        let line = ceil(NSLayoutManager().defaultLineHeight(for: font))
        let measured = field.sizeThatFits(NSSize(width: width, height: .greatestFiniteMagnitude))
        // Cell padding is included, but the title never reserves a third line.
        return CGSize(width: width, height: min(line * 2 + 4, max(line + 4, ceil(measured.height))))
    }

    static func dismantleNSView(_ field: CaptureTaskTitleTextField, coordinator: Coordinator) {
        field.onWindowChanged = nil; field.delegate = nil
        if let window = field.window, let editor = field.currentEditor(), window.firstResponder === editor {
            window.makeFirstResponder(nil)
        }
    }

    @MainActor final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: CaptureTaskTitleField
        private var focusRevision = 0
        private var previousFocusIntent: Bool?
        private var pendingFocusClear = false
        init(parent: CaptureTaskTitleField) { self.parent = parent }

        func applyFocus(to field: NSTextField) {
            // A false binding records no programmatic focus request. Native
            // click/Tab focus can precede the delegate's first text edit, so
            // replaying an unchanged false value would cancel user input.
            if previousFocusIntent == true && !parent.isFocused { pendingFocusClear = true }
            if parent.isFocused { pendingFocusClear = false }
            previousFocusIntent = parent.isFocused
            focusRevision += 1; let revision = focusRevision
            DispatchQueue.main.async { [weak self, weak field] in
                guard let self, let field, self.focusRevision == revision, let window = field.window else { return }
                let owned = field.currentEditor().map { window.firstResponder === $0 } ?? (window.firstResponder === field)
                if self.parent.isEnabled && self.parent.isFocused {
                    self.pendingFocusClear = false
                    if !owned { window.makeFirstResponder(field) }
                } else if owned && (!self.parent.isEnabled || self.pendingFocusClear) {
                    self.pendingFocusClear = false; window.makeFirstResponder(nil)
                } else if !owned { self.pendingFocusClear = false }
            }
        }
        func controlTextDidBeginEditing(_ notification: Notification) {
            parent.isFocused = true
        }
        func controlTextDidChange(_ notification: Notification) {
            guard let field = notification.object as? NSTextField else { return }
            let value = (field.currentEditor() as? NSTextView)?.string ?? field.stringValue
            if parent.text != value { parent.text = value }
        }
        func controlTextDidEndEditing(_ notification: Notification) {
            if let field = notification.object as? NSTextField, parent.text != field.stringValue { parent.text = field.stringValue }
            parent.isFocused = false
        }
        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            // A vertical title field keeps Return as text input; primary Save
            // remains explicit and cannot accidentally commit another draft.
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                textView.insertNewlineIgnoringFieldEditor(nil); return true
            }
            return false
        }
    }
}

@MainActor
private final class CaptureTaskTitleTextField: NSTextField {
    // This borderless representable measures its whole view. Standard field
    // alignment adds two points on each side, making SwiftUI's proposed width
    // disagree with the native frame and repeatedly changing wrapping width.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0) }
    var onWindowChanged: (() -> Void)?
    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); onWindowChanged?() }
    override func layout() {
        super.layout()
        if bounds.width > 0, abs(preferredMaxLayoutWidth - bounds.width) > 0.25 {
            preferredMaxLayoutWidth = bounds.width
        }
    }
}

/// Page navigation stays outside the scrolling reading/editing surfaces.
/// The mounted panes retain local edits, OCR selection, and media/PDF state.
enum CapturePageSection: String, CaseIterable, Identifiable {
    case preview, task, comments, reminder, text, details
    var id: String { rawValue }
    var title: String {
        switch self {
        case .preview: return "Preview"
        case .task: return "Task"
        case .comments: return "Comments"
        case .reminder: return "Reminder"
        case .text: return "Text"
        case .details: return "Details"
        }
    }
    var accessibilityTitle: String { self == .text ? "Recognized text" : title }
    var focus: String {
        switch self {
        case .preview: return "capture-preview"
        case .comments: return "comment"
        case .text: return "recognized-text"
        default: return rawValue
        }
    }
    static func from(focus: String?) -> Self? {
        if focus == "title" { return .task }
        return allCases.first { $0.focus == focus }
    }
}

@MainActor
struct DetailScreen: View {
    @Environment(\.workspaceZoom) private var zoom
    @Environment(\.daBinAccent) private var accent
    @ObservedObject var state: AppState
    @ObservedObject var capture: Capture
    @ObservedObject var draft: CaptureDraft
    // The native title editor owns focus; this state records explicit focus
    // intent and follows its delegate without a second SwiftUI focus engine.
    @State private var focusedField: String?
    @State private var copiedSearchableText = false
    @State private var pageSection: CapturePageSection = .preview

    private var sections: [CapturePageSection] {
        CapturePageSection.allCases.filter {
            ($0 != .task || capture.isTask) && ($0 != .text || ContentIndexService.isEligible(capture.kind))
        }
    }
    private var controlFont: CGFloat { min(16, zoom.fontSize(13)) }

    var body: some View {
        GeometryReader { geometry in
            let layout = DetailLayout(viewport: geometry.size, factor: zoom.factor)
            VStack(spacing: 0) {
                header(layout: layout)
                sectionNavigation(layout: layout)
                    .padding(.horizontal, layout.horizontalInset).padding(.vertical, 8)
                    .background(Palette.soft.opacity(0.4))
                    .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
                GeometryReader { paneGeometry in
                    let paneLayout = DetailLayout(viewport: paneGeometry.size, factor: zoom.factor)
                    ZStack(alignment: .topLeading) {
                        pane(.preview, layout: paneLayout) { originalContent(layout: paneLayout).id("capture-preview") }
                        if capture.isTask {
                            pane(.task, layout: paneLayout) {
                                TaskFocusControls(state: state, capture: capture, compact: false, showsSchedule: false, emphasizesCountdown: false)
                                taskWorkspace(layout: paneLayout).id("task").accessibilityIdentifier("task-workspace")
                            }
                        }
                        pane(.comments, layout: paneLayout) {
                            CaptureDetailPanels(state: state, capture: capture, draft: draft,
                                selection: .constant(.comments), showsTabs: false, isActive: pageSection == .comments)
                        }
                        pane(.reminder, layout: paneLayout) {
                            CaptureDetailPanels(state: state, capture: capture, draft: draft,
                                selection: .constant(.reminder), showsTabs: false, isActive: pageSection == .reminder)
                        }
                        if ContentIndexService.isEligible(capture.kind) {
                            pane(.text, layout: paneLayout) { searchableText(layout: paneLayout) }
                        }
                        pane(.details, layout: paneLayout) {
                            CaptureSourceView(capture: capture)
                            CaptureTrailView(state: state, capture: capture, compact: false)
                            if let error = capture.previewError, !error.isEmpty {
                                Label(error, systemImage: "info.circle")
                                    .font(.system(size: min(14, zoom.fontSize(12)))).foregroundStyle(Palette.muted)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            if capture.kind != .task { original }
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                saveFooter
            }.frame(width: geometry.size.width, height: geometry.size.height)
                .accessibilityElement(children: .contain).accessibilityIdentifier("detail-content")
                .onAppear { restoreSection() }
                .onChange(of: state.detailFocus) { _, target in
                    if let section = CapturePageSection.from(focus: target), sections.contains(section) { pageSection = section }
                    focusedField = target == "title" ? "title" : nil
                }
                .onChange(of: capture.isTask) { _, isTask in
                    selectSection(isTask ? .task : .preview)
                }
        }
    }

    private func restoreSection() {
        if let section = CapturePageSection.from(focus: state.detailFocus), sections.contains(section) {
            pageSection = section
        } else { pageSection = capture.isTask ? .task : .preview }
        focusedField = state.detailFocus == "title" ? "title" : nil
    }

    private func selectSection(_ section: CapturePageSection) {
        guard sections.contains(section) else { return }
        if pageSection != section { state.workspaceViewport = nil }
        pageSection = section
        state.detailFocus = section.focus
    }

    private func header(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                if capture.isTask { TaskStatusButton(state: state, capture: capture) }
                Group {
                    if capture.isTask {
                        CaptureTaskTitleField(text: $draft.title, fontSize: layout.titleSize,
                            isFocused: Binding(get: { focusedField == "title" }, set: { focused in
                                if focused { focusedField = "title" }
                                else if focusedField == "title" { focusedField = nil }
                            }))
                            .background(NavigationEditorRegion(target: .detailTitle))
                            .accessibilityLabel("Task title").accessibilityIdentifier("detail-title")
                            .onChange(of: draft.title) { _, _ in draft.message = nil }
                            .buddyHelp(draft.title)
                    } else {
                        Text(capture.title).lineLimit(2).accessibilityIdentifier("detail-title")
                            .captureDragSource(state: state, capture: capture).buddyHelp(capture.title)
                    }
                }.font(.system(size: layout.titleSize, weight: .semibold, design: .rounded))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { identityMetadata; Spacer(minLength: 0); capturedDate }
                VStack(alignment: .leading, spacing: 4) { identityMetadata; capturedDate }
            }
            actionRail
            CaptureConversionUndo(state: state, capture: capture)
        }.padding(.horizontal, layout.horizontalInset).padding(.vertical, 12)
    }

    private var identityMetadata: some View {
        HStack(spacing: 7) {
            CaptureProjectPickerButton(state: state, capture: capture)
            if capture.isTask {
                Text(capture.isCompleted ? "COMPLETED" : "TASK")
                    .font(.system(size: min(12, zoom.fontSize(10)), weight: .medium)).foregroundStyle(Palette.muted)
                    .accessibilityIdentifier("detail-task-caption").captureDragSource(state: state, capture: capture)
                if draft.planning.priority != .none { TaskPriorityTag(priority: draft.planning.priority) }
            }
        }
    }

    private var capturedDate: some View {
        Button { state.showCaptureDay(capture) } label: {
            Label(captureReceiptText(capture, includeWeekday: true), systemImage: "calendar")
                .monospacedDigit().lineLimit(1).fixedSize(horizontal: true, vertical: false)
        }.font(.system(size: min(18, zoom.fontSize(16)), weight: .medium)).buttonStyle(.plain)
            .foregroundStyle(Palette.muted)
            .accessibilityLabel("Captured \(prettyDay(capture.captureDay)) at \(captureClock(capture))")
            .accessibilityIdentifier("detail-captured-at").buddyHelp("Show original capture day")
    }

    private func sectionNavigation(layout: DetailLayout) -> some View {
        Group {
            if layout.contentWidth / zoom.factor >= 610 {
                HStack(spacing: 4) { ForEach(sections) { section in sectionButton(section) } }
            } else {
                HStack(spacing: 5) {
                    Menu {
                        ForEach(sections) { section in
                            Button { selectSection(section) } label: {
                                if pageSection == section { Label(section.accessibilityTitle, systemImage: "checkmark") }
                                else { Text(section.accessibilityTitle) }
                            }.accessibilityIdentifier("detail-section-option-" + section.rawValue)
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Text(pageSection.title).fontWeight(.semibold)
                            Image(systemName: "chevron.up.chevron.down").font(.system(size: 9, weight: .semibold))
                        }.padding(.horizontal, 9).frame(minHeight: 32).contentShape(RoundedRectangle(cornerRadius: 7))
                            .background(accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                    }.menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                        .accessibilityLabel("Capture section: " + pageSection.accessibilityTitle)
                        .accessibilityIdentifier("detail-section-picker").buddyHelp("Switch capture section")
                    Spacer(minLength: 0)
                    sectionButton(.comments)
                    sectionButton(.reminder)
                }
            }
        }.font(.system(size: controlFont))
            .accessibilityElement(children: .contain).accessibilityLabel("Capture sections")
            .accessibilityIdentifier("detail-section-navigation")
    }

    private func sectionButton(_ section: CapturePageSection) -> some View {
        Button { selectSection(section) } label: {
            Text(section.title).font(.system(size: controlFont, weight: pageSection == section ? .semibold : .medium))
                .padding(.horizontal, 9).frame(minHeight: 32).contentShape(RoundedRectangle(cornerRadius: 7))
                .background(pageSection == section ? accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }.buttonStyle(.plain).foregroundStyle(pageSection == section ? accent : Palette.muted)
            .accessibilityLabel(section.accessibilityTitle)
            .accessibilityAddTraits(pageSection == section ? .isSelected : [])
            .accessibilityIdentifier("detail-section-" + section.rawValue)
    }

    private func pane<Content: View>(_ section: CapturePageSection, layout: DetailLayout,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        let active = pageSection == section
        return ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(.horizontal, layout.horizontalInset).padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .id("detail-pane-top-" + section.rawValue)
                    .background {
                        if active { Color.clear.workspaceZoomItem("capture:" + capture.id.uuidString) }
                    }
            }.background {
                if active {
                    WorkspaceScrollHistory(anchor: state.workspaceViewport, contextID: "detail-" + capture.id.uuidString + "-" + section.rawValue,
                        onAnchor: { state.workspaceViewport = $0 }).allowsHitTesting(false).accessibilityHidden(true)
                }
            }
            .onChange(of: draft.editingCommentID) { _, _ in
                if active && section == .comments { proxy.scrollTo("detail-pane-top-comments", anchor: .top) }
            }
        }.opacity(active ? 1 : 0).allowsHitTesting(active).disabled(!active).accessibilityHidden(!active)
            .accessibilityIdentifier("detail-pane-" + section.rawValue)
    }

    private var saveFooter: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                if let message = draft.visibleMessage {
                    Text(message).foregroundStyle(draft.hasError ? Color.red : Palette.muted)
                        .accessibilityIdentifier("detail-save-feedback")
                } else {
                    Text(draft.hasChanges ? "Draft kept locally · Save to apply" : "Captured day stays the same").foregroundStyle(Palette.muted)
                }
                if draft.hasUnresolvedValidation {
                    Button { state.keepDetailDraftAndGoBack() } label: {
                        Text("Keep draft and go back")
                            .font(.system(size: min(15, max(12, zoom.fontSize(12))), weight: .medium))
                            .frame(minHeight: 32, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(accent)
                        .disabled(!state.canKeepDetailDraftAndGoBack)
                        .accessibilityIdentifier("detail-keep-draft-back")
                        .accessibilityHint("Keep the unfinished edits locally and return to the previous page")
                }
            }.font(.system(size: min(13, zoom.fontSize(11)))).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Save changes") { saveChanges() }.buttonStyle(.borderedProminent)
                .controlSize(.regular).disabled(!draft.hasChanges).keyboardShortcut("s", modifiers: .command)
                .accessibilityIdentifier("detail-save")
        }.padding(13).overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
    }

    private func saveChanges() {
        state.saveDetail(capture: capture, draft: draft)
        switch draft.validationIssue {
        case .title:
            selectSection(.task); state.detailFocus = "title"; focusedField = "title"
        case .planning: selectSection(.task)
        case .reminder: selectSection(.reminder)
        case nil: break
        }
    }

    private func originalContent(layout: DetailLayout) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if capture.kind == .text || capture.kind == .task || capture.kind == .link {
                Button { state.openExtendedCapture(capture.id) } label: {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(capture.originalText ?? capture.originalURL ?? capture.title)
                            .font(.system(size: layout.bodySize)).lineSpacing(zoom.lineSpacing(5)).lineLimit(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Label("Open Extended View", systemImage: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: zoom.fontSize(12), weight: .medium)).foregroundStyle(accent)
                    }.padding(zoom.value(16)).frame(maxWidth: .infinity, minHeight: zoom.value(130), alignment: .topLeading)
                        .background(Palette.soft, in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line, lineWidth: 1))
                        .contentShape(RoundedRectangle(cornerRadius: 14))
                }.buttonStyle(.plain).accessibilityLabel("Open capture in DaBin Extended View")
                    .accessibilityIdentifier("detail-preview-open-extended")
                    .captureDragSource(state: state, capture: capture)
            } else {
                DetailPreview(store: state.store, capture: capture, height: layout.previewHeight,
                    onOpenOriginal: { state.openExtendedCapture(capture.id) },
                    openLabel: "Open capture in DaBin Extended View")
                    .captureDragSource(state: state, capture: capture)
                Button("Open Extended View", systemImage: "arrow.up.left.and.arrow.down.right") {
                    state.openExtendedCapture(capture.id)
                }.buttonStyle(.plain).font(.system(size: zoom.fontSize(12), weight: .medium)).foregroundStyle(accent)
                    .accessibilityIdentifier("detail-open-extended")
            }
        }
    }

    private func taskWorkspace(layout: DetailLayout) -> some View {
        let arrangement = layout.usesTaskColumns
            ? AnyLayout(HStackLayout(alignment: .top, spacing: layout.sectionSpacing))
            : AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        return arrangement {
            VStack(alignment: .leading, spacing: 8) {
                TaskPlanningEditor(planning: $draft.planning, pendingChecklistText: $draft.pendingChecklistText,
                    showsFocusDuration: false)
                if let previous = capture.taskPlanning?.previousOccurrenceID {
                    Button("Previous occurrence", systemImage: "arrow.counterclockwise") { state.openCapture(previous) }
                        .buttonStyle(.plain).font(.system(size: zoom.fontSize(12)))
                }
            }.frame(maxWidth: .infinity, alignment: .topLeading)
            TaskAttachmentsView(state: state, task: capture,
                minimumCardWidth: layout.attachmentMinimumWidth, thumbnailHeight: layout.attachmentHeight)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var actionRail: some View {
        HStack(spacing: 6) {
            compactAction("Copy", symbol: "doc.on.doc", title: "Copy capture") { state.copyCapturesToClipboard([capture]) }
                .accessibilityIdentifier("detail-action-copy")
            if !capture.isTask {
                compactAction("Make task", symbol: "checkmark.circle", title: "Turn \(capture.title) into a task") { state.convertToTask(capture) }
                    .accessibilityIdentifier("capture-convert-to-task-" + capture.id.uuidString)
                    .disabled(state.removingCaptureID == capture.id)
            }
            Menu {
                Button("Open Extended View", systemImage: "arrow.up.left.and.arrow.down.right") { state.openExtendedCapture(capture.id) }
                if capture.kind != .text && capture.kind != .task {
                    Button("Open original", systemImage: "arrow.up.forward.square") { state.openOriginal(capture) }
                        .accessibilityIdentifier("detail-action-open-original")
                }
                Button("Saved folder", systemImage: "folder") { state.showArchiveFolder(for: capture) }
                    .accessibilityLabel("Show saved folder").accessibilityIdentifier("detail-action-folder")
                if let parent = capture.parentTaskID {
                    Button("Back to task", systemImage: "arrow.turn.up.left") { state.openCapture(parent, focus: "task") }
                }
                CaptureReturnToInboxMenuItem(state: state, capture: capture)
                Divider()
                Button("Trash", systemImage: "trash") { state.requestRemoval(capture) }
                    .accessibilityLabel("Move \(capture.title.isEmpty ? "capture" : capture.title) to Recently Deleted")
                    .accessibilityIdentifier("capture-trash-" + capture.id.uuidString)
                    .disabled(state.removingCaptureID != nil || state.isArchiveOperationRunning)
            } label: { compactActionLabel("More", symbol: "ellipsis") }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
                .accessibilityLabel("More capture actions").accessibilityIdentifier("detail-actions-more")
                .buddyHelp("Open, organize, locate or remove this capture")
            Spacer(minLength: 0)
        }.foregroundStyle(accent).accessibilityElement(children: .contain).accessibilityLabel("Capture actions")
            .accessibilityIdentifier("detail-actions")
    }

    private func compactAction(_ label: String, symbol: String, title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { compactActionLabel(label, symbol: symbol) }
            .buttonStyle(.plain).accessibilityLabel(title).buddyHelp(title)
    }

    private func compactActionLabel(_ label: String, symbol: String) -> some View {
        Label(label, systemImage: symbol).font(.system(size: controlFont, weight: .medium))
            .padding(.horizontal, 8).frame(minHeight: 32).contentShape(RoundedRectangle(cornerRadius: 7))
            .background(Palette.soft, in: RoundedRectangle(cornerRadius: 7))
    }

    @ViewBuilder
    private func searchableText(layout: DetailLayout) -> some View {
        switch capture.contentIndexState {
        case "indexing":
            Label("Making this capture searchable…", systemImage: "text.viewfinder")
                .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
                .accessibilityLabel("Recognizing text on this Mac")
        case "ready" where !capture.indexedText.isEmpty:
            VStack(alignment: .leading, spacing: 6) {
                CaptureRecognizedTextPanel(capture: capture, layout: layout,
                                          copied: copiedSearchableText, onCopy: copySearchableText)
                if let message = capture.contentIndexError {
                    Text(message).font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted)
                }
            }
            .accessibilityElement(children: .contain)
        case "ready":
            Label("No readable text found", systemImage: "text.viewfinder")
                .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
        case "unavailable":
            VStack(alignment: .leading, spacing: 5) {
                Label(capture.contentIndexError ?? "Text search is unavailable for this capture.",
                      systemImage: "text.viewfinder")
                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
                if state.contentIndex != nil, capture.contentIndexCanRetry {
                    Button("Try text recognition again") { state.retryContentIndex(capture) }
                        .buttonStyle(.plain).font(.system(size: zoom.fontSize(12))).foregroundStyle(accent)
                        .buddyHelp("Retry local text recognition")
                }
            }
        default:
            if state.contentIndex?.isBusy == true {
                Label("Waiting for local text recognition…", systemImage: "text.viewfinder")
                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted)
            }
        }
    }

    private func copySearchableText() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        guard pasteboard.setString(capture.indexedText, forType: .string) else {
            state.reportFailure("Searchable text could not be copied.")
            return
        }
        copiedSearchableText = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.4))
            copiedSearchableText = false
        }
    }

    private var original: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(capture.originalURL ?? capture.originalFilename ?? "Text capture")
                    .font(.system(size: zoom.fontSize(12))).foregroundStyle(Palette.muted).lineLimit(3).textSelection(.enabled)
                if let bytes = capture.byteCount { Text(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)).font(.system(size: zoom.fontSize(11))).foregroundStyle(Palette.muted) }
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 11)
            .overlay(alignment: .top) { Rectangle().fill(Palette.line).frame(height: 1) }
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line).frame(height: 1) }
            .captureDragSource(state: state, capture: capture)
            .buddyHelp("Drag the saved content into another app")
    }

}
