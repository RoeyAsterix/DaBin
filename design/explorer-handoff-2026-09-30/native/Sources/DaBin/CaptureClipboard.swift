import AppKit
import Foundation

enum CaptureClipboardItem: Equatable {
    case text(String)
    case webURL(String)
    case file(URL)
}

struct CaptureClipboardPayload: Equatable {
    let items: [CaptureClipboardItem]
}

enum CaptureClipboardError: LocalizedError, Equatable {
    case noContent
    case missingSavedOriginal(String)
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .noContent:
            return "This action has no content to copy."
        case .missingSavedOriginal(let name):
            return "The saved original for \(name) is unavailable."
        case .writeFailed:
            return "macOS could not write this action to the clipboard."
        }
    }
}

/// Reconstructs an action's captured content without reading its source app or
/// original external location. File payloads always use DaBin's managed copy.
@MainActor
final class CaptureClipboardService {
    typealias ManagedURLResolver = (Capture) -> URL?
    typealias PayloadWriter = (CaptureClipboardPayload) -> Bool

    private let writer: PayloadWriter

    init(writer: @escaping PayloadWriter) {
        self.writer = writer
    }

    convenience init() {
        self.init(writer: Self.systemWriter())
    }

    convenience init(pasteboard: NSPasteboard) {
        self.init(writer: Self.writer(for: pasteboard))
    }

    func payload(for captures: [Capture], managedURL: ManagedURLResolver) throws -> CaptureClipboardPayload {
        let items = try captures.map { capture -> CaptureClipboardItem in
            switch capture.kind {
            case .link:
                guard let value = firstNonempty(capture.originalURL, capture.originalText, capture.title) else {
                    throw CaptureClipboardError.noContent
                }
                return .webURL(value)
            case .text, .task:
                guard let value = firstNonempty(capture.originalText, capture.title) else {
                    throw CaptureClipboardError.noContent
                }
                return .text(value)
            case .image, .video, .pdf, .document, .ai, .file:
                guard let url = managedURL(capture) else {
                    throw CaptureClipboardError.missingSavedOriginal(capture.originalFilename ?? capture.title)
                }
                return .file(url)
            }
        }
        guard !items.isEmpty else { throw CaptureClipboardError.noContent }
        return CaptureClipboardPayload(items: items)
    }

    @discardableResult
    func copy(_ captures: [Capture], managedURL: ManagedURLResolver) throws -> CaptureClipboardPayload {
        let payload = try payload(for: captures, managedURL: managedURL)
        guard writer(payload) else { throw CaptureClipboardError.writeFailed }
        return payload
    }

    private func firstNonempty(_ values: String?...) -> String? {
        values.first { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        } ?? nil
    }

    private static func systemWriter() -> PayloadWriter {
        writer(for: .general)
    }

    private static func writer(for pasteboard: NSPasteboard) -> PayloadWriter {
        { payload in
            let objects: [NSPasteboardWriting] = payload.items.map { item in
                switch item {
                case .text(let value):
                    return value as NSString
                case .webURL(let value):
                    let item = NSPasteboardItem()
                    item.setString(value, forType: .URL)
                    item.setString(value, forType: .string)
                    return item
                case .file(let url):
                    return url as NSURL
                }
            }
            pasteboard.clearContents()
            return pasteboard.writeObjects(objects)
        }
    }
}
