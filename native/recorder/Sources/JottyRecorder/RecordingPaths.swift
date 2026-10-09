import Foundation

struct RecordingPaths {
  enum Error: Swift.Error, Equatable, LocalizedError {
    case outputDirectoryDoesNotExist
    case outputFileAlreadyExists

    var errorDescription: String? {
      switch self {
      case .outputDirectoryDoesNotExist:
        "Output directory does not exist"
      case .outputFileAlreadyExists:
        "system.m4a, microphone.m4a, or audio.m4a already exists"
      }
    }
  }

  let systemAudio: URL
  let microphoneAudio: URL
  let aecMicrophoneAudio: URL
  let playbackAudio: URL

  init(directoryPath: String) throws {
    var isDirectory: ObjCBool = false
    let directoryExists = FileManager.default.fileExists(
      atPath: directoryPath,
      isDirectory: &isDirectory
    )

    guard directoryExists, isDirectory.boolValue else {
      throw Error.outputDirectoryDoesNotExist
    }

    let directory = URL(filePath: directoryPath, directoryHint: .isDirectory)
    let systemAudio = directory.appending(path: "system.m4a")
    let microphoneAudio = directory.appending(path: "microphone.m4a")
    let playbackAudio = directory.appending(path: "audio.m4a")

    guard !FileManager.default.fileExists(atPath: systemAudio.path),
      !FileManager.default.fileExists(atPath: microphoneAudio.path),
      !FileManager.default.fileExists(atPath: playbackAudio.path)
    else {
      throw Error.outputFileAlreadyExists
    }

    self.systemAudio = systemAudio
    self.microphoneAudio = microphoneAudio
    aecMicrophoneAudio = directory.appending(path: "microphone-aec.wav")
    self.playbackAudio = playbackAudio
  }
}
