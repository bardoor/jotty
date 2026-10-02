import AVFoundation
import CoreGraphics
import Darwin
import Foundation

@main
struct JottyRecorderCommand {
  static func main() async {
    signal(SIGPIPE, SIG_IGN)

    guard let arguments = RecorderArguments.parse(Array(CommandLine.arguments.dropFirst())) else {
      writeError("Usage: jotty-recorder [--live | --aec-spike] OUTPUT_DIRECTORY")
      exit(EX_USAGE)
    }

    do {
      let paths = try RecordingPaths(directoryPath: arguments.outputDirectory)
      try await ensurePermissions()

      let terminationWaiter = TerminationWaiter()
      let packetWriter = PacketWriter(output: .standardOutput)
      let liveMixer = try liveMixer(for: arguments.mode, paths: paths, packetWriter: packetWriter)
      let recorder = Recorder(
        paths: paths,
        liveMixer: liveMixer,
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

      if arguments.mode == .aecSpike {
        writeError("Saved microphone-aec.wav")
      }
    } catch {
      writeError("Error: \(error.localizedDescription)")
      exit(EXIT_FAILURE)
    }
  }

  private static func liveMixer(
    for mode: RecorderArguments.Mode,
    paths: RecordingPaths,
    packetWriter: PacketWriting
  ) throws -> LiveAudioMixing? {
    switch mode {
    case .archive:
      return nil
    case .live:
      return LiveAudioMixer(packetWriter: packetWriter)
    case .aecSpike:
      guard let libraryPath = ProcessInfo.processInfo.environment["JOTTY_AEC_LIBRARY_PATH"] else {
        throw AECSpikeError.missingLibraryPath
      }

      return AECQualityCoordinator(
        processor: try DynamicAECProcessor(libraryPath: libraryPath),
        writer: try WaveFileWriter(outputURL: paths.aecMicrophoneAudio)
      )
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

enum AECSpikeError: Swift.Error, LocalizedError {
  case missingLibraryPath

  var errorDescription: String? {
    "JOTTY_AEC_LIBRARY_PATH is required for --aec-spike"
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
