#!/usr/bin/env swift
// Local, dependency-free MP4 inspection and frame extraction for walkthrough QA.
// Usage: swift inspect_video.swift INPUT.mp4 OUTPUT_DIR [--times 0,5,10] [--decode]
import Foundation
import AVFoundation
import CoreGraphics
import CoreText
import ImageIO
import UniformTypeIdentifiers

enum InspectError: Error { case message(String) }

func fourCC(_ value: FourCharCode) -> String {
    String(bytes: [24, 16, 8, 0].map { UInt8((value >> $0) & 255) }, encoding: .ascii) ?? String(value)
}

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        throw InspectError.message("Cannot create PNG: \(url.path)")
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw InspectError.message("PNG write failed: \(url.path)") }
}

func label(_ text: String, x: CGFloat, y: CGFloat, size: CGFloat, context: CGContext) {
    let attributes: [NSAttributedString.Key: Any] = [
        NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Menlo" as CFString, size, nil),
        NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.94, alpha: 1)
    ]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
    context.textPosition = CGPoint(x: x, y: y)
    CTLineDraw(line, context)
}

func contactSheet(_ frames: [(Double, CGImage)], output: URL, title: String) throws {
    let columns = 4, cellWidth = 480, imageHeight = 270, captionHeight = 34, margin = 16, titleHeight = 52
    let rows = (frames.count + columns - 1) / columns
    let width = columns * cellWidth + (columns + 1) * margin
    let height = rows * (imageHeight + captionHeight + margin) + margin + titleHeight
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        throw InspectError.message("Cannot create contact sheet context")
    }
    context.setFillColor(CGColor(gray: 0.07, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: width, height: height))
    label(title, x: CGFloat(margin), y: CGFloat(height - 34), size: 20, context: context)
    for (index, entry) in frames.enumerated() {
        let x = CGFloat(margin + (index % columns) * (cellWidth + margin))
        let y = CGFloat(height - titleHeight - margin - imageHeight - (index / columns) * (imageHeight + captionHeight + margin))
        context.setFillColor(CGColor(gray: 0, alpha: 1))
        context.fill(CGRect(x: x, y: y, width: CGFloat(cellWidth), height: CGFloat(imageHeight)))
        let scale = min(CGFloat(cellWidth) / CGFloat(entry.1.width), CGFloat(imageHeight) / CGFloat(entry.1.height))
        let frameWidth = CGFloat(entry.1.width) * scale, frameHeight = CGFloat(entry.1.height) * scale
        context.interpolationQuality = .high
        context.draw(entry.1, in: CGRect(x: x + (CGFloat(cellWidth) - frameWidth) / 2,
                                        y: y + (CGFloat(imageHeight) - frameHeight) / 2,
                                        width: frameWidth, height: frameHeight))
        label(String(format: "%02d · %.3fs", index + 1, entry.0), x: x + 4, y: y - 24, size: 16, context: context)
    }
    guard let image = context.makeImage() else { throw InspectError.message("Cannot render contact sheet") }
    try writePNG(image, to: output)
}

func decode(_ asset: AVAsset, tracks: [AVAssetTrack]) throws -> [[String: Any]] {
    var results: [[String: Any]] = []
    for track in tracks {
        let reader = try AVAssetReader(asset: asset)
        let settings: [String: Any]
        if track.mediaType == .video {
            settings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        } else if track.mediaType == .audio {
            settings = [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16,
                        AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        } else { continue }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { throw InspectError.message("Cannot decode track \(track.trackID)") }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? InspectError.message("Decode did not start") }
        var samples = 0, previous = -Double.infinity, monotonic = true, last = 0.0
        while let sample = output.copyNextSampleBuffer() {
            let timestamp = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            if timestamp < previous { monotonic = false }
            previous = timestamp; last = timestamp; samples += 1
        }
        guard reader.status == .completed else { throw reader.error ?? InspectError.message("Decode incomplete") }
        results.append(["type": track.mediaType.rawValue, "sampleBuffers": samples,
                        "lastPresentationSeconds": last, "timestampsMonotonic": monotonic, "status": "completed"])
    }
    return results
}

do {
    let args = Array(CommandLine.arguments.dropFirst())
    guard args.count >= 2 else { throw InspectError.message("Usage: swift inspect_video.swift INPUT.mp4 OUTPUT_DIR [--times 0,5,10] [--decode]") }
    let input = URL(fileURLWithPath: args[0]), output = URL(fileURLWithPath: args[1], isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let asset = AVURLAsset(url: input)
    let duration = try await asset.load(.duration).seconds
    guard duration.isFinite && duration > 0 else { throw InspectError.message("Input has no valid duration") }
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    let audioTracks = try await asset.loadTracks(withMediaType: .audio)
    guard !videoTracks.isEmpty else { throw InspectError.message("Input has no video track") }
    var metadata: [String: Any] = ["input": input.path, "durationSeconds": duration,
        "fileBytes": (try input.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? 0,
        "videoTrackCount": videoTracks.count, "audioTrackCount": audioTracks.count,
        "playable": try await asset.load(.isPlayable), "exportable": try await asset.load(.isExportable)]
    var trackRecords: [[String: Any]] = []
    for track in videoTracks + audioTracks {
        let (naturalSize, transform, fps, rate, range, formats) = try await track.load(
            .naturalSize, .preferredTransform, .nominalFrameRate, .estimatedDataRate, .timeRange, .formatDescriptions)
        let size = naturalSize.applying(transform)
        trackRecords.append(["id": track.trackID, "type": track.mediaType.rawValue,
                "width": abs(size.width), "height": abs(size.height), "fps": fps,
                "estimatedDataRate": rate, "durationSeconds": range.duration.seconds,
                "codecs": formats.map { fourCC(CMFormatDescriptionGetMediaSubType($0)) }])
    }
    metadata["tracks"] = trackRecords
    var times = (0..<12).map { min(duration - 0.05, Double($0) * duration / 12 + 0.5) }
    if let index = args.firstIndex(of: "--times"), index + 1 < args.count {
        times = args[index + 1].split(separator: ",").compactMap { Double($0) }
    }
    guard !times.isEmpty && times.allSatisfy({ $0 >= 0 && $0 < duration }) else {
        throw InspectError.message("Frame times must be >= 0 and < duration")
    }
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.requestedTimeToleranceBefore = .zero
    generator.requestedTimeToleranceAfter = .zero
    var frames: [(Double, CGImage)] = [], frameRecords: [[String: Any]] = []
    for (index, time) in times.enumerated() {
        let (image, actual) = try await generator.image(at: CMTime(seconds: time, preferredTimescale: 60000))
        let name = String(format: "frame-%02d-%07.3fs.png", index + 1, time)
        try writePNG(image, to: output.appendingPathComponent(name))
        frames.append((actual.seconds, image))
        frameRecords.append(["requestedSeconds": time, "actualSeconds": actual.seconds,
                             "path": name, "width": image.width, "height": image.height])
    }
    metadata["frames"] = frameRecords
    try contactSheet(frames, output: output.appendingPathComponent("contact-sheet.png"), title: input.lastPathComponent)
    if args.contains("--decode") { metadata["decode"] = try decode(asset, tracks: videoTracks + audioTracks) }
    let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
    try json.write(to: output.appendingPathComponent("metadata.json"))
    print(String(data: json, encoding: .utf8)!)
} catch {
    fputs("Video inspection failed: \(error)\n", stderr)
    exit(1)
}
