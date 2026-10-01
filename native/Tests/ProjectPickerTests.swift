import Foundation

@main struct ProjectPickerTests {
    @MainActor static func main() throws {
        var checks = 0
        func expect(_ condition: Bool, _ message: String) throws {
            checks += 1
            if !condition { throw NSError(domain: "ProjectPickerTests", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
        }
        try expect(ProjectNamePolicy.normalized("  Cafe\u{301}  ") == "Café", "Trim and normalize new names")
        for invalid in ["", "   ", "all projects", " UNFILED ", "A\nB", String(repeating: "a", count: 181)] {
            try expect(ProjectNamePolicy.validationMessage(invalid, existing: []) != nil, "Reject invalid or reserved name")
        }
        try expect(ProjectNamePolicy.validationMessage("cafe\u{301}", existing: ["Café"]) != nil, "Reject normalized case-insensitive duplicate")
        try expect(ProjectNamePolicy.validationMessage("לקוח 日本語", existing: []) == nil, "Allow mixed-language project")
        let long = String(repeating: "文", count: 180)
        try expect(ProjectNamePolicy.validationMessage(long, existing: []) == nil, "180-character boundary is accepted")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("DaBin-ProjectPicker-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = try CaptureStore(root: root)
        let workspace = WorkspaceStore(root: root)
        try expect(workspace.projectColorHex(for: nil) == nil,
                   "Unfiled has no synthetic project color")
        try expect(workspace.projectColorHex(for: "Not created yet") == WorkspaceStore.defaultProjectColorHex,
                   "Named projects without a stored choice use the stable default")
        try workspace.createProject(name: "Color client", colorHex: "a1b2c3")
        try expect(workspace.projectNames.contains("Color client")
                   && workspace.scratchpad(project: "Color client").isEmpty
                   && workspace.projectColorHex(for: "Color client") == "A1B2C3",
                   "Project creation atomically persists its empty marker and canonical RGB color")
        try workspace.setProjectColor(hex: "0f71c9", for: "Color client")
        try expect(workspace.projectColorHex(for: "Color client") == "0F71C9",
                   "Changing a project color canonicalizes and persists the new RGB value")
        for invalidColor in ["#112233", "12345", "1234567", "GG1122", "１２３４５６"] {
            do {
                try workspace.setProjectColor(hex: invalidColor, for: "Color client")
                try expect(false, "Invalid RGB value must be rejected")
            } catch WorkspaceError.invalidProjectColor { }
        }
        try expect(workspace.projectColorHex(for: "Color client") == "0F71C9",
                   "Rejected color edits preserve the prior project color")

        workspace.failureInjector = { throw CaptureStoreError.injectedInterruption }
        do {
            try workspace.createProject(name: "Interrupted project", colorHex: "112233")
            try expect(false, "Injected project save must fail")
        } catch CaptureStoreError.injectedInterruption { }
        workspace.failureInjector = nil
        try expect(!workspace.projectNames.contains("Interrupted project"),
                   "A failed atomic project creation publishes neither its marker nor its color")

        let reopenedColors = WorkspaceStore(root: root)
        try expect(reopenedColors.projectNames.contains("Color client")
                   && reopenedColors.projectColorHex(for: "Color client") == "0F71C9",
                   "Project colors and empty project markers survive restart")

        let stamp = Date(timeIntervalSinceReferenceDate: 100)
        var currentSnapshot = WorkspaceSnapshot()
        currentSnapshot.scratchpads[WorkspaceSnapshot.projectKey("Current")] =
            WorkspaceScratchpad(text: "", projectName: "Current", updatedAt: stamp)
        currentSnapshot.projectColors = ["Current": "111111"]
        var incomingSnapshot = currentSnapshot
        incomingSnapshot.scratchpads[WorkspaceSnapshot.projectKey("Incoming")] =
            WorkspaceScratchpad(text: "", projectName: "Incoming", updatedAt: stamp)
        incomingSnapshot.projectColors = ["Current": "222222", "Incoming": "333333"]
        let merged = try WorkspaceSnapshot.merging(incomingSnapshot, into: currentSnapshot)
        try expect(merged.projectColors == ["Current": "111111", "Incoming": "333333"],
                   "Workspace restore adds missing colors without overwriting current choices")
        var unsafeSnapshot = currentSnapshot
        unsafeSnapshot.projectColors = ["Current": "#111111"]
        do {
            _ = try unsafeSnapshot.validated()
            try expect(false, "Decorated color strings must not enter the workspace archive")
        } catch WorkspaceError.invalidArchive { }
        unsafeSnapshot = currentSnapshot
        unsafeSnapshot.projectColors = ["Orphan": "112233"]
        do {
            _ = try unsafeSnapshot.validated()
            try expect(false, "Color keys without a persisted project marker must be rejected")
        } catch WorkspaceError.invalidArchive { }
        let legacyData = try JSONEncoder().encode(WorkspaceSnapshot())
        let legacySnapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: legacyData)
        try expect(legacySnapshot.projectColors == nil,
                   "A workspace with no project-color field remains backward compatible")

        try workspace.setScratchpad(text: "", project: long)
        workspace.selectedProject = long
        let capture = try store.capture(text: "A named project item")[0]
        try store.setOrganization(capture, pinned: false, projectName: long)
        try expect(capture.projectName == long, "Project filing retains the complete accepted name")
        let unfiled = try store.capture(text: "Unfiled text")[0]
        workspace.mode = .clipboard; workspace.explorerUnfiledOnly = true
        let results = WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "")
        try expect(results.map(\.id) == [unfiled.id], "Unfiled applies consistently to Clipboard")
        workspace.explorerUnfiledOnly = false
        try expect(WorkspaceQuery.items(store.captures, workspace: workspace, project: nil, filter: .all, query: "").count == 2,
                   "All projects clears the Unfiled restriction")
        let reopened = WorkspaceStore(root: root)
        try expect(reopened.selectedProject == long && reopened.projectNames.contains(long)
                   && reopened.projectColorHex(for: "Color client") == "0F71C9",
                   "Long project and project colors persist across restart")
        print("PASS: \(checks) shared project picker and scope checks")
    }
}
