import AppKit
import Combine
import Foundation

private final class ManualPromiseFixture: InputFilePromise {
    private(set) var fileNames: [String] = []
    private let names: [String]
    private var destination: URL?
    private var reader: ((URL, Error?) -> Void)?
    private var queue: OperationQueue?

    init(_ names: [String]) { self.names = names }

    func receive(at destination: URL, operationQueue: OperationQueue,
                 reader: @escaping (URL, Error?) -> Void) {
        self.destination = destination
        self.queue = operationQueue
        self.reader = reader
        fileNames = names
    }

    func deliver(_ index: Int) {
        guard let destination, let reader, let queue else { fatalError("Promise was not requested") }
        let name = names[index]
        queue.addOperation {
            let url = destination.appendingPathComponent(name)
            do {
                try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
                try Data(name.utf8).write(to: url)
                reader(url, nil)
            } catch { reader(url, error) }
        }
    }
}

@MainActor private final class ManualReminderClient: ReminderNotificationClient {
    func authorization() async -> ReminderAuthorization { .allowed }
    func requestAuthorization() async throws -> Bool { fatalError("No system permission in this fixture") }
    func pending() async -> [ScheduledReminder] { [] }
    func add(_ reminder: ScheduledReminder) async throws {}
    func removePending(_ identifiers: [String]) {}
    func removeDelivered(_ identifiers: [String]) {}
}

@main struct ManualCaptureLifecycleTests {
    @MainActor private static var checks = 0

    @MainActor private static func expect(_ condition: @autoclosure () throws -> Bool,
                                          _ message: String) throws {
        checks += 1
        if try !condition() {
            throw NSError(domain: "ManualCaptureLifecycleTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor private static func wait(_ message: String, until condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition(), Date() < deadline { try await Task.sleep(for: .milliseconds(10)) }
        try expect(condition(), message)
    }

    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinManualInput-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "DaBinManualInput.\(UUID())"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        // These empty, named boards receive only fixture promises. The general
        // clipboard and native notification/shortcut services are never used.
        let firstBoard = NSPasteboard(name: .init("DaBinManualInput.First.\(UUID())"))
        let newerBoard = NSPasteboard(name: .init("DaBinManualInput.Newer.\(UUID())"))
        firstBoard.clearContents()
        newerBoard.clearContents()
        defer { firstBoard.releaseGlobally(); newerBoard.releaseGlobally() }
        let firstPromise = ManualPromiseFixture(["Late-first.fixture", "Late-second.fixture"])
        let newerPromise = ManualPromiseFixture(["Newer.fixture"])
        let store = try CaptureStore(root: root.appendingPathComponent("Archive"))
        let input = InputService(store: store, promiseTimeout: 1, stagingRoot: root,
                                 promiseReader: { board in
            board.name == firstBoard.name ? [firstPromise] : [newerPromise]
        })
        let previews = PreviewService(store: store, defaults: defaults)
        defer { previews.shutdown() }
        let state = AppState(store: store, previews: previews,
                             reminders: ReminderService(store: store, client: ManualReminderClient()),
                             manualInput: input)
        var results: [([Capture], [String])] = []
        input.onResult = { captures, failures in results.append((captures, failures)) }
        var busyNotifications: [Bool] = []
        let observation = state.objectWillChange.sink { busyNotifications.append(state.isImporting) }
        defer { observation.cancel() }

        state.openLibrary()
        state.pasteClipboard(from: firstBoard)
        try expect(input.isBusy && state.isImporting, "An explicit manual paste immediately protects active receiving work")
        try await wait("The missing-file timeout returns control to the user") { results.count == 1 && !input.isBusy }
        try expect(!state.isImporting && store.captures.isEmpty,
                   "A timed-out promise releases busy state without inventing a capture")
        try expect(results[0].0.isEmpty && results[0].1.count == 1 && state.status?.severity == .error,
                   "The incomplete manual paste reports its missing files")
        try expect(state.route == .library, "A timeout does not navigate away from the current view")

        var busyAtCommit: [Bool] = []
        store.failureInjector = { checkpoint in
            if checkpoint == .beforeMetadataSave { busyAtCommit.append(state.isImporting && input.isBusy) }
        }
        defer { store.failureInjector = nil }
        busyNotifications.removeAll()
        firstPromise.deliver(0)
        try await wait("The first late file completes independently") { results.count == 2 && !input.isBusy }
        try expect(busyAtCommit == [true], "A late file is busy before metadata commit, keeping the quit guard effective")
        try expect(busyNotifications.contains(true), "Late-file busy changes notify views through AppState")
        try expect(!state.isImporting && state.status?.severity == .success,
                   "Late completion reports success and releases its own busy work")
        try expect(results[1].0.count == 1 && results[1].1.isEmpty && store.captures.count == 1,
                   "Late completion reports only the newly saved capture")

        // A second late callback belongs to the older paste. It must not clear
        // the aggregate busy flag while a newer paste still awaits its file.
        state.pasteClipboard(from: newerBoard)
        try expect(state.isImporting && input.isBusy, "A newer manual paste owns an independent pending receive")
        firstPromise.deliver(1)
        try await wait("The older paste's second late file completes") { results.count >= 3 }
        try expect(results.count == 3 && results[2].0.count == 1 && results[2].1.isEmpty,
                   "The older late callback succeeds while the newer source remains pending")
        try expect(input.isBusy && state.isImporting,
                   "An older completion cannot release the newer paste's busy and quit protection")
        newerPromise.deliver(0)
        try await wait("The newer paste completes and releases the final receive") { results.count == 4 && !input.isBusy }
        try expect(!state.isImporting && busyAtCommit == [true, true, true],
                   "Every late or current import stays busy through its metadata commit")
        try expect(results.map { $0.0.count } == [0, 1, 1, 1] && store.captures.count == 3,
                   "Each promised file is reported once without replaying earlier successes")
        for capture in store.captures {
            guard let original = store.managedURL(for: capture), let name = capture.originalFilename else {
                throw NSError(domain: "ManualCaptureLifecycleTests", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "A saved promise has no managed original"])
            }
            try expect(try Data(contentsOf: original) == Data(name.utf8),
                       "Each reported capture has its exact durable original bytes")
        }
        print("PASS: \(checks) manual capture lifecycle checks (private named pasteboards)")
    }
}
