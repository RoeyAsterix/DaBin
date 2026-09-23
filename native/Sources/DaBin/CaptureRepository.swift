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
        return try context.fetch(request).map { record in
            guard let data = record.value(forKey: "payload") as? Data else {
                throw CaptureStoreError.invalidOriginal("A saved metadata record is unreadable.")
            }
            let snapshot = try JSONDecoder().decode(CaptureSnapshot.self, from: data)
            try validate(snapshot, recordID: record.value(forKey: "captureID") as? UUID)
            return snapshot
        }
    }

    /// Upsert the supplied captures as one transaction, preserving every unrelated record.
    func save(_ captures: [Capture]) throws {
        try saveSnapshots(captures.map(CaptureSnapshot.init))
    }

    /// Delete exactly one indexed capture in a single metadata transaction.
    func remove(id: UUID) throws {
        do {
            let request = NSFetchRequest<NSManagedObject>(entityName: "CaptureRecord")
            request.predicate = NSPredicate(format: "captureID == %@", id as NSUUID)
            let records = try context.fetch(request)
            guard records.count == 1 else {
                throw CaptureStoreError.invalidOriginal("This capture is no longer in the archive.")
            }
            context.delete(records[0])
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
            for snapshot in snapshots {
                try validate(snapshot, recordID: snapshot.id)
                let data = try encoder.encode(snapshot)
                let request = NSFetchRequest<NSManagedObject>(entityName: "CaptureRecord")
                request.predicate = NSPredicate(format: "captureID == %@", snapshot.id as NSUUID)
                request.fetchLimit = 1
                let record = try context.fetch(request).first
                    ?? NSEntityDescription.insertNewObject(forEntityName: "CaptureRecord", into: context)
                record.setValue(snapshot.id, forKey: "captureID")
                record.setValue(data, forKey: "payload")
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func validate(_ snapshot: CaptureSnapshot, recordID: UUID?) throws {
        let origin = snapshot.captureOriginRaw.flatMap(CaptureOrigin.init(rawValue:)) ?? .manual
        guard [1, 2, 3, 4].contains(snapshot.schemaVersion), CaptureKind(rawValue: snapshot.kindRaw) != nil,
              recordID == snapshot.id,
              snapshot.captureOriginRaw.map({ CaptureOrigin(rawValue: $0) != nil }) ?? true,
              !origin.isAutomatic || snapshot.automaticActionID != nil else {
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
