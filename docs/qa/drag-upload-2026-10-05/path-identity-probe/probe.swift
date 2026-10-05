import Foundation
import Darwin

let files = FileManager.default
let temp = files.temporaryDirectory
let requested = temp.appendingPathComponent("DaBinPathIdentityQA-" + UUID().uuidString, isDirectory: true)
try files.createDirectory(at: requested, withIntermediateDirectories: false)
defer { try? files.removeItem(at: requested) }
let root = requested.resolvingSymlinksInPath().standardizedFileURL
let id = UUID().uuidString
let created = root.appendingPathComponent(id, isDirectory: true)
try files.createDirectory(at: created, withIntermediateDirectories: false)
let listed = try files.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)[0]
func description(_ url: URL) -> [String: String] {
    let real = url.withUnsafeFileSystemRepresentation { path -> String in
        guard let path, let resolved = realpath(path, nil) else { return "<unresolved>" }
        defer { free(resolved) }
        return String(cString: resolved)
    }
    return ["absoluteString": url.absoluteString, "path": url.path,
            "standardizedPath": url.standardizedFileURL.path,
            "resolvedPath": url.resolvingSymlinksInPath().standardizedFileURL.path,
            "realpath": real]
}
var directStat = stat(), listedStat = stat()
let directRead = created.withUnsafeFileSystemRepresentation { $0.map { lstat($0, &directStat) } ?? -1 }
let listedRead = listed.withUnsafeFileSystemRepresentation { $0.map { lstat($0, &listedStat) } ?? -1 }
let report: [String: Any] = [
    "temporaryDirectory": description(temp), "requestedRoot": description(requested),
    "resolvedRoot": description(root), "registeredDirectory": description(created), "enumeratedDirectory": description(listed),
    "productionStringKeysEqual": created.path == listed.path,
    "URLValuesEqual": created == listed,
    "resolvedStringKeysEqual": created.resolvingSymlinksInPath().standardizedFileURL.path == listed.resolvingSymlinksInPath().standardizedFileURL.path,
    "sameNativeDirectory": directRead == 0 && listedRead == 0 && directStat.st_dev == listedStat.st_dev && directStat.st_ino == listedStat.st_ino,
    "productionRegisteredKey": created.path,
    "productionEnumeratedKey": listed.path,
    "proposedRootAndIDKey": root.path + "/" + id
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: URL(fileURLWithPath: "/private/tmp/dabin-outgoing-path-identity-20261005/report.json"))
print(String(decoding: data, as: UTF8.self))
