import Foundation
import Testing

@testable import JottyRecorder

struct RecordingPathsTests {
  @Test
  func createsExpectedTrackURLsInExistingDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let paths = try RecordingPaths(directoryPath: directory.path)

    #expect(paths.systemAudio == directory.appending(path: "system.m4a"))
    #expect(paths.microphoneAudio == directory.appending(path: "microphone.m4a"))
  }

  @Test
  func rejectsMissingDirectory() {
    let path = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
      .path

    #expect(throws: RecordingPaths.Error.outputDirectoryDoesNotExist) {
      try RecordingPaths(directoryPath: path)
    }
  }

  @Test
  func missingDirectoryErrorExplainsTheProblem() {
    #expect(
      RecordingPaths.Error.outputDirectoryDoesNotExist.errorDescription
        == "Output directory does not exist"
    )
  }

  @Test
  func refusesToOverwriteExistingTrack() throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }
    FileManager.default.createFile(
      atPath: directory.appending(path: "system.m4a").path,
      contents: Data()
    )

    #expect(throws: RecordingPaths.Error.outputFileAlreadyExists) {
      try RecordingPaths(directoryPath: directory.path)
    }
  }
}
