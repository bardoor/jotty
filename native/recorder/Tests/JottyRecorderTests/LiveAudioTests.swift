import AVFoundation
import CoreMedia
import Foundation
import Testing

@testable import JottyRecorder

private enum TestFailure: Swift.Error {
  case expected
}

private final class FailingConverter: PCMConverting, @unchecked Sendable {
  func convert(_ sampleBuffer: CMSampleBuffer) throws -> Data {
    throw TestFailure.expected
  }

  func finish() throws -> Data {
    Data()
  }
}

private final class SlowConverter: PCMConverting, @unchecked Sendable {
  func convert(_ sampleBuffer: CMSampleBuffer) throws -> Data {
    Thread.sleep(forTimeInterval: 0.01)
    return Data([0x00, 0x00])
  }

  func finish() throws -> Data {
    Data()
  }
}

private final class RecordingPacketWriter: PacketWriting, @unchecked Sendable {
  enum Event: Equatable {
    case ready
    case pcm(Data)
    case failure(LiveAudioSource, LiveAudioFailureReason)
  }

  private let lock = NSLock()
  private var recordedEvents: [Event] = []

  var events: [Event] {
    lock.lock()
    defer { lock.unlock() }
    return recordedEvents
  }

  func writeReady() throws {
    append(.ready)
  }

  func writePCM(_ pcm: Data) throws {
    append(.pcm(pcm))
  }

  func writeFailure(source: LiveAudioSource, reason: LiveAudioFailureReason) throws {
    append(.failure(source, reason))
  }

  private func append(_ event: Event) {
    lock.lock()
    recordedEvents.append(event)
    lock.unlock()
  }
}

private final class FailingPCMWriter: PacketWriting, @unchecked Sendable {
  private let recorder = RecordingPacketWriter()

  var events: [RecordingPacketWriter.Event] {
    recorder.events
  }

  func writeReady() throws {
    try recorder.writeReady()
  }

  func writePCM(_ pcm: Data) throws {
    throw TestFailure.expected
  }

  func writeFailure(source: LiveAudioSource, reason: LiveAudioFailureReason) throws {
    try recorder.writeFailure(source: source, reason: reason)
  }
}

private final class FixedConverter: PCMConverting, @unchecked Sendable {
  func convert(_ sampleBuffer: CMSampleBuffer) throws -> Data {
    Data([0x00, 0x00])
  }

  func finish() throws -> Data {
    Data()
  }
}

private final class FailingPCMArtifact: PCMWriting, @unchecked Sendable {
  func append(_ pcm: Data) throws {
    throw TestFailure.expected
  }

  func finish() throws {}
}

private final class RecordingPCMArtifact: PCMWriting, @unchecked Sendable {
  private(set) var chunks: [Data] = []
  private(set) var finished = false

  func append(_ pcm: Data) throws {
    chunks.append(pcm)
  }

  func finish() throws {
    finished = true
  }
}

private final class RecordingLiveMixer: LiveAudioMixing, @unchecked Sendable {
  private(set) var presentationTimes: [CMTime] = []

  func append(_ pcm: Data, source: LiveAudioSource, presentationTime: CMTime) throws {
    presentationTimes.append(presentationTime)
  }

  func finish(source: LiveAudioSource) throws {}

  func fail(source: LiveAudioSource, reason: LiveAudioFailureReason) {}
}

struct LiveAudioTests {
  @Test
  func passesSourcePresentationTimeToRealtimeMixer() throws {
    let mixer = RecordingLiveMixer()
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FixedConverter(),
      mixer: mixer
    )
    let expectedTime = CMTime(value: 250, timescale: 1_000)

    emitter.process(try syntheticSampleBuffer(frameCount: 480, presentationTime: expectedTime))

    #expect(mixer.presentationTimes == [expectedTime])
  }

  @Test
  func mixesSystemAndMicrophonePCMIntoOneSaturatingStream() throws {
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)

    try mixer.append(pcm([1_000, 30_000]), source: .system, presentationTime: .zero)
    #expect(packetWriter.events.isEmpty)

    try mixer.append(pcm([2_000, 10_000]), source: .microphone, presentationTime: .zero)

    #expect(packetWriter.events == [.pcm(pcm([3_000, Int16.max]))])
  }

  @Test
  func fansOutTheExactEmittedPCMToPlaybackAndFinalizesIt() throws {
    let packetWriter = RecordingPacketWriter()
    let playbackWriter = RecordingPCMArtifact()
    let mixer = LiveAudioMixer(packetWriter: packetWriter, playbackWriter: playbackWriter)

    try mixer.append(pcm([30_000, -30_000]), source: .system, presentationTime: .zero)
    try mixer.append(pcm([10_000, -10_000]), source: .microphone, presentationTime: .zero)
    try mixer.finish(source: .system)
    try mixer.finish(source: .microphone)

    let expected = pcm([Int16.max, Int16.min])
    #expect(packetWriter.events == [.pcm(expected)])
    #expect(playbackWriter.chunks == [expected])
    #expect(playbackWriter.finished)
  }

  @Test
  func playbackFailureRemainsTerminalAtRecorderFinalization() throws {
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter, playbackWriter: FailingPCMArtifact())

    try mixer.append(pcm([1_000]), source: .system, presentationTime: .zero)
    #expect(throws: TestFailure.self) {
      try mixer.append(pcm([2_000]), source: .microphone, presentationTime: .zero)
    }
    #expect(packetWriter.events == [.pcm(pcm([3_000]))])
    #expect(throws: TestFailure.self) {
      try mixer.finalize()
    }
  }

  @Test
  func alignsMixedPCMByPresentationTime() throws {
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)

    try mixer.append(pcm([1_000, 1_000]), source: .system, presentationTime: .zero)
    try mixer.append(
      pcm([2_000]),
      source: .microphone,
      presentationTime: CMTime(value: 1, timescale: 16_000)
    )

    #expect(packetWriter.events == [.pcm(pcm([1_000])), .pcm(pcm([3_000]))])
  }

  @Test
  func flushesTheLongerSourceWithSilenceAfterBothSourcesFinish() throws {
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)

    try mixer.append(pcm([1_000, 2_000]), source: .system, presentationTime: .zero)
    try mixer.append(pcm([3_000]), source: .microphone, presentationTime: .zero)
    try mixer.finish(source: .microphone)
    try mixer.finish(source: .system)

    #expect(packetWriter.events == [.pcm(pcm([4_000])), .pcm(pcm([2_000]))])
  }

  @Test
  func convertsSyntheticAudioToMono16KHzSigned16BitPCM() throws {
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)

    let converter = CanonicalPCMConverter()
    let firstPCM = try converter.convert(sampleBuffer)
    let secondPCM = try converter.convert(sampleBuffer)
    let finalPCM = try converter.finish()

    let format = CanonicalPCMConverter.canonicalFormat()
    #expect(format.sampleRate == 16_000)
    #expect(format.channelCount == 1)
    #expect(format.commonFormat == .pcmFormatInt16)
    #expect(format.isInterleaved)
    #expect(format.streamDescription.pointee.mFormatFlags & kAudioFormatFlagIsBigEndian == 0)
    #expect(!firstPCM.isEmpty)
    #expect(firstPCM.count.isMultiple(of: MemoryLayout<Int16>.size))
    #expect(!secondPCM.isEmpty)
    #expect(secondPCM.count.isMultiple(of: MemoryLayout<Int16>.size))
    #expect(firstPCM.count + secondPCM.count + finalPCM.count == 320 * MemoryLayout<Int16>.size)
  }

  @Test
  func conversionFailureDisablesSharedRealtimeOutputAndEmitsOneFailure() throws {
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FailingConverter(),
      mixer: mixer
    )
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)

    emitter.process(sampleBuffer)
    emitter.finish()
    emitter.process(sampleBuffer)
    emitter.finish()

    #expect(packetWriter.events == [.failure(.system, .conversion)])
  }

  @Test
  func slowConversionProcessesEverySequentialSample() throws {
    let converter = SlowConverter()
    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)
    let emitter = LiveAudioEmitter(
      source: .microphone,
      converter: converter,
      mixer: mixer
    )
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)
    try mixer.append(Data(repeating: 0, count: 8), source: .system, presentationTime: .zero)

    for _ in 1 ... 4 {
      emitter.process(sampleBuffer)
    }
    emitter.finish()

    #expect(packetWriter.events == Array(repeating: .pcm(Data([0x00, 0x00])), count: 4))
  }

  @Test
  func packetOutputFailureDisablesSharedRealtimeOutputAndEmitsOneFailure() throws {
    let packetWriter = FailingPCMWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)
    let microphoneEmitter = LiveAudioEmitter(
      source: .microphone,
      converter: FixedConverter(),
      mixer: mixer
    )
    let systemEmitter = LiveAudioEmitter(
      source: .system,
      converter: FixedConverter(),
      mixer: mixer
    )
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)

    microphoneEmitter.process(sampleBuffer)
    systemEmitter.process(sampleBuffer)
    systemEmitter.finish()
    systemEmitter.process(sampleBuffer)
    systemEmitter.finish()

    #expect(packetWriter.events == [.failure(.system, .packetOutput)])
  }

  @Test
  func liveConversionFailureDoesNotPreventArchivalFinalization() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let packetWriter = RecordingPacketWriter()
    let mixer = LiveAudioMixer(packetWriter: packetWriter)
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FailingConverter(),
      mixer: mixer
    )
    let outputURL = directory.appending(path: "system.m4a")
    let output = AudioStreamOutput(
      label: "LiveAudioTests.archival-output",
      outputURL: outputURL,
      liveEmitter: emitter
    )

    output.append(try syntheticSampleBuffer(frameCount: 480))
    try await output.finish()

    let attributes = try FileManager.default.attributesOfItem(atPath: outputURL.path)
    let size = try #require(attributes[.size] as? NSNumber)
    #expect(size.intValue > 0)
    #expect(packetWriter.events == [.failure(.system, .conversion)])
  }
}

private func syntheticSampleBuffer(
  frameCount: AVAudioFrameCount,
  presentationTime: CMTime = .zero
) throws -> CMSampleBuffer {
  let format = AVAudioFormat(
    commonFormat: .pcmFormatInt16,
    sampleRate: 48_000,
    channels: 1,
    interleaved: true
  )!

  var formatDescription: CMAudioFormatDescription?
  let formatStatus = CMAudioFormatDescriptionCreate(
    allocator: kCFAllocatorDefault,
    asbd: format.streamDescription,
    layoutSize: 0,
    layout: nil,
    magicCookieSize: 0,
    magicCookie: nil,
    extensions: nil,
    formatDescriptionOut: &formatDescription
  )
  guard formatStatus == noErr, let formatDescription else {
    throw TestFailure.expected
  }

  let byteCount = Int(frameCount) * MemoryLayout<Int16>.size
  var blockBuffer: CMBlockBuffer?
  let blockStatus = CMBlockBufferCreateWithMemoryBlock(
    allocator: kCFAllocatorDefault,
    memoryBlock: nil,
    blockLength: byteCount,
    blockAllocator: kCFAllocatorDefault,
    customBlockSource: nil,
    offsetToData: 0,
    dataLength: byteCount,
    flags: 0,
    blockBufferOut: &blockBuffer
  )
  guard blockStatus == noErr, let blockBuffer else {
    throw TestFailure.expected
  }

  var samples = (0 ..< Int(frameCount)).map { Int16(($0 % 32) * 512) }
  let replaceStatus = samples.withUnsafeMutableBytes { bytes in
    CMBlockBufferReplaceDataBytes(with: bytes.baseAddress!, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)
  }
  guard replaceStatus == noErr else {
    throw TestFailure.expected
  }

  var timing = CMSampleTimingInfo(
    duration: CMTime(value: 1, timescale: 48_000),
    presentationTimeStamp: presentationTime,
    decodeTimeStamp: .invalid
  )
  var sampleSize = MemoryLayout<Int16>.size
  var sampleBuffer: CMSampleBuffer?
  let sampleStatus = CMSampleBufferCreateReady(
    allocator: kCFAllocatorDefault,
    dataBuffer: blockBuffer,
    formatDescription: formatDescription,
    sampleCount: CMItemCount(frameCount),
    sampleTimingEntryCount: 1,
    sampleTimingArray: &timing,
    sampleSizeEntryCount: 1,
    sampleSizeArray: &sampleSize,
    sampleBufferOut: &sampleBuffer
  )
  guard sampleStatus == noErr, let sampleBuffer else {
    throw TestFailure.expected
  }

  return sampleBuffer
}

private func pcm(_ samples: [Int16]) -> Data {
  samples.withUnsafeBytes { Data($0) }
}
