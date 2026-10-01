import Foundation

/// A visual card boundary. Imported originals that share one immutable receipt
/// instant came from the same explicit paste or drop and stay together on the board.
struct CaptureCardGroup: Identifiable {
    enum ID: Hashable {
        case capture(UUID)
        case importedBatch(Date)
    }

    let id: ID
    let captures: [Capture]

    var primary: Capture { captures[0] }
    var isImportedBatch: Bool { captures.count > 1 }
    var isMinimized: Bool { captures.allSatisfy(\.isMinimized) }

    /// Tasks have their own visible status/carryover. Exports can retain the
    /// original receipt grouping independently of this presentation choice.
    static func cards(from captures: [Capture], separateTasks: Bool = true) -> [CaptureCardGroup] {
        let imported = captures.filter { $0.attachmentRelativePath != nil && (!separateTasks || !$0.isTask) }
        let byReceipt = Dictionary(grouping: imported, by: \.capturedAt)
        var emittedReceipts = Set<Date>()
        var result: [CaptureCardGroup] = []

        for capture in captures {
            if capture.attachmentRelativePath != nil, (!separateTasks || !capture.isTask),
               let batch = byReceipt[capture.capturedAt], batch.count > 1 {
                guard emittedReceipts.insert(capture.capturedAt).inserted else { continue }
                result.append(CaptureCardGroup(id: .importedBatch(capture.capturedAt), captures: batch))
            } else {
                result.append(CaptureCardGroup(id: .capture(capture.id), captures: [capture]))
            }
        }
        return result
    }
}
