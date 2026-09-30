@testable import DaBinTestCore
import AppKit
import Foundation

/// Synthetic, local-only data-path measurements. UI latency and GPU presentation
/// are measured separately by the review wrapper; this is not a product benchmark.
@main struct ReviewPerformance {
    @MainActor static func main() throws {
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-Review-Performance-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let now = Date()
        let captures = (0..<10_000).map { i in
            Capture(capturedAt: now.addingTimeInterval(-Double(i) * 1200), kind: .text,
                    originalText: "Synthetic design note \(i). \(i % 100 == 0 ? "violetneedle" : "everyday") Color, spacing and helpful reminders.",
                    title: "Fictional reference \(i)")
        }
        func measure(_ operation: () throws -> Void) rethrows -> Double {
            let start = ProcessInfo.processInfo.systemUptime
            try operation()
            return (ProcessInfo.processInfo.systemUptime - start) * 1000
        }
        var searchSamples: [Double] = []
        var matchCounts: [Int] = []
        for _ in 0..<12 {
            searchSamples.append(measure {
                let result = CaptureSearch.groups(captures: captures, query: "violetneedle", filter: .all, includeContext: false)
                matchCounts.append(result.reduce(0) { $0 + $1.entries.filter(\.isMatch).count })
            })
        }
        guard matchCounts.allSatisfy({ $0 == 100 }) else { throw NSError(domain: "ReviewPerformance", code: 1) }
        let repository = try CaptureRepository(root: root)
        let saveMS = try measure { try repository.save(captures) }
        var loadedCount = 0
        #if REVIEW_DEFERRED_SUPPORT
        let loadMS = try measure { loadedCount = try CaptureStore(root: root, repairArchiveOnOpen: false).captures.count }
        let firstMirrorGenerationMS = try measure { _ = try CaptureStore(root: root) }
        let warmLoadMS = try measure { _ = try CaptureStore(root: root, repairArchiveOnOpen: false) }
        #else
        let loadMS = try measure { loadedCount = try CaptureStore(root: root).captures.count }
        #endif
        guard loadedCount == 10_000 else { throw NSError(domain: "ReviewPerformance", code: 2) }
        let sorted = searchSamples.sorted()
        var result: [String: Any] = [
            "syntheticOnly": true, "records": captures.count, "matchesPerQuery": 100,
            "searchSamplesMS": searchSamples, "searchMedianMS": (sorted[5] + sorted[6]) / 2,
            "searchMaxMS": sorted.last!, "metadataSaveMS": saveMS, "archiveLoadMS": loadMS,
            "environment": ProcessInfo.processInfo.operatingSystemVersionString,
            "scope": "Production CaptureSearch.groups over 10,000 in-memory text records; production repository save and store load. No thumbnails, OCR, GPU, automation latency, network, or private archive. One local run, not a broad performance guarantee."
        ]
        #if REVIEW_DEFERRED_SUPPORT
        result["firstMirrorGenerationMS"] = firstMirrorGenerationMS
        result["warmMetadataLoadMS"] = warmLoadMS
        result["archiveLoadScope"] = "Metadata and originals ready, readable mirror repair deferred. Separate firstMirrorGenerationMS measures legacy/eager folder generation; it is not foreground startup."
        #else
        result["archiveLoadScope"] = "Baseline eager load includes generating readable folders for all 10,000 records."
        #endif
        try JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]).write(to: output, options: .atomic)
        print(String(data: try JSONSerialization.data(withJSONObject: result, options: .prettyPrinted), encoding: .utf8)!)
    }
}
