import AppKit

@main
enum DaBinMain {
    @MainActor static func main() {
        // Local maintenance without opening windows, reading the clipboard,
        // fetching previews, or scheduling notifications. Run with DaBin closed.
        if CommandLine.arguments.contains("--organize-archive") {
            do {
                let store = try CaptureStore()
                let folder = try store.prepareArchiveFolder()
                print("Local archive: \(folder.path)")
                print("Organized \(store.captures.count) captures.")
                if let warning = store.error {
                    fputs("Archive needs attention: \(warning)\n", stderr)
                    exit(2)
                }
            } catch {
                fputs("Could not organize archive: \(error.localizedDescription)\n", stderr)
                exit(1)
            }
            return
        }
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

