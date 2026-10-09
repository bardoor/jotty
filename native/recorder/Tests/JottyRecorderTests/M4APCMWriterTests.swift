import AVFoundation
import Foundation
import Testing

@testable import JottyRecorder

struct M4APCMWriterTests {
  @Test
  func writesCompressedPlayableMonoM4A() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let url = directory.appending(path: "audio.m4a")
    let writer = try M4APCMWriter(outputURL: url)
    let pcm = Array(repeating: Int16(1_000), count: 16_000).withUnsafeBytes { Data($0) }

    try writer.append(pcm)
    try writer.finish()

    let asset = AVURLAsset(url: url)
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
    let size = try #require(attributes[.size] as? NSNumber)
    #expect(tracks.count == 1)
    #expect(size.intValue > 0)
    #expect(size.intValue < pcm.count)
  }
}
