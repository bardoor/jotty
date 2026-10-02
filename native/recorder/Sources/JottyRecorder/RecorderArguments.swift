struct RecorderArguments: Equatable {
  enum Mode: Equatable {
    case archive
    case live
    case aecSpike
  }

  let outputDirectory: String
  let mode: Mode

  static func parse(_ arguments: [String]) -> RecorderArguments? {
    if arguments.count == 1 {
      return RecorderArguments(outputDirectory: arguments[0], mode: .archive)
    }

    guard arguments.count == 2 else {
      return nil
    }

    switch arguments[0] {
    case "--live":
      return RecorderArguments(outputDirectory: arguments[1], mode: .live)
    case "--aec-spike":
      return RecorderArguments(outputDirectory: arguments[1], mode: .aecSpike)
    default:
      return nil
    }
  }
}
