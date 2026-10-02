import AVFoundation
import CoreGraphics
import Darwin
import Foundation

@main
struct JottyRecorderCommand {
  static func main() async {
    signal(SIGPIPE, SIG_IGN)

    guard let arguments = arguments() else {
      writeError("Usage: jotty-recorder [--live] OUTPUT_DIRECTORY")
      exit(EX_USAGE)
    }

    do {
      let paths = try RecordingPaths(directoryPath: arguments.outputDirectory)
      try await ensurePermissions()

      let terminationWaiter = TerminationWaiter()
      let packetWriter = PacketWriter(output: .standardOutput)
      let recorder = Recorder(
        paths: paths,
        liveOutput: arguments.live ? packetWriter : nil,
        onFailure: { terminationWaiter.fail($0) }
      )
      try await recorder.start()

      do {
        try packetWriter.writeReady()
      } catch {
        try await recorder.stop()
        throw error
      }

      writeError("Recording system audio and default microphone. Press Ctrl-C to stop.")

      do {
        try await terminationWaiter.wait()
      } catch {
        try? await recorder.stop()
        throw error
      }

      writeError("Stopping recording...")
      try await recorder.stop()
      writeError("Saved system.m4a and microphone.m4a")
    } catch {
      writeError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static func arguments() -> (outputDirectory: String, live: Bool)? {
    switch CommandLine.arguments.dropFirst() {
    case let arguments where arguments.count == 1:
      return (arguments[arguments.startIndex], false)
    case let arguments where arguments.count == 2 && arguments.first == "--live":
      return (arguments[arguments.index(after: arguments.startIndex)], true)
    default:
      return nil
    }
  }

  private static func ensurePermissions() async throws {
    if !CGPreflightScreenCaptureAccess() {
      writeError("Grant Screen & System Audio Recording permission when prompted.")

      guard CGRequestScreenCaptureAccess() else {
        throw PermissionError.screenCaptureDenied
      }

      throw PermissionError.screenCaptureRelaunchRequired
    }

    let microphoneAccess = await AVCaptureDevice.requestAccess(for: .audio)

    guard microphoneAccess else {
      throw PermissionError.microphoneDenied
    }
  }

  private static func writeError(_ message: String) {
    let data = Data("\(message)\n".utf8)

    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      _ = Darwin.write(STDERR_FILENO, baseAddress, bytes.count)
    }
  }
}

enum PermissionError: Swift.Error, LocalizedError {
  case screenCaptureDenied
  case screenCaptureRelaunchRequired
  case microphoneDenied

  var errorDescription: String? {
    switch self {
    case .screenCaptureDenied:
      "Screen & System Audio Recording permission was denied"
    case .screenCaptureRelaunchRequired:
      "Screen recording permission was granted. Fully quit and reopen the terminal, then run Jotty Recorder again."
    case .microphoneDenied:
      "Microphone permission was denied"
    }
  }
}
