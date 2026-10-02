import AVFoundation
import Foundation
import Testing

@testable import JottyRecorder

struct WaveFileWriterTests {
  @Test
  func writesMono16KHzInt16WaveFile() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outputURL = directory.appending(path: "microphone-aec.wav")
    let writer = try WaveFileWriter(outputURL: outputURL)

    try writer.append(pcm(Array(repeating: 1_000, count: 160)))
    try writer.finish()

    let file = try AVAudioFile(forReading: outputURL)
    #expect(file.fileFormat.sampleRate == 16_000)
    #expect(file.fileFormat.channelCount == 1)
    #expect(file.length == 160)
  }
}

private func pcm(_ samples: [Int16]) -> Data {
  samples.withUnsafeBytes { Data($0) }
}
