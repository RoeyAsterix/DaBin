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
        try expect(reopened.selectedProject == long && reopened.projectNames.contains(long), "Long project persists across restart")
        print("PASS: \(checks) shared project picker and scope checks")
    }
}
