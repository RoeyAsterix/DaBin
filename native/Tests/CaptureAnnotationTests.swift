import Foundation

/// All archives are temporary and all timestamps/content are synthetic. No
/// notification client, real clipboard or application-support archive is used.
@main struct CaptureAnnotationTests {
    @MainActor private static var checks = 0
    private static let base = Date(timeIntervalSince1970: 1_700_000_000)

    @MainActor private static func expect(_ value: @autoclosure () throws -> Bool, _ message: String) throws {
        checks += 1
        guard try value() else { throw NSError(domain: "CaptureAnnotationTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    @MainActor private static func rejected(_ body: () throws -> Void, _ message: String) throws {
        var failed = false
        do { try body() } catch { failed = true }
        try expect(failed, message)
    }
    private static func snapshot(_ value: Capture) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(CaptureSnapshot(value))
    }

    @MainActor static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinAnnotations-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try legacy(root.appendingPathComponent("Legacy"))
        try comments(root.appendingPathComponent("Comments"))
        try commentRemoval(root.appendingPathComponent("CommentRemoval"))
        try acknowledgments(root.appendingPathComponent("Acknowledgments"))
        try combinedFocus(root.appendingPathComponent("Combined"))
        try malformed(root.appendingPathComponent("Malformed"))
        print("PASS: \(checks) annotation checks; legacy threads, edits, exact comment deletion/additive Undo, search/export, restart/backup, exact reminder/focus acknowledgments and atomic rollback.")
    }

    @MainActor private static func legacy(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let capture = Capture(capturedAt: base, kind: .text, originalText: "Original stays exact", title: "Legacy")
        capture.comment = "  Earlier comment\nwith exact spacing.  "
        var object = try JSONSerialization.jsonObject(with: snapshot(capture)) as! [String: Any]
        object["schemaVersion"] = 10
        object.removeValue(forKey: "commentEntries")
        object.removeValue(forKey: "reminderAcknowledgment")
        let old = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try CaptureRepository(root: root).saveSnapshots([old])
        let loaded = try CaptureStore(root: root).captures[0]
        try expect(loaded.comment == capture.comment && loaded.commentCount == 1, "Old single comment survives as one thread entry without changing bytes")
        try expect(loaded.commentThread[0].id == capture.id && loaded.commentThread[0].createdAt == nil, "Legacy entry identity is stable and its unknown posting date stays unknown")
        try expect(loaded.reminderAcknowledgment == nil && !loaded.isReminderAcknowledged, "Missing acknowledgment fields are backward compatible")
        let roundtrip = Capture(snapshot: try JSONDecoder().decode(CaptureSnapshot.self, from: snapshot(loaded)))
        try expect(roundtrip.commentThread == loaded.commentThread && CaptureSnapshot(roundtrip).schemaVersion == 11, "Legacy thread roundtrip upgrades additively to schema11")
        capture.comment = " \n\t "
        let blank = Capture(snapshot: CaptureSnapshot(capture))
        try expect(blank.comment == capture.comment && blank.commentCount == 0, "Whitespace-only legacy bytes survive without an empty visible comment")
    }

    @MainActor private static func comments(_ root: URL) throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let note = try store!.createNote(text: "Immutable original", at: base)
        note.comment = "Legacy introduction"
        try store!.save(captures: [note])
        let later = try store!.appendComment(note, text: "Second reply: NeedleΩ", at: base.addingTimeInterval(20))
        let earlier = try store!.appendComment(note, text: "  First reply\n    preserve code indent", at: base.addingTimeInterval(10))
        try expect(note.commentThread.map(\.id) == [note.id, earlier.id, later.id], "Thread is chronological with legacy text first")
        try expect(note.comment == "Legacy introduction\n\n  First reply\n    preserve code indent\n\nSecond reply: NeedleΩ", "Existing comment consumers receive deterministic full text with whitespace retained")
        try expect(note.originalText == "Immutable original" && note.capturedAt == base, "Adding a comment never changes original content or receipt date")
        let edited = try store!.updateComment(note, id: earlier.id, text: "Edited first reply", at: base.addingTimeInterval(30))
        try expect(edited.id == earlier.id && edited.createdAt == earlier.createdAt && edited.editedAt == base.addingTimeInterval(30), "Editing keeps identity and posting date and records an edit time")
        try expect(note.commentThread.map(\.id) == [note.id, earlier.id, later.id], "Editing does not reorder a thread")
        let results = CaptureSearch.groups(captures: [note], query: "NeedleΩ", filter: .all, includeContext: false)
        try expect(results.flatMap(\.entries).map(\.id) == [note.id], "New replies remain searchable through legacy aggregate consumers")
        let export = DayExportDocument.make(captures: [note], selectedDate: base)
        try expect(export.text.contains("Edited first reply") && export.text.contains("Second reply: NeedleΩ"), "Day exports include every reply")
        let human = try String(contentsOf: store!.archiveURL(for: note)!.appendingPathComponent("Capture.md"), encoding: .utf8)
        try expect(human.contains("Earlier comment — date unavailable") && human.contains("Second reply: NeedleΩ"), "Readable archive includes thread chronology without inventing legacy dates")
        let before = try snapshot(note)
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store!.appendComment(note, text: "Must roll back") }, "A failed append is reported")
        try expect(try snapshot(note) == before, "Failed append restores entries, aggregate text and edit time")
        try rejected({ _ = try store!.updateComment(note, id: earlier.id, text: "Must also roll back") }, "A failed edit is reported")
        try expect(try snapshot(note) == before, "Failed edit restores every persisted field")
        store!.failureInjector = nil
        try rejected({ _ = try store!.appendComment(note, text: " \n ") }, "Blank replies are rejected")
        try rejected({ _ = try store!.updateComment(note, id: UUID(), text: "Missing") }, "An unknown reply cannot replace another one")
        try expect(try snapshot(note) == before, "Rejected input leaves the thread unchanged")
        let thread = note.commentThread
        let id = note.id
        store = nil
        let reopened = try CaptureStore(root: root)
        let restored = reopened.captures.first { $0.id == id }!
        try expect(restored.commentThread == thread, "All reply identities, dates and text survive restart")
        try reopened.update(restored, comment: restored.comment, reminderAt: base, reminderTimeZoneID: "UTC")
        try expect(restored.commentThread == thread, "Unchanged aggregate in an old editor never flattens the thread")
        let backup = root.deletingLastPathComponent().appendingPathComponent("Thread.dabinbackup")
        try reopened.exportBackup(to: backup)
        let restoredStore = try CaptureStore(root: root.deletingLastPathComponent().appendingPathComponent("ThreadRestored"))
        _ = try restoredStore.restoreBackup(from: backup)
        try expect(restoredStore.captures[0].commentThread == thread, "Portable backup/restore retains full comment history")
        let beforeLegacyEdit = try snapshot(restored)
        reopened.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ try reopened.update(restored, comment: "Rejected aggregate replacement", reminderAt: nil, reminderTimeZoneID: nil) }, "A failed compatibility edit is reported")
        try expect(try snapshot(restored) == beforeLegacyEdit, "Failed aggregate edits roll back the full thread and reminder together")
        reopened.failureInjector = nil
        try reopened.update(restored, comment: "Explicit legacy replacement", reminderAt: restored.reminderAt, reminderTimeZoneID: "UTC")
        try expect(restored.commentCount == 1 && restored.commentThread[0].text == "Explicit legacy replacement", "An explicit aggregate edit has a deterministic compatibility fallback")
        let recurring = try reopened.createTask(text: "Recurring fixture", at: base)
        _ = try reopened.appendComment(recurring, text: "Keep this context", at: base)
        var planning = TaskPlanning(); planning.plannedDay = CaptureCalendar.dayString(Date()); planning.recurrence = .daily
        try reopened.setTaskPlanning(recurring, planning: planning)
        try reopened.setTaskCompleted(recurring, completed: true)
        let successor = reopened.captures.first { $0.taskPlanning?.previousOccurrenceID == recurring.id }
        try expect(successor?.commentThread == recurring.commentThread, "Recurring successor preserves reply provenance rather than flattening it")
    }

    @MainActor private static func commentRemoval(_ root: URL) throws {
        let store = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let note = try store.createTask(text: "Original task and receipt stay intact", at: base)
        var planning = TaskPlanning()
        planning.checklist = [TaskChecklistItem(text: "Keep this unrelated step")]
        try store.setTaskPlanning(note, planning: planning)
        note.comment = "  Legacy text\nwith its exact whitespace  "
        try store.save(captures: [note])
        let first = try store.appendComment(note, text: "First reply — שלום", at: base.addingTimeInterval(10))
        let removed = try store.appendComment(note, text: "Reply to delete", at: base.addingTimeInterval(20))
        let edited = try store.updateComment(note, id: removed.id, text: "Edited reply\n日本語", at: base.addingTimeInterval(25))
        let other = try store.createNote(text: "Another capture remains separate", at: base)
        let before = try snapshot(note)
        let beforeOther = try snapshot(other)
        let originalThread = note.commentThread
        let legacyEntry = originalThread[0]
        try rejected({ _ = try store.removeComment(note, id: UUID()) }, "Unknown comment deletion cannot remove a neighboring reply")
        try rejected({ _ = try store.removeComment(note, id: removed.id, at: Date(timeIntervalSince1970: .infinity)) },
            "An invalid deletion timestamp is rejected before mutation")
        try expect(try snapshot(note) == before && snapshot(other) == beforeOther, "Rejected deletion leaves every capture field unchanged")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store.removeComment(note, id: removed.id, at: base.addingTimeInterval(30)) }, "Failed comment deletion is reported")
        try expect(try snapshot(note) == before, "Failed deletion rolls back entries, aggregate and edit timestamp exactly")
        let failedReload = try CaptureStore(root: root, repairArchiveOnOpen: false)
        try expect(failedReload.captures.first { $0.id == note.id }?.commentThread == originalThread,
            "A fresh store confirms failed deletion left the durable thread intact")
        store.failureInjector = nil
        let receipt = try store.removeComment(note, id: removed.id, at: base.addingTimeInterval(30))
        try expect(receipt.captureID == note.id && receipt.entry == edited,
            "Removal receipt retains the exact capture, reply UUID, text, posting date and edit date")
        try expect(note.commentThread == [legacyEntry, first] && !note.comment.contains("Edited reply"),
            "Deleting one exact reply preserves every neighboring comment and updates searchable aggregate text")
        let afterRemoval = try snapshot(note)
        try rejected({ _ = try store.removeComment(note, id: removed.id) }, "Repeating deletion cannot remove another reply")
        try expect(try snapshot(note) == afterRemoval, "Repeated deletion leaves the surviving conversation unchanged")
        try expect(note.originalText == "Original task and receipt stay intact" && note.capturedAt == base
            && note.title == "Original task and receipt stay intact" && note.taskPlanning == planning,
            "Comment deletion leaves original content, receipt, title and checklist untouched")
        try expect(try snapshot(other) == beforeOther, "Deleting a comment never changes another capture")
        let later = try store.appendComment(note, text: "Later reply after deletion", at: base.addingTimeInterval(40))
        let changedFirst = try store.updateComment(note, id: first.id, text: "Later edit of the neighboring reply", at: base.addingTimeInterval(45))
        let beforeUndo = try snapshot(note)
        let invalidReceipt = CaptureCommentRemovalReceipt(captureID: note.id,
            entry: CaptureCommentEntry(createdAt: base, text: " \n "))
        try rejected({ _ = try store.restoreComment(note, receipt: invalidReceipt) }, "Undo refuses an invalid empty reply before changing saved content")
        let extraLegacyReceipt = CaptureCommentRemovalReceipt(captureID: note.id,
            entry: CaptureCommentEntry(createdAt: nil, text: "A contradictory second legacy entry"))
        try rejected({ _ = try store.restoreComment(note, receipt: extraLegacyReceipt) }, "Undo cannot create two legacy undated thread entries")
        try expect(try snapshot(note) == beforeUndo, "Invalid restoration receipts preserve exact current metadata")
        try rejected({ _ = try store.restoreComment(other, receipt: receipt) }, "A removal receipt cannot restore into a different capture")
        try rejected({ _ = try store.restoreComment(note, receipt: receipt, at: Date(timeIntervalSince1970: .infinity)) },
            "An invalid restoration timestamp is rejected")
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store.restoreComment(note, receipt: receipt, at: base.addingTimeInterval(50)) }, "Failed Undo remains retryable")
        try expect(try snapshot(note) == beforeUndo, "Failed Undo rolls back the whole live snapshot without losing later replies or edits")
        let failedUndoReload = try CaptureStore(root: root, repairArchiveOnOpen: false)
        try expect(failedUndoReload.captures.first { $0.id == note.id }?.commentThread == note.commentThread,
            "Failed Undo leaves the durable thread in its prior state")
        store.failureInjector = nil
        try expect(try store.restoreComment(note, receipt: receipt, at: base.addingTimeInterval(50)), "The same receipt can retry Undo after storage recovers")
        try expect(note.commentThread == [legacyEntry, changedFirst, edited, later],
            "Additive Undo restores the exact deleted reply in chronology while preserving later additions and edits")
        try expect(note.comment.contains("Later reply after deletion") && note.comment.contains("Edited reply")
            && note.originalText == "Original task and receipt stay intact" && note.taskPlanning == planning,
            "Undo updates aggregate text without replacing the conversation or unrelated task fields")
        let beforeNoOp = try snapshot(note)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try expect(try store.restoreComment(note, receipt: receipt, at: base.addingTimeInterval(60)) == false,
            "Repeating exact Undo is an idempotent no-op that performs no write")
        try expect(try snapshot(note) == beforeNoOp, "Repeated Undo keeps its existing text, chronology and update timestamp")
        store.failureInjector = nil
        _ = try store.updateComment(note, id: edited.id, text: "Changed after successful Undo", at: base.addingTimeInterval(60))
        let changed = try snapshot(note)
        try rejected({ _ = try store.restoreComment(note, receipt: receipt) }, "Undo never overwrites changed text now owning the same reply identity")
        try expect(try snapshot(note) == changed, "Conflicting identity preserves all current data")
        let legacyReceipt = try store.removeComment(note, id: note.id, at: base.addingTimeInterval(70))
        try expect(legacyReceipt.entry == legacyEntry && legacyReceipt.entry.createdAt == nil,
            "Legacy deletion retains exact bytes and does not invent a posting date")
        try expect(try store.restoreComment(note, receipt: legacyReceipt, at: base.addingTimeInterval(80)), "A legacy reply can be restored additively")
        try expect(note.commentThread[0] == legacyEntry && note.commentThread.count == 4, "Legacy Undo preserves its original position and every modern reply")
        let reloaded = try CaptureStore(root: root, repairArchiveOnOpen: false)
        let persistedThread = reloaded.captures.first { $0.id == note.id }!.commentThread
        try expect(persistedThread == note.commentThread, "Deleted and restored reply provenance survives a fresh store")
        let backup = root.deletingLastPathComponent().appendingPathComponent("CommentRemoval.dabinbackup")
        try store.exportBackup(to: backup)
        let backupTarget = try CaptureStore(root: root.deletingLastPathComponent().appendingPathComponent("CommentRemovalRestored"), repairArchiveOnOpen: false)
        _ = try backupTarget.restoreBackup(from: backup)
        try expect(backupTarget.captures.first { $0.id == note.id }?.commentThread == note.commentThread,
            "Backup and restore retain the post-Undo conversation exactly")
        let stale = Capture(snapshot: CaptureSnapshot(note))
        try rejected({ _ = try store.removeComment(stale, id: first.id) }, "A stale capture object cannot delete a current reply")
        try rejected({ _ = try store.restoreComment(stale, receipt: receipt) }, "A stale capture object cannot restore a reply")
        try store.moveToTrash(note)
        try rejected({ _ = try store.removeComment(note, id: first.id) }, "A trashed capture cannot lose a comment through a stale action")
        try rejected({ _ = try store.restoreComment(note, receipt: legacyReceipt) }, "Comment Undo cannot resurrect a deleted capture")

        let single = try store.createNote(text: "One comment only", at: base)
        let singleEntry = try store.appendComment(single, text: "Keep exact last-reply bytes", at: base)
        let singleReceipt = try store.removeComment(single, id: singleEntry.id, at: base.addingTimeInterval(1))
        try expect(single.commentCount == 0 && single.comment.isEmpty && single.commentEntries.isEmpty,
            "Deleting the last reply empties both aggregate and entries without a ghost legacy comment")
        _ = try store.restoreComment(single, receipt: singleReceipt, at: base.addingTimeInterval(2))
        try expect(single.commentThread == [singleEntry], "Undo of the last reply restores exactly one original entry")

        let longLegacy = try store.createNote(text: "Legacy comments may exceed the new reply limit", at: base)
        longLegacy.comment = String(repeating: "L", count: CaptureCommentThread.maximumNewCommentCharacters + 1)
        try store.save(captures: [longLegacy])
        let longReceipt = try store.removeComment(longLegacy, id: longLegacy.id, at: base.addingTimeInterval(1))
        _ = try store.restoreComment(longLegacy, receipt: longReceipt, at: base.addingTimeInterval(2))
        try expect(longLegacy.commentThread == [longReceipt.entry], "Undo preserves valid long legacy content instead of imposing the new-comment input limit")

        let full = try store.createNote(text: "Comment capacity remains enforced", at: base)
        let fullEntries = (0..<CaptureCommentThread.maximumEntries).map {
            CaptureCommentEntry(createdAt: base.addingTimeInterval(Double($0)), text: "Synthetic reply \($0)")
        }
        full.setCommentEntries(fullEntries); full.comment = CaptureCommentThread.text(fullEntries)
        try store.save(captures: [full])
        let fullReceipt = try store.removeComment(full, id: fullEntries[0].id, at: base)
        _ = try store.appendComment(full, text: "A later reply uses the available slot", at: base.addingTimeInterval(2_000))
        let fullBeforeUndo = try snapshot(full)
        try rejected({ _ = try store.restoreComment(full, receipt: fullReceipt) }, "Undo cannot exceed the durable thread limit after a later reply fills its slot")
        try expect(try snapshot(full) == fullBeforeUndo && full.commentCount == CaptureCommentThread.maximumEntries,
            "A full-thread Undo refusal preserves every current reply for a later retry")
    }

    @MainActor private static func acknowledgments(_ root: URL) throws {
        var store: CaptureStore? = try CaptureStore(root: root)
        let first = try store!.createNote(text: "Reminder A", at: base)
        let second = try store!.createNote(text: "Reminder B", at: base)
        for capture in [first, second] { try store!.update(capture, comment: "Keep this comment", reminderAt: base, reminderTimeZoneID: "UTC") }
        let tokens = [first.reminderOccurrence!, second.reminderOccurrence!]
        let originals = try [snapshot(first), snapshot(second)]
        store!.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store!.acknowledgeReminders(tokens, at: base.addingTimeInterval(1)) }, "Injected acknowledgment failure is surfaced")
        try expect(try [snapshot(first), snapshot(second)] == originals, "A batch failure rolls back both acknowledgment fields and edit timestamps")
        store!.failureInjector = nil
        second.contentIndexState = "invalid"
        try rejected({ _ = try store!.acknowledgeReminders(tokens, at: base.addingTimeInterval(1)) }, "Metadata validation failure aborts the entire batch")
        second.contentIndexState = "idle"
        try expect(!first.isReminderAcknowledged && !second.isReminderAcknowledged, "Repository failure rolls back live objects for every record")
        let failedReload = try CaptureStore(root: root)
        try expect(failedReload.captures.allSatisfy { !$0.isReminderAcknowledged }, "Repository rollback leaves no partial durable acknowledgment")
        try expect(try store!.acknowledgeReminders(tokens + tokens, at: base.addingTimeInterval(2)) == 2, "A batch acknowledges each due occurrence exactly once despite duplicate tokens")
        try expect(first.reminderAt == base && first.title == "Reminder A" && first.comment == "Keep this comment" && !first.isCompleted, "Acknowledging does not clear reminders, titles, comments or complete tasks")
        try expect(try store!.acknowledgeReminders(tokens, at: base.addingTimeInterval(3)) == 0, "Repeated acknowledgment is a no-op")
        let firstID = first.id
        store = nil
        let reopened = try CaptureStore(root: root)
        let current = reopened.captures.first { $0.id == firstID }!
        try expect(reopened.captures.allSatisfy(\.isReminderAcknowledged), "A due alert remains acknowledged after restart")
        let oldRevision = current.reminderRevision
        try reopened.update(current, comment: current.comment, reminderAt: base.addingTimeInterval(5), reminderTimeZoneID: "UTC")
        try expect(current.reminderRevision > oldRevision && !current.isReminderAcknowledged, "A rescheduled reminder is a fresh unacknowledged occurrence")
        try expect(try reopened.acknowledgeReminders(tokens, at: base.addingTimeInterval(10)) == 0 && !current.isReminderAcknowledged, "Closing an old popup cannot acknowledge the new schedule")
        try expect(try reopened.acknowledgeReminders([current.reminderOccurrence!], at: base) == 0, "Future reminders cannot be acknowledged early")
        try expect(try reopened.acknowledgeReminders(captures: [current], at: base.addingTimeInterval(10)) == 1, "Current due occurrence can be acknowledged")
        let backup = root.deletingLastPathComponent().appendingPathComponent("Acknowledged.dabinbackup")
        try reopened.exportBackup(to: backup)
        let target = try CaptureStore(root: root.deletingLastPathComponent().appendingPathComponent("AcknowledgedRestored"))
        _ = try target.restoreBackup(from: backup)
        try expect(target.captures.allSatisfy(\.isReminderAcknowledged), "Backup/restore retains durable acknowledgments")
        let completed = try reopened.createTask(text: "Completed", at: base)
        try reopened.update(completed, comment: "", reminderAt: base, reminderTimeZoneID: "UTC")
        try reopened.setTaskCompleted(completed, completed: true)
        let excluded = completed.reminderOccurrence!
        try expect(try reopened.acknowledgeReminders([excluded], at: base.addingTimeInterval(20)) == 0, "Completed tasks are excluded")
        let deletedToken = current.reminderOccurrence!
        try reopened.moveToTrash(current)
        try expect(try reopened.acknowledgeReminders([deletedToken], at: base.addingTimeInterval(20)) == 0, "Deleted captures are excluded")
    }

    @MainActor private static func combinedFocus(_ root: URL) throws {
        let store = try CaptureStore(root: root)
        let task = try store.createTask(text: "Timer and reminder", at: base)
        try store.update(task, comment: "Keep task context", reminderAt: base, reminderTimeZoneID: "UTC")
        var session = TaskFocusSession(remainingSeconds: 0, endAt: nil)
        session.completedAlertID = UUID(); session.completedAt = base
        try store.setTaskFocus(task, session: session, durationMinutes: 5)
        let focus = task.focusOccurrence!
        let reminder = task.reminderOccurrence!
        let before = try snapshot(task)
        store.failureInjector = { if $0 == .beforeMetadataSave { throw CaptureStoreError.importVerificationFailed } }
        try rejected({ _ = try store.acknowledgeAlerts(reminders: [reminder], focus: [focus], at: base.addingTimeInterval(1)) }, "Combined focus/reminder acknowledgment reports failure")
        try expect(try snapshot(task) == before, "Combined failure restores both persisted acknowledgment kinds")
        store.failureInjector = nil
        try expect(try store.acknowledgeAlerts(reminders: [reminder], focus: [focus], at: base.addingTimeInterval(1)) == 2, "One atomic save acknowledges two distinct alert occurrences on one task")
        try expect(task.isReminderAcknowledged && task.taskPlanning?.focusSession?.acknowledgedAt != nil && !task.isCompleted, "Acknowledgment changes alert state without completing the task")
        let reopened = try CaptureStore(root: root)
        try expect(reopened.captures[0].isReminderAcknowledged && reopened.captures[0].taskPlanning?.focusSession?.acknowledgedAt != nil, "Both acknowledgment kinds survive restart")
        let backup = root.deletingLastPathComponent().appendingPathComponent("Combined.dabinbackup")
        try reopened.exportBackup(to: backup)
        let restored = try CaptureStore(root: root.deletingLastPathComponent().appendingPathComponent("CombinedRestored"))
        _ = try restored.restoreBackup(from: backup)
        try expect(restored.captures[0].reminderAcknowledgment == task.reminderAcknowledgment
            && restored.captures[0].taskPlanning?.focusSession == task.taskPlanning?.focusSession,
            "A portable backup preserves both acknowledgment kinds exactly")
        session.completedAlertID = UUID(); session.completedAt = base.addingTimeInterval(2)
        try store.setTaskFocus(task, session: session)
        try expect(try store.acknowledgeAlerts(reminders: [], focus: [focus], at: base.addingTimeInterval(3)) == 0, "Old focus popup cannot acknowledge a new completion identity")
        try expect(task.taskPlanning?.focusSession?.acknowledgedAt == nil, "New focus completion remains pending")
    }

    @MainActor private static func malformed(_ root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = try CaptureRepository(root: root)
        let capture = Capture(capturedAt: base, kind: .text, originalText: "Test", title: "Test")
        let entry = CaptureCommentEntry(createdAt: base, text: "Reply")
        capture.comment = entry.text; capture.setCommentEntries([entry])
        let original = try JSONSerialization.jsonObject(with: snapshot(capture)) as! [String: Any]
        var object = original
        let entries = original["commentEntries"] as! [Any]
        object["commentEntries"] = entries + entries
        let duplicate = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try rejected({ try repository.saveSnapshots([duplicate]) }, "Duplicate comment identities are rejected before saving")
        object = original; object["comment"] = "Contradictory aggregate"
        let mismatch = try JSONDecoder().decode(CaptureSnapshot.self, from: JSONSerialization.data(withJSONObject: object))
        try rejected({ try repository.saveSnapshots([mismatch]) }, "A contradictory thread aggregate is rejected")
        capture.setReminderAcknowledgment(CaptureReminderAcknowledgment(revision: 1, dueAt: base, acknowledgedAt: base.addingTimeInterval(-1)))
        try rejected({ try repository.save([capture]) }, "Invalid acknowledgment timestamps/revisions are rejected")
        try expect(try repository.load().isEmpty, "Invalid snapshots leave no partial records")
    }
}
