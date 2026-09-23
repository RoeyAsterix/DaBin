import AppKit
import SwiftUI

/// Local privacy information remains readable without a network connection.
enum PrivacyInformation {
    static let policyURLKey = "DaBinPrivacyPolicyURL"
    static let supportURLKey = "DaBinSupportURL"

    struct Section: Identifiable {
        let title: String
        let paragraphs: [String]
        var id: String { title }
    }

    static func configuredURL(for key: String, bundle: Bundle = .main) -> URL? {
        validatedURL(bundle.object(forInfoDictionaryKey: key) as? String)
    }

    static func validatedURL(_ value: String?) -> URL? {
        guard let value,
              let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              components.scheme?.lowercased() == "https",
              let host = components.host, !host.isEmpty,
              components.user == nil, components.password == nil else { return nil }
        return components.url
    }

    static func document(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "PrivacyPolicy", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8),
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return """
            ## Your data
            DaBin saves content you explicitly add on this Mac. It has no account, analytics, ads or cloud sync. Optional link previews contact the websites of saved links and are off by default. You can disable them in Settings. Captures remain locally until you remove the app's data folder.

            ## Privacy information unavailable
            The detailed privacy document could not be loaded from this app installation. Keep the local data folder intact and reinstall DaBin to restore the full policy and removal instructions.
            """
        }
        return text
    }

    static func sections(in document: String) -> [Section] {
        ("\n" + document).components(separatedBy: "\n## ").dropFirst().compactMap { block in
            let lines = block.components(separatedBy: "\n")
            guard let title = lines.first, !title.isEmpty else { return nil }
            let paragraphs = lines.dropFirst().joined(separator: "\n")
                .components(separatedBy: "\n\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            return Section(title: title, paragraphs: paragraphs)
        }
    }
}

@MainActor
struct PrivacyPolicySheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.daBinAccent) private var accent
    let dataFolder: URL
    private let sections = PrivacyInformation.sections(in: PrivacyInformation.document())

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Privacy & your data").font(.system(size: 19, weight: .semibold, design: .rounded))
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 12)
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(18)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("DaBin · Updated 23 September 2026")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    ForEach(sections) { section in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(section.title).font(.system(size: 14, weight: .semibold))
                                .accessibilityAddTraits(.isHeader)
                            ForEach(Array(section.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                                Text(paragraph).font(.system(size: 12))
                                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                            }
                        }
                    }
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([dataFolder])
                    } label: {
                        Label("Show DaBin data folder", systemImage: "folder")
                    }.buttonStyle(.plain).foregroundStyle(accent)
                        .help("Reveal the complete local data folder in Finder")
                    if let url = PrivacyInformation.configuredURL(for: PrivacyInformation.policyURLKey) {
                        Link("Privacy policy online", destination: url).foregroundStyle(accent)
                    }
                    if let url = PrivacyInformation.configuredURL(for: PrivacyInformation.supportURLKey) {
                        Link("Contact & support", destination: url).foregroundStyle(accent)
                    }
                }.padding(18)
            }
        }
        .frame(width: 350, height: 440)
        .tint(accent)
    }
}
