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

struct AECQualityCoordinatorTests {
  @Test
  func holdsCaptureUntilRenderTimelineCatchesUp() throws {
    let processor = RecordingAECProcessor()
    let writer = RecordingPCMWriter()
    let coordinator = AECQualityCoordinator(processor: processor, writer: writer)
    let render = pcm(Array(repeating: 1_000, count: 160))
    let capture = pcm(Array(repeating: 2_000, count: 160))

    try coordinator.append(capture, source: .microphone, presentationTime: .zero)
    #expect(processor.events.isEmpty)

    try coordinator.append(render, source: .system, presentationTime: .zero)

    #expect(
      processor.events == [
        .render(render),
        .capture(capture, delayMilliseconds: 0),
      ]
    )
    #expect(writer.chunks == [capture])
  }

  @Test
  func preservesPartialInputUntilACompleteFrameArrives() throws {
    let processor = RecordingAECProcessor()
    let writer = RecordingPCMWriter()
    let coordinator = AECQualityCoordinator(processor: processor, writer: writer)
    let halfRender = pcm(Array(repeating: 1_000, count: 80))
    let halfCapture = pcm(Array(repeating: 2_000, count: 80))

    try coordinator.append(halfRender, source: .system, presentationTime: .zero)
    try coordinator.append(halfCapture, source: .microphone, presentationTime: .zero)
    try coordinator.append(halfRender, source: .system, presentationTime: milliseconds(5))
    #expect(processor.events == [.render(halfRender + halfRender)])

    try coordinator.append(halfCapture, source: .microphone, presentationTime: milliseconds(5))

    #expect(processor.events.count == 2)
    #expect(writer.chunks.count == 1)
  }

  @Test
  func processesRenderAheadOfMatchingCapture() throws {
    let processor = RecordingAECProcessor()
    let writer = RecordingPCMWriter()
    let coordinator = AECQualityCoordinator(processor: processor, writer: writer)
    let render = pcm(Array(repeating: 1_000, count: 160))
    let capture = pcm(Array(repeating: 2_000, count: 160))
    let time = milliseconds(20)

    try coordinator.append(render, source: .system, presentationTime: time)
    try coordinator.append(capture, source: .microphone, presentationTime: time)

    #expect(
      processor.events == [
        .render(render),
        .capture(capture, delayMilliseconds: 0),
      ]
    )
  }

  @Test
  func finishesDiagnosticWriterAfterBothSourcesFinish() throws {
    let processor = RecordingAECProcessor()
    let writer = RecordingPCMWriter()
    let coordinator = AECQualityCoordinator(processor: processor, writer: writer)

    try coordinator.finish(source: .system)
    #expect(writer.finishCount == 0)

    try coordinator.finish(source: .microphone)
    try coordinator.finish(source: .microphone)

    #expect(writer.finishCount == 1)
  }
}

private func pcm(_ samples: [Int16]) -> Data {
  samples.withUnsafeBytes { Data($0) }
}

private func milliseconds(_ value: Int64) -> CMTime {
  CMTime(value: value, timescale: 1_000)
}
