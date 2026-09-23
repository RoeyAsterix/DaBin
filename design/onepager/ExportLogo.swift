import AppKit
import SwiftUI

@main
struct ExportLogo {
    @MainActor static func main() throws {
        let target = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        let logo = DaBinLogo()
            .environment(\.colorScheme, .light)
            .environment(\.daBinAccent, Color(red: 109.0/255, green: 83.0/255, blue: 135.0/255))
            .padding(2)
        let renderer = ImageRenderer(content: logo)
        renderer.scale = 8
        guard let image = renderer.cgImage else { fatalError("Logo rendering failed") }
        let bitmap = NSBitmapImageRep(cgImage: image)
        try bitmap.representation(using: .png, properties: [:])!.write(to: target.appendingPathComponent("DaBin-logo.png"))
        print("Exported original native logo: \(image.width) x \(image.height)")
    }
}
