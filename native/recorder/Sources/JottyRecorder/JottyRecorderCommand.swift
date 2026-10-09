import AVFoundation
import CoreGraphics
import Darwin
import Foundation

@main
struct JottyRecorderCommand {
  static func main() async {
    signal(SIGPIPE, SIG_IGN)

    if Array(CommandLine.arguments.dropFirst()) == ["--list-microphones"] {
      do {
        try writeMicrophones()
        return
      } catch {
        writeError("Error: \(error.localizedDescription)")
        exit(EXIT_FAILURE)
      }
    }

    guard let arguments = RecorderArguments.parse(Array(CommandLine.arguments.dropFirst())) else {
      writeError("Usage: jotty-recorder [--live [--microphone-device-id ID]] OUTPUT_DIRECTORY")
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
        microphoneDeviceID: arguments.microphoneDeviceID,
        onFailure: { terminationWaiter.fail($0) }
      )
      try await recorder.start()

      do {
        try packetWriter.writeReady()
      } catch {
        try await recorder.stop()
        throw error
      }

      writeError("Recording system audio and microphone. Press Ctrl-C to stop.")

      do {
        try await terminationWaiter.wait()
      } catch {
        try? await recorder.stop()
        throw error
      }

      writeError("Stopping recording...")
      try await recorder.stop()
      writeError("Saved system.m4a, microphone.m4a, microphone-aec.wav, and audio.m4a")
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
      guard let executableURL = Bundle.main.executableURL else {
        throw AECError.executableURLUnavailable
      }

      let libraryURL = DynamicAECProcessor.libraryURL(adjacentTo: executableURL)
      return AECCoordinator(
        processor: try DynamicAECProcessor(libraryPath: libraryURL.path),
        artifact: try WaveFileWriter(outputURL: paths.aecMicrophoneAudio),
        output: LiveAudioMixer(
          packetWriter: packetWriter,
          playbackWriter: try M4APCMWriter(outputURL: paths.playbackAudio)
        )
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

  private static func writeMicrophones() throws {
    let devices = AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone, .external],
      mediaType: .audio,
      position: .unspecified
    ).devices
    let microphones = devices.map { MicrophoneDevice(id: $0.uniqueID, name: $0.localizedName) }
    let data = try JSONEncoder().encode(microphones)
    FileHandle.standardOutput.write(data)
    FileHandle.standardOutput.write(Data("\n".utf8))
  }

  private static func writeError(_ message: String) {
    let data = Data("\(message)\n".utf8)

    data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      _ = Darwin.write(STDERR_FILENO, baseAddress, bytes.count)
    }
  }
}

private struct MicrophoneDevice: Encodable {
  let id: String
  let name: String
}

enum AECError: Swift.Error, LocalizedError {
  case executableURLUnavailable

  var errorDescription: String? {
    "Cannot locate the recorder executable"
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
