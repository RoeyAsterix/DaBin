import Foundation

@main struct SearchResultExcerptTests {
    @MainActor private static var checks = 0
    @MainActor private static func expect(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        checks += 1
        guard condition() else {
            throw NSError(domain: "SearchResultExcerptTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: message])
        }
    }

    @MainActor static func main() throws {
        let distant = String(repeating: "Fictional background material. ", count: 300)
            + "A distinctive constellation query belongs here. "
            + String(repeating: "Fictional later material. ", count: 100)
        let body = Capture(kind: .text, originalText: distant, title: "Fictional client feedback")
        let bodyEntry = SearchEntry(capture: body, isMatch: true, indexedTextMatch: nil)
        let bodyExcerpt = SearchResultExcerpt.make(entry: bodyEntry, query: "constellation")
        try expect(bodyExcerpt?.text.contains("constellation") == true,
                   "An original-content match far beyond the first 180 characters remains visible")
        try expect((bodyExcerpt?.text.count ?? 0) <= 182 && bodyExcerpt?.text.hasPrefix("…") == true,
                   "A distant match renders bounded content with an honest truncation cue")
        try expect(bodyExcerpt?.label == nil, "Original captured content does not acquire a misleading extracted-text label")

        let indexed = "Recognized constellation " + String(repeating: "Fictional extracted content. ", count: 100)
        let indexedEntry = SearchEntry(capture: body, isMatch: true, indexedTextMatch: indexed)
        let indexedExcerpt = SearchResultExcerpt.make(entry: indexedEntry, query: "constellation")
        try expect(indexedExcerpt?.label == "Extracted text" && indexedExcerpt?.text.contains("constellation") == true,
                   "Extracted evidence remains visibly distinguished from the immutable source")
        try expect((indexedExcerpt?.text.count ?? 0) <= 182,
                   "An oversized indexed-text snippet cannot bypass the result card's 180-character content bound")

        body.comment = "Fictional approval comment: adjust the milestone."
        let commentExcerpt = SearchResultExcerpt.make(entry: bodyEntry, query: "milestone")
        try expect(commentExcerpt?.label == "Comment" && commentExcerpt?.text.contains("milestone") == true,
                   "A comment-only hit shows the matching comment and explains why the capture matched")
        body.setTaskPlanning(TaskPlanning(checklist: [
            TaskChecklistItem(text: "Prepare fictional invoice"),
            TaskChecklistItem(text: "Ask client about the constellation reference")
        ]))
        let checklistExcerpt = SearchResultExcerpt.make(entry: bodyEntry, query: "invoice")
        try expect(checklistExcerpt?.label == "Checklist" && checklistExcerpt?.text.contains("invoice") == true,
                   "A task-step-only hit shows readable checklist evidence")
        try expect(checklistExcerpt?.text.contains("\n") == false,
                   "Multiline matching fields normalize whitespace inside the compact card")
        body.comment += " Includes the constellation reference."
        try expect(SearchResultExcerpt.make(entry: indexedEntry, query: "constellation")?.label == "Extracted text",
                   "Recognized matching evidence retains its source label when the same term appears in a comment")

        let whitespace = Capture(kind: .text, originalText: " \n\t ", title: "Fictional empty capture")
        let whitespaceEntry = SearchEntry(capture: whitespace, isMatch: true, indexedTextMatch: nil)
        try expect(SearchResultExcerpt.make(entry: whitespaceEntry, query: "") == nil,
                   "Whitespace-only content does not produce a blank excerpt row")
        try expect(SearchResultExcerpt.make(entry: SearchEntry(capture: whitespace, isMatch: true,
                                                             indexedTextMatch: " \n\t "), query: "") == nil,
                   "An empty extracted-text snippet cannot create a blank result row")
        try expect(SearchResultExcerpt.excerpt("", words: ["query"], requiresMatch: true) == nil,
                   "Empty content never manufactures matching evidence")
        try expect(SearchResultExcerpt.excerpt("Fictional content", words: ["missing"], requiresMatch: true) == nil,
                   "A required but absent term returns no misleading matching excerpt")
        try expect(SearchResultExcerpt.excerpt("Fictional content", words: [], requiresMatch: true) == nil,
                   "No query terms cannot be presented as an explicit content match")
        try expect(SearchResultExcerpt.excerpt("one\n\n two\tthree", words: [], requiresMatch: false) == "one two three",
                   "Recent browsing excerpts remain readable without a query")

        let sameTitle = Capture(kind: .text, originalText: "Fictional identical title", title: "Fictional identical title")
        try expect(SearchResultExcerpt.make(entry: SearchEntry(capture: sameTitle, isMatch: true, indexedTextMatch: nil),
                                           query: "") == nil,
                   "Empty-query cards avoid repeating the same title as their body")
        let preview = Capture(kind: .pdf, title: "Fictional brief.pdf")
        preview.previewDescription = "Fictional client summary awaiting approval."
        try expect(SearchResultExcerpt.make(entry: SearchEntry(capture: preview, isMatch: true, indexedTextMatch: nil),
                                           query: "approval")?.text.contains("approval") == true,
                   "Saved preview descriptions provide matching evidence when a file has no original plain text")

        let unicode = String(repeating: "👩🏽‍💻 שלום 東京 ", count: 60) + "Cafe\u{301} rendezvous 🌌"
            + String(repeating: " 🧑‍🚀 مرحبا ", count: 60)
        let unicodeSnippet = SearchResultExcerpt.excerpt(unicode, words: ["CAFÉ"], requiresMatch: true)
        try expect(unicodeSnippet?.contains("Cafe\u{301}") == true && (unicodeSnippet?.count ?? 0) <= 182,
                   "Case and diacritic matching keep full Unicode graphemes intact within the bounded excerpt")
        try expect(unicodeSnippet?.hasPrefix("…") == true && unicodeSnippet?.hasSuffix("…") == true,
                   "Mixed-language text shows both truncation cues around a distant match")
        let emoji = SearchResultExcerpt.excerpt("Before 👩🏽‍💻 after", words: ["👩🏽‍💻"], requiresMatch: true)
        try expect(emoji == "Before 👩🏽‍💻 after", "Multi-scalar emoji remain one intact grapheme")
        try expect(SearchResultExcerpt.excerpt("שלום עולם", words: ["שלום"], requiresMatch: true) == "שלום עולם",
                   "Right-to-left matching preserves the original text instead of reversing characters")

        print("PASS: \(checks) search result excerpt bounds, matching evidence, labels and Unicode checks")
    }
}
