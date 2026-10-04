import Foundation

@main
struct PrivacyInformationTests {
    private static var checks = 0

    private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "PrivacyInformationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    static func main() throws {
        let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let policy = try String(contentsOf: root.appendingPathComponent("Resources/PrivacyPolicy.md"), encoding: .utf8)
        let sections = PrivacyInformation.sections(in: policy)
        try expect(sections.count == 9, "All nine privacy sections are readable")
        try expect(sections.allSatisfy { !$0.title.isEmpty && !$0.paragraphs.isEmpty }, "Every section has content")
        try expect(sections.first?.title == "Your daily board stays on your Mac", "Title and update line are not presented as a body section")
        try expect(sections.last?.title == "Backups and security", "Final policy section is retained")
        let updates = sections.first { $0.title == "Software updates" }
        try expect(updates?.paragraphs.joined(separator: " ").contains("does not check or download updates silently") == true,
                   "The in-app policy explains that GitHub update contact is user initiated")
        let automatic = sections.first { $0.title == "Optional Auto Capture" }
        let automaticText = automatic?.paragraphs.joined(separator: " ") ?? ""
        try expect(automaticText.contains("off by default")
                   && automaticText.contains("does not import what was already on the clipboard")
                   && automaticText.contains("not uploaded"),
                   "The in-app policy explains Auto Capture opt-in, baseline and local-storage boundaries")
        try expect(automaticText.contains("sign with that project name")
                   && automaticText.contains("someone viewing your screen")
                   && automaticText.contains("not guarantee"),
                   "Automatic-save policy discloses local project labels without a capture-exclusion guarantee")
        try expect(automaticText.contains("red recording symbol")
                   && automaticText.contains("when the board is closed"),
                   "The policy explains the persistent active-recording indication independently of confirmations")
        let reminders = sections.first { $0.title == "Reminders" }?.paragraphs.joined(separator: " ") ?? ""
        try expect(reminders.contains("first three words of the task title")
                   && reminders.contains("without marking the task completed")
                   && reminders.contains("do not hide a waiting timer alarm")
                   && reminders.contains("not a guarantee"),
                   "Timer policy discloses visible task words, acknowledgment, quiet behavior and screen-capture limitations")
        let recognition = sections.first { $0.title == "Local text recognition and search" }
        let recognitionText = recognition?.paragraphs.joined(separator: " ") ?? ""
        try expect(recognitionText.contains("Apple frameworks on this Mac")
                   && recognitionText.contains("does not require Screen Recording permission")
                   && recognitionText.contains("permanently deleting the capture also removes its recognized text"),
                   "The policy explains local processing, permission boundaries and recognized-text removal")
        try expect(PrivacyInformation.sections(in: "## First\n\nOne.\n\nTwo.").first?.paragraphs == ["One.", "Two."],
                   "A heading at the start of a fallback document is retained")
        try expect(PrivacyInformation.sections(in: "").isEmpty, "Empty documents produce no empty sections")
        try expect(PrivacyInformation.updatedLine(in: "# DaBin\n\nUpdated 2 October 2026\n\n## Your data\nLocal.") == "Updated 2 October 2026",
                   "The policy update line is derived from the loaded document")
        try expect(PrivacyInformation.updatedLine(in: "# DaBin\r\n\r\n  Updated 1 October 2026  \r\n") == "Updated 1 October 2026",
                   "Policy date extraction handles surrounding whitespace and Windows line endings")
        try expect(PrivacyInformation.updatedLine(in: "## Your data\nNo date here.") == nil,
                   "Undated fallback documents do not invent an update date")
        try expect(PrivacyInformation.updatedLine(in: "Updated \n\nUpdated     \n") == nil,
                   "Empty update labels are not presented as a policy date")
        try expect(PrivacyInformation.updatedLine(in: "Text with Updated 24 September 2026 inside it.") == nil,
                   "A date mentioned in body text is not treated as the policy header")

        for invalid: String? in [nil, "", " ", "http://example.com/privacy", "file:///tmp/policy", "javascript:alert(1)", "https://", "https://name:secret@example.com"] {
            try expect(PrivacyInformation.validatedURL(invalid) == nil, "Unsafe or absent external URLs are not offered")
        }
        try expect(PrivacyInformation.validatedURL(" https://example.com/privacy \n")?.absoluteString == "https://example.com/privacy",
                   "Configured HTTPS policy links normalize surrounding whitespace")

        let fixture = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinPrivacyTests-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: fixture) }
        let resources = fixture.appendingPathComponent("Contents/Resources")
        try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
        let info: [String: Any] = ["CFBundleIdentifier": "com.dabin.privacytests.\(UUID())",
                                  "CFBundlePackageType": "BNDL",
                                  PrivacyInformation.policyURLKey: "https://example.com/privacy",
                                  PrivacyInformation.supportURLKey: "https://example.com/support"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: fixture.appendingPathComponent("Contents/Info.plist"))
        try policy.write(to: resources.appendingPathComponent("PrivacyPolicy.md"), atomically: true, encoding: .utf8)
        guard let bundle = Bundle(url: fixture) else { fatalError("Could not open isolated test bundle") }
        let emptyFixture = FileManager.default.temporaryDirectory.appendingPathComponent("DaBinEmptyPrivacyTests-\(UUID()).bundle")
        defer { try? FileManager.default.removeItem(at: emptyFixture) }
        try FileManager.default.createDirectory(at: emptyFixture.appendingPathComponent("Contents/Resources"), withIntermediateDirectories: true)
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.dabin.emptyprivacytests.\(UUID())", "CFBundlePackageType": "BNDL"], format: .xml, options: 0)
            .write(to: emptyFixture.appendingPathComponent("Contents/Info.plist"))
        guard let emptyBundle = Bundle(url: emptyFixture) else { fatalError("Could not open isolated empty bundle") }
        let fallback = PrivacyInformation.sections(in: PrivacyInformation.document(bundle: emptyBundle))
        try expect(fallback.count == 2 && fallback.first?.title == "Your data", "Missing resource has a readable local fallback")
        try expect(PrivacyInformation.configuredURL(for: PrivacyInformation.policyURLKey, bundle: bundle)?.path == "/privacy",
                   "Published policy URL is read from the build's configuration")
        try expect(PrivacyInformation.configuredURL(for: PrivacyInformation.supportURLKey, bundle: bundle)?.path == "/support",
                   "Support URL is read from the build's configuration")
        try expect(PrivacyInformation.configuredURL(for: "MissingKey", bundle: bundle) == nil, "Missing owner links never use an invented fallback")
        try expect(PrivacyInformation.document(bundle: bundle) == policy, "Bundled policy is loaded without network access")
        try expect(PrivacyInformation.updatedLine(in: PrivacyInformation.document(bundle: bundle)) == "Updated 4 October 2026",
                   "The isolated bundled policy exposes its current update date rather than the retired sheet date")
        try expect(PrivacyInformation.updatedLine(in: PrivacyInformation.document(bundle: emptyBundle)) == nil,
                   "A missing policy resource never claims the full policy's update date")

        let manifestData = try Data(contentsOf: root.appendingPathComponent("Resources/PrivacyInfo.xcprivacy"))
        let manifest = try PropertyListSerialization.propertyList(from: manifestData, options: [], format: nil) as! [String: Any]
        try expect(manifest["NSPrivacyTracking"] as? Bool == false, "Manifest declares no tracking")
        try expect((manifest["NSPrivacyCollectedDataTypes"] as? [Any])?.isEmpty == true, "Manifest does not invent off-device developer data collection")
        let APIs = manifest["NSPrivacyAccessedAPITypes"] as! [[String: Any]]
        let reasons = Dictionary(uniqueKeysWithValues: APIs.map { ($0["NSPrivacyAccessedAPIType"] as! String, $0["NSPrivacyAccessedAPITypeReasons"] as! [String]) })
        try expect(reasons["NSPrivacyAccessedAPICategoryUserDefaults"] == ["CA92.1"], "Preference use has its app-only reason")
        try expect(reasons["NSPrivacyAccessedAPICategorySystemBootTime"] == ["35F9.1"], "Animation timer use has its elapsed-time reason")
        try expect(reasons["NSPrivacyAccessedAPICategoryFileTimestamp"] == ["C617.1"],
                   "Owned preview-cache file metadata declares its app-container reason without unrelated timestamp reasons")
        print("PASS: \(checks) privacy information checks")
    }
}
