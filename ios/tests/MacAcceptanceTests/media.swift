import Foundation
import AppKit
import ImageIO
import AVFoundation
import UniformTypeIdentifiers

/// Small deterministic media, only inside an existing isolated acceptance root.
@main struct AcceptanceMediaFixture {
    static func main() async throws {
        guard CommandLine.arguments.count == 2,
              let physical = realpath(CommandLine.arguments[1], nil) else { fatalError("Existing test root required") }
        defer { free(physical) }
        let root = URL(fileURLWithPath: String(cString: physical))
        guard root.path.hasPrefix("/private/tmp/OpenCommander-MacUITest-Acceptance-20261018-"),
              root.deletingLastPathComponent().path == "/private/tmp" else { fatalError("Not a test root") }
        let fm = FileManager.default, directory = root.appendingPathComponent("MediaExtra")
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        let audio = directory.appendingPathComponent("Synthetic.wav")
        if !fm.fileExists(atPath: audio.path) {
            let count = 44100 * 6
            var wave = Data()
            func tag(_ text: String) { wave.append(contentsOf: text.utf8) }
            func u16(_ number: UInt16) { var value = number.littleEndian; withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) } }
            func u32(_ number: UInt32) { var value = number.littleEndian; withUnsafeBytes(of: &value) { wave.append(contentsOf: $0) } }
            tag("RIFF"); u32(UInt32(36 + count * 2)); tag("WAVEfmt "); u32(16)
            u16(1); u16(1); u32(44100); u32(88200); u16(2); u16(16); tag("data"); u32(UInt32(count * 2))
            for sample in 0..<count { u16(UInt16(bitPattern: Int16(sin(Double(sample) * 2 * .pi * 440 / 44100) * 1600))) }
            try wave.write(to: audio, options: .withoutOverwriting)
        }
        let gif = directory.appendingPathComponent("TwoFrames.gif")
        if !fm.fileExists(atPath: gif.path) {
            guard let output = CGImageDestinationCreateWithURL(gif as CFURL, UTType.gif.identifier as CFString, 2, nil) else { fatalError("GIF writer") }
            CGImageDestinationSetProperties(output, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for color in [NSColor.systemBlue, .systemOrange] {
                let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 160, pixelsHigh: 96,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
                color.setFill(); NSBezierPath(rect: NSRect(x: 0, y: 0, width: 160, height: 96)).fill()
                NSGraphicsContext.restoreGraphicsState()
                CGImageDestinationAddImage(output, bitmap.cgImage!,
                    [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.5]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(output), let source = CGImageSourceCreateWithURL(gif as CFURL, nil),
                  CGImageSourceGetCount(source) == 2 else { fatalError("GIF frame validation") }
        }
        let movie = directory.appendingPathComponent("Synthetic.mp4")
        if !fm.fileExists(atPath: movie.path) {
            let writer = try AVAssetWriter(outputURL: movie, fileType: .mp4)
            let input = AVAssetWriterInput(mediaType: .video, outputSettings:
                [AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: 160, AVVideoHeightKey: 96])
            let adapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
                sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                    kCVPixelBufferWidthKey as String: 160, kCVPixelBufferHeightKey as String: 96])
            writer.add(input)
            guard writer.startWriting() else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
            writer.startSession(atSourceTime: .zero)
            let deadline = Date().addingTimeInterval(15)
            for frame in 0..<60 {
                while !input.isReadyForMoreMediaData {
                    guard writer.status == .writing, Date() < deadline else {
                        writer.cancelWriting(); throw CocoaError(.fileWriteUnknown)
                    }
                    try await Task.sleep(nanoseconds: 1_000_000)
                }
                var pixel: CVPixelBuffer?
                guard CVPixelBufferCreate(nil, 160, 96, kCVPixelFormatType_32ARGB, nil, &pixel) == kCVReturnSuccess,
                      let pixel else { fatalError("pixel buffer") }
                CVPixelBufferLockBaseAddress(pixel, [])
                let base = CVPixelBufferGetBaseAddress(pixel)!.assumingMemoryBound(to: UInt8.self)
                let stride = CVPixelBufferGetBytesPerRow(pixel)
                for y in 0..<96 { for x in 0..<160 {
                    let index = y * stride + x * 4
                    base[index] = 255; base[index + 1] = frame < 30 ? 255 : 0
                    base[index + 2] = 0; base[index + 3] = frame < 30 ? 0 : 255
                } }
                CVPixelBufferUnlockBaseAddress(pixel, [])
                guard adapter.append(pixel, withPresentationTime: CMTime(value: Int64(frame), timescale: 10)) else {
                    throw writer.error ?? CocoaError(.fileWriteUnknown)
                }
            }
            input.markAsFinished()
            writer.finishWriting {}
            while writer.status == .writing {
                guard Date() < deadline else { writer.cancelWriting(); throw CocoaError(.fileWriteUnknown) }
                try await Task.sleep(nanoseconds: 10_000_000)
            }
            guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
        }
        for url in [audio, movie] {
            let duration = try await AVURLAsset(url: url).load(.duration).seconds
            guard duration > 5.8 && duration < 6.1 else { fatalError("Invalid media duration") }
        }
        guard let gifSource = CGImageSourceCreateWithURL(gif as CFURL, nil), CGImageSourceGetCount(gifSource) == 2 else {
            fatalError("Invalid existing GIF fixture")
        }
        print("PASS synthetic 6-second WAV/MP4 and independently validated two-frame GIF: \(directory.path)")
    }
}
