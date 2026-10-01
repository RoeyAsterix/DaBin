import Foundation

/// A receipt is evidence of use, never an inference from copying or opening an app.
enum CapturePasteEvidence: String, Codable, Sendable {
    case manual, confirmed

    var title: String { self == .manual ? "Recorded by you" : "Confirmed paste" }
}

struct CapturePasteEvent: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    let applicationName: String
    let applicationBundleIdentifier: String?
    let recordedAt: Date
    let evidence: CapturePasteEvidence

    init(id: UUID = UUID(), applicationName: String, applicationBundleIdentifier: String? = nil,
         recordedAt: Date = Date(), evidence: CapturePasteEvidence = .manual) {
        self.id = id
        self.applicationName = applicationName
        self.applicationBundleIdentifier = applicationBundleIdentifier
        self.recordedAt = recordedAt
        self.evidence = evidence
    }

    var isValid: Bool {
        let name = applicationName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name == applicationName, name.count <= 100, name.utf8.count <= 400,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              recordedAt.timeIntervalSince1970.isFinite,
              (0...253_402_300_799).contains(recordedAt.timeIntervalSince1970) else { return false }
        guard let identifier = applicationBundleIdentifier else { return true }
        return !identifier.isEmpty && identifier.utf8.count <= 255
            && identifier.unicodeScalars.allSatisfy {
                CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_").contains($0)
            }
    }
}

struct CaptureApplicationIdentity: Equatable, Identifiable, Sendable {
    let name: String
    let bundleIdentifier: String?
    var id: String { bundleIdentifier?.lowercased() ?? "name:\(name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX")))" }

    static let choices: [Self] = [
        .init(name: "Mail", bundleIdentifier: "com.apple.mail"),
        .init(name: "Notes", bundleIdentifier: "com.apple.Notes"),
        .init(name: "Finder", bundleIdentifier: "com.apple.finder"),
        .init(name: "Safari", bundleIdentifier: "com.apple.Safari"),
        .init(name: "Chrome", bundleIdentifier: "com.google.Chrome"),
        .init(name: "Slack", bundleIdentifier: "com.tinyspeck.slackmacgap"),
        .init(name: "DaBin", bundleIdentifier: "com.dabin.mac")
    ]

    static func resolve(name: String?, identifier: String?) -> Self? {
        let name = name?.trimmingCharacters(in: .whitespacesAndNewlines)
        let identifier = identifier?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let identifier, !identifier.isEmpty {
            if let known = choices.first(where: { $0.bundleIdentifier?.caseInsensitiveCompare(identifier) == .orderedSame }) { return known }
            return .init(name: name.flatMap { $0.isEmpty ? nil : $0 }
                         ?? identifier.split(separator: ".").last.map(String.init) ?? identifier,
                         bundleIdentifier: identifier)
        }
        guard let name, !name.isEmpty else { return nil }
        if let known = choices.first(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame
            || ($0.name == "Chrome" && name.caseInsensitiveCompare("Google Chrome") == .orderedSame) }) { return known }
        return .init(name: name, bundleIdentifier: nil)
    }
}

struct CapturePasteDestination: Identifiable, Equatable {
    let application: CaptureApplicationIdentity
    var count: Int
    var id: String { application.id }
}

enum CapturePasteHistory {
    static let maximumEvents = 1_000
    static let compactLimit = 3

    static func isValid(_ events: [CapturePasteEvent]) -> Bool {
        events.count <= maximumEvents && events.allSatisfy(\.isValid)
            && Set(events.map(\.id)).count == events.count
    }

    static func newestFirst(_ events: [CapturePasteEvent]) -> [CapturePasteEvent] {
        events.sorted { $0.recordedAt == $1.recordedAt ? $0.id.uuidString < $1.id.uuidString : $0.recordedAt > $1.recordedAt }
    }

    static func destinations(_ events: [CapturePasteEvent]) -> [CapturePasteDestination] {
        var results: [CapturePasteDestination] = []
        for event in newestFirst(events) where event.isValid {
            guard let app = CaptureApplicationIdentity.resolve(name: event.applicationName, identifier: event.applicationBundleIdentifier) else { continue }
            if let index = results.firstIndex(where: { $0.id == app.id }) { results[index].count += 1 }
            else { results.append(.init(application: app, count: 1)) }
        }
        return results
    }

    static func compactDestinations(_ events: [CapturePasteEvent]) -> [CapturePasteDestination] {
        Array(destinations(events).prefix(compactLimit))
    }

    static func overflowCount(_ events: [CapturePasteEvent]) -> Int {
        max(0, destinations(events).count - compactLimit)
    }
}

@MainActor
extension CaptureStore {
    /// This is an explicit user ledger. No public mutation can fabricate a confirmed paste.
    @discardableResult
    func recordPasteDestination(for capture: Capture, applicationName: String,
                                applicationBundleIdentifier: String? = nil, at date: Date = Date()) throws -> CapturePasteEvent {
        let event = CapturePasteEvent(applicationName: applicationName.trimmingCharacters(in: .whitespacesAndNewlines),
                                      applicationBundleIdentifier: applicationBundleIdentifier, recordedAt: date)
        guard event.isValid else {
            throw CaptureStoreError.invalidOriginal("Enter an app or product name of up to 100 characters.")
        }
        guard capture.pasteHistory.count < CapturePasteHistory.maximumEvents else {
            throw CaptureStoreError.invalidOriginal("This capture has 1,000 paste records. Remove an old record before adding another.")
        }
        try commitPasteHistory(capture.pasteHistory + [event], for: capture)
        return event
    }

    func removePasteDestination(_ eventID: UUID, from capture: Capture) throws {
        guard let event = capture.pasteHistory.first(where: { $0.id == eventID }), event.evidence == .manual else {
            throw CaptureStoreError.invalidOriginal("Only an existing manually recorded paste can be removed.")
        }
        try commitPasteHistory(capture.pasteHistory.filter { $0.id != eventID }, for: capture)
    }

    private func commitPasteHistory(_ history: [CapturePasteEvent], for capture: Capture) throws {
        guard capture.deletedAt == nil, captures.contains(where: { $0 === capture }), CapturePasteHistory.isValid(history) else {
            throw CaptureStoreError.invalidOriginal("This capture is no longer available to update.")
        }
        let prior = capture.pasteHistory
        let previousDate = capture.updatedAt
        capture.setPasteHistory(history)
        capture.updatedAt = Date()
        do {
            try failureInjector?(.beforeMetadataSave)
            try save(captures: [capture])
        } catch {
            capture.setPasteHistory(prior)
            capture.updatedAt = previousDate
            throw error
        }
    }
}
