import AppKit
import PDFKit
import SwiftUI

/// Fits one complete page into the available preview while retaining document navigation.
@MainActor
struct FittedPDFPreview: View {
    let url: URL
    @Environment(\.daBinAccent) private var accent
    @StateObject private var model: FittedPDFModel

    init(url: URL) {
        self.url = url
        _model = StateObject(wrappedValue: FittedPDFModel(url: url))
    }

    var body: some View {
        VStack(spacing: 4) {
            FittedPDFSurface(view: model.view)
                .padding(4)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            if model.pageCount > 1 {
                HStack(spacing: 12) {
                    Button(action: { model.movePage(by: -1) }) {
                        Image(systemName: "chevron.left")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(model.pageIndex == 0)
                    .accessibilityLabel("Previous PDF page")
                    .help("Previous page")

                    Text("\(model.pageIndex + 1) / \(model.pageCount)")
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Page \(model.pageIndex + 1) of \(model.pageCount)")

                    Button(action: { model.movePage(by: 1) }) {
                        Image(systemName: "chevron.right")
                            .frame(width: 24, height: 22)
                    }
                    .disabled(model.pageIndex + 1 >= model.pageCount)
                    .accessibilityLabel("Next PDF page")
                    .help("Next page")
                }
                .font(.system(size: 11, weight: .medium))
                .buttonStyle(.plain)
                .foregroundStyle(accent)
                .frame(height: 24)
            }
        }
        .onChange(of: url) { _, newURL in model.load(newURL) }
    }
}

@MainActor
private final class FittedPDFModel: NSObject, ObservableObject {
    let view = FittedPageView(frame: NSRect(x: 0, y: 0, width: 320, height: 202))
    @Published private(set) var pageIndex = 0
    @Published private(set) var pageCount = 0
    private var loadedURL: URL?

    init(url: URL) {
        super.init()
        view.displayMode = .singlePage
        view.displayBox = .cropBox
        view.backgroundColor = .clear
        view.displaysPageBreaks = false
        NotificationCenter.default.addObserver(self, selector: #selector(pageChanged),
                                               name: .PDFViewPageChanged, object: view)
        load(url)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func load(_ url: URL) {
        guard loadedURL != url else { return }
        loadedURL = url
        view.document = PDFDocument(url: url)
        pageIndex = 0
        pageCount = view.document?.pageCount ?? 0
        view.fitCurrentPage()
    }

    func movePage(by amount: Int) {
        guard let document = view.document,
              let page = document.page(at: pageIndex + amount) else { return }
        view.go(to: page)
        pageIndex = document.index(for: page)
        view.fitCurrentPage()
    }

    @objc private func pageChanged(_ notification: Notification) {
        // PDFKit also changes pages through its native keyboard commands. Defer state
        // publication because this notification can arrive during an AppKit layout.
        DispatchQueue.main.async { [weak self] in
            guard let self, let document = self.view.document,
                  let page = self.view.currentPage else { return }
            let index = document.index(for: page)
            guard index != NSNotFound, index != self.pageIndex else { return }
            self.pageIndex = index
            self.view.fitCurrentPage()
        }
    }
}

@MainActor
private struct FittedPDFSurface: NSViewRepresentable {
    let view: FittedPageView
    func makeNSView(context: Context) -> FittedPageView { view }
    func updateNSView(_ nsView: FittedPageView, context: Context) {}
}

@MainActor
private final class FittedPageView: PDFView {
    private var fittedSize = NSSize.zero

    override func layout() {
        super.layout()
        guard bounds.width > 0, bounds.height > 0, fittedSize != bounds.size else { return }
        fittedSize = bounds.size
        fitCurrentPage()
    }

    func fitCurrentPage() {
        // In PDFKit, only a non-continuous display mode makes autoScales fit the
        // complete page. Continuous modes intentionally fit only its width.
        autoScales = true
    }
}
