import CoreMedia
import Foundation
import Testing

@testable import JottyRecorder

private final class RecordingAECProcessor: AECProcessing, @unchecked Sendable {
  enum Event: Equatable {
    case render(Data)
    case capture(Data, delayMilliseconds: Int)
  }

  private(set) var events: [Event] = []

  func processRender(_ render: Data) throws {
    events.append(.render(render))
  }

  func processCapture(_ capture: Data, delayMilliseconds: Int) throws -> Data {
    events.append(.capture(capture, delayMilliseconds: delayMilliseconds))
    return capture
  }
}

private final class RecordingLiveAudioOutput: LiveAudioMixing, @unchecked Sendable {
  enum Event: Equatable {
    case append(Data, source: LiveAudioSource, presentationTime: CMTime)
    case finish(LiveAudioSource)
    case failure(LiveAudioSource, LiveAudioFailureReason)
  }

  private(set) var events: [Event] = []

  func append(_ pcm: Data, source: LiveAudioSource, presentationTime: CMTime) throws {
    events.append(.append(pcm, source: source, presentationTime: presentationTime))
  }

  func finish(source: LiveAudioSource) throws {
    events.append(.finish(source))
  }

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {
    events.append(.failure(source, reason))
  }
}

private final class RecordingPCMWriter: PCMWriting, @unchecked Sendable {
  private(set) var chunks: [Data] = []
  private(set) var finishCount = 0

  func append(_ pcm: Data) throws {
    chunks.append(pcm)
  }

  func finish() throws {
    finishCount += 1
  }
}

struct AECCoordinatorTests {
  @Test
  func sendsRenderAndCleanedCaptureToDownstreamTimeline() throws {
    let processor = RecordingAECProcessor()
    let output = RecordingLiveAudioOutput()
    let artifact = RecordingPCMWriter()
    let coordinator = AECCoordinator(processor: processor, artifact: artifact, output: output)
    let render = pcm(Array(repeating: 1_000, count: 160))
    let capture = pcm(Array(repeating: 2_000, count: 160))

    try coordinator.append(capture, source: .microphone, presentationTime: .zero)
    #expect(processor.events.isEmpty)
    #expect(output.events.isEmpty)

    try coordinator.append(render, source: .system, presentationTime: .zero)

    #expect(
      processor.events == [
        .render(render),
        .capture(capture, delayMilliseconds: 0),
      ]
    )
    #expect(
      output.events == [
        .append(render, source: .system, presentationTime: .zero),
        .append(capture, source: .microphone, presentationTime: .zero),
      ]
    )
    #expect(artifact.chunks == [capture])
  }

  @Test
  func dropsStartupCaptureThatPredatesTheFirstRenderReference() throws {
    let processor = RecordingAECProcessor()
    let output = RecordingLiveAudioOutput()
    let coordinator = AECCoordinator(processor: processor, artifact: RecordingPCMWriter(), output: output)
    let render = pcm(Array(repeating: 1_000, count: 160))
    let capture = pcm(Array(repeating: 2_000, count: 160))
    let renderTime = milliseconds(20)

    try coordinator.append(capture, source: .microphone, presentationTime: .zero)
    try coordinator.append(render, source: .system, presentationTime: renderTime)

    #expect(processor.events == [.render(render)])
    #expect(
      output.events == [
        .append(render, source: .system, presentationTime: renderTime)
      ]
    )
  }

  @Test
  func dropsCaptureTailWithoutAReference() throws {
    let processor = RecordingAECProcessor()
    let output = RecordingLiveAudioOutput()
    let artifact = RecordingPCMWriter()
    let coordinator = AECCoordinator(processor: processor, artifact: artifact, output: output)
    let render = pcm(Array(repeating: 1_000, count: 160))
    let capture = pcm(Array(repeating: 2_000, count: 160))

    try coordinator.append(render, source: .system, presentationTime: .zero)
    try coordinator.append(capture, source: .microphone, presentationTime: milliseconds(10))
    try coordinator.finish(source: .system)
    try coordinator.finish(source: .microphone)

    #expect(
      output.events == [
        .append(render, source: .system, presentationTime: .zero),
        .finish(.system),
        .finish(.microphone),
      ]
    )
    #expect(artifact.finishCount == 1)
  }

  @Test
  func forwardsFailureToDownstream() {
    let output = RecordingLiveAudioOutput()
    let artifact = RecordingPCMWriter()
    let coordinator = AECCoordinator(
      processor: RecordingAECProcessor(),
      artifact: artifact,
      output: output
    )

    coordinator.fail(source: .system, reason: .conversion)

    #expect(output.events == [.failure(.system, .conversion)])
    #expect(artifact.finishCount == 1)
  }
}

private func pcm(_ samples: [Int16]) -> Data {
  samples.withUnsafeBytes { Data($0) }
}

private func milliseconds(_ value: Int64) -> CMTime {
  CMTime(value: value, timescale: 1_000)
}
