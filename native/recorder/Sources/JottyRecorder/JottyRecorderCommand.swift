import AVFoundation
import CoreGraphics
import Darwin
import Foundation

final class InterruptWaiter: @unchecked Sendable {
  private var source: DispatchSourceSignal?

  func wait() async {
    await withCheckedContinuation { continuation in
      signal(SIGINT, SIG_IGN)

      let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .main)
      source.setEventHandler { [weak self] in
        self?.source?.cancel()
        self?.source = nil
        continuation.resume()
      }
      self.source = source
      source.resume()
    }
  }
}

@main
struct JottyRecorderCommand {
  static func main() async {
    guard CommandLine.arguments.count == 2 else {
      writeError("Usage: jotty-recorder OUTPUT_DIRECTORY")
      exit(EX_USAGE)
    }

    do {
      let paths = try RecordingPaths(directoryPath: CommandLine.arguments[1])
      try await ensurePermissions()

      let recorder = Recorder(paths: paths)
      try await recorder.start()
      writeError("Recording system audio and default microphone. Press Ctrl-C to stop.")

      await InterruptWaiter().wait()

      writeError("Stopping recording...")
      try await recorder.stop()
      writeError("Saved system.m4a and microphone.m4a")
    } catch {
      writeError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
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
    FileHandle.standardError.write(Data("\(message)\n".utf8))
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
