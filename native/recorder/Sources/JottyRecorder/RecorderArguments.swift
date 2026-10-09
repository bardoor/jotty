struct RecorderArguments: Equatable {
  enum Mode: Equatable {
    case archive
    case live
  }

  let outputDirectory: String
  let mode: Mode
  let microphoneDeviceID: String?

  static func parse(_ arguments: [String]) -> RecorderArguments? {
    if arguments.count == 1 {
      return RecorderArguments(outputDirectory: arguments[0], mode: .archive, microphoneDeviceID: nil)
    }

    if arguments.count == 2, arguments[0] == "--live" {
      return RecorderArguments(outputDirectory: arguments[1], mode: .live, microphoneDeviceID: nil)
    }

    if arguments.count == 4,
       arguments[0] == "--live",
       arguments[1] == "--microphone-device-id",
       !arguments[2].isEmpty
    {
      return RecorderArguments(
        outputDirectory: arguments[3],
        mode: .live,
        microphoneDeviceID: arguments[2]
      )
    }

    return nil
  }
}
