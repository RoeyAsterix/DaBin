import Foundation
import CoreData

/// Transactional metadata storage. Attachment layout and capture behavior live outside this repository.
/// The existing DaBinV1 model and store filename are retained without an implicit migration or reset.
@MainActor final class CaptureRepository {
    private let container: NSPersistentContainer
    private let context: NSManagedObjectContext

    init(root: URL) throws {
        try Self.validateStoreFiles(root: root)
        let objectModel = NSManagedObjectModel()
        objectModel.versionIdentifiers = ["DaBinV1"]
        let entity = NSEntityDescription()
        entity.name = "CaptureRecord"
        entity.managedObjectClassName = "NSManagedObject"
        let identity = NSAttributeDescription()
        identity.name = "captureID"
        identity.attributeType = .UUIDAttributeType
        identity.isOptional = false
        let payload = NSAttributeDescription()
        payload.name = "payload"
        payload.attributeType = .binaryDataAttributeType
        payload.isOptional = false
        entity.properties = [identity, payload]
        entity.uniquenessConstraints = [["captureID"]]
        objectModel.entities = [entity]

        container = NSPersistentContainer(name: "DaBinV1", managedObjectModel: objectModel)
        let description = NSPersistentStoreDescription(url: root.appendingPathComponent("metadata.store"))
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.viewContext
        context.mergePolicy = NSErrorMergePolicy
        context.undoManager = nil
    }

    func load() throws -> [CaptureSnapshot] {
        let request = NSFetchRequest<NSManagedObject>(entityName: "CaptureRecord")
        let snapshots = try context.fetch(request).map { record in
            guard let data = record.value(forKey: "payload") as? Data else {
                throw CaptureStoreError.invalidOriginal("A saved metadata record is unreadable.")
            }
            let snapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: data)
            try validate(snapshot, recordID: record.value(forKey: "captureID") as? UUID)
            return snapshot
        }
        try validateRelationships(snapshots)
        return snapshots
    }

    /// Upsert the supplied captures as one transaction, preserving every unrelated record.
    func save(_ captures: [Capture]) throws {
        try saveSnapshots(captures.map(CaptureSnapshot.init))
    }

    /// Delete a task and its attached receipts in one metadata transaction.
    func remove(id: UUID) throws { try remove(ids: [id]) }

    func remove(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CaptureRecord")
            request.predicate = NSPredicate(format: "captureID IN %@", ids.map { $0 as NSUUID })
            let records = try context.fetch(request)
            guard records.count == ids.count else {
                throw CaptureStoreError.invalidOriginal("This capture is no longer in the archive.")
            }
            records.forEach(context.delete)
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Allows a layout migration to commit or restore receipt metadata without changing its identity.
    func saveSnapshots(_ snapshots: [CaptureSnapshot]) throws {
        do {
            let encoder = JSONEncoder()
            // Fetch before inserting. A fetch after each insertion asks Core
            // Data to scan an ever-growing pending-insert set and makes a large
            // import quadratic. Small batches retain a single scoped lookup.
            let ids = Array(Set(snapshots.map(\.id)))
            var existing: [UUID: NSManagedObject] = [:]
            for start in stride(from: 0, to: ids.count, by: 500) {
                let request = NSFetchRequest<NSManagedObject>(entityName: "CaptureRecord")
                request.predicate = NSPredicate(format: "captureID IN %@", ids[start..<min(start + 500, ids.count)].map { $0 as NSUUID })
                for record in try context.fetch(request) {
                    guard let id = record.value(forKey: "captureID") as? UUID else {
                        throw CaptureStoreError.invalidOriginal("A saved metadata record has no identity.")
                    }
                    existing[id] = record
                }
            }
            for snapshot in snapshots {
                try validate(snapshot, recordID: snapshot.id)
                let data = try encoder.encode(snapshot)
                let record = existing[snapshot.id]
                    ?? NSEntityDescription.insertNewObject(forEntityName: "CaptureRecord", into: context)
                // Repeated identities keep the prior API's last-payload-wins behavior.
                existing[snapshot.id] = record
                record.setValue(snapshot.id, forKey: "captureID")
                record.setValue(data, forKey: "payload")
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    /// Backup restoration validates its entire batch before writing files or
    /// touching the managed object context.
    func validateSnapshots(_ snapshots: [CaptureSnapshot]) throws {
        guard Set(snapshots.map(\.id)).count == snapshots.count else {
            throw CaptureStoreError.invalidOriginal("The backup contains duplicate capture identities.")
        }
        for snapshot in snapshots { try validate(snapshot, recordID: snapshot.id) }
        try validateRelationships(snapshots)
    }

    private func validateRelationships(_ snapshots: [CaptureSnapshot]) throws {
        let byID = Dictionary(uniqueKeysWithValues: snapshots.map { ($0.id, $0) })
        for snapshot in snapshots {
            guard let parentID = snapshot.parentTaskID else { continue }
            guard parentID != snapshot.id, let parent = byID[parentID],
                  parent.parentTaskID == nil,
                  parent.kindRaw == CaptureKind.task.rawValue || parent.convertedToTask == true,
                  snapshot.deletedAt != nil || parent.deletedAt == nil else {
                throw CaptureStoreError.invalidOriginal("A task attachment has an invalid parent. The archive was preserved.")
            }
        }
    }

    private func validate(_ snapshot: CaptureSnapshot, recordID: UUID?) throws {
        let origin = snapshot.captureOriginRaw.flatMap(CaptureOrigin.init(rawValue:)) ?? .manual
        let indexState = snapshot.contentIndexState ?? "idle"
        let indexVersion = snapshot.contentIndexVersion ?? 0
        let indexCanRetry = snapshot.contentIndexCanRetry ?? false
        let indexValid = snapshot.schemaVersion < 6 || (
            ["idle", "indexing", "ready", "unavailable"].contains(indexState)
            && (0...ContentIndexService.currentVersion).contains(indexVersion)
            && (snapshot.indexedText?.count ?? 0) <= ContentTextExtractor.maximumCharacters
            && (snapshot.contentIndexError?.count ?? 0) <= 4_000
            // Terminal indexes from older extractors remain readable. The
            // indexing service decides which formats actually need an upgrade.
            && (["idle", "indexing"].contains(indexState) ? indexVersion == 0 : (1...ContentIndexService.currentVersion).contains(indexVersion))
            && (!indexCanRetry || indexState == "unavailable")
        )
        guard (1...11).contains(snapshot.schemaVersion), CaptureKind(rawValue: snapshot.kindRaw) != nil,
              recordID == snapshot.id,
              snapshot.captureOriginRaw.map({ CaptureOrigin(rawValue: $0) != nil }) ?? true,
              (!origin.isAutomatic || snapshot.automaticActionID != nil), indexValid,
              snapshot.taskPlanning?.isValid ?? true,
              CaptureCommentThread.isValid(snapshot.commentEntries, aggregate: snapshot.comment),
              snapshot.reminderAcknowledgment?.isValid ?? true,
              (snapshot.reminderAcknowledgment?.revision ?? 0) <= snapshot.reminderRevision,
              CapturePasteHistory.isValid(snapshot.pasteHistory ?? []) else {
            throw CaptureStoreError.invalidOriginal("The metadata schema or identity is unsupported. The store was preserved.")
        }
    }

    private static func validateStoreFiles(root: URL) throws {
        // Inspect the directory entries themselves, including dangling symlinks, before SQLite opens them.
        for filename in ["metadata.store", "metadata.store-wal", "metadata.store-shm"] {
            do {
                let attributes = try FileManager.default.attributesOfItem(atPath: root.appendingPathComponent(filename).path)
                guard attributes[.type] as? FileAttributeType == .typeRegular else {
                    throw CaptureStoreError.invalidManagedPath
                }
            } catch let error as CocoaError where error.code == .fileNoSuchFile || error.code == .fileReadNoSuchFile {
                // SQLite will create a missing store or sidecar inside the already-validated archive root.
                continue
            }
        }
    }
}
