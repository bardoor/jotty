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
    case pcm(Data, LiveAudioSource)
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

  func writePCM(_ pcm: Data, source: LiveAudioSource) throws {
    append(.pcm(pcm, source))
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

  func writePCM(_ pcm: Data, source: LiveAudioSource) throws {
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

struct LiveAudioTests {
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
  func conversionFailureDisablesOnlyThatSourceAndEmitsOneFailure() throws {
    let packetWriter = RecordingPacketWriter()
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FailingConverter(),
      packetWriter: packetWriter
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
    let emitter = LiveAudioEmitter(
      source: .microphone,
      converter: converter,
      packetWriter: packetWriter
    )
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)

    for _ in 1 ... 4 {
      emitter.process(sampleBuffer)
    }
    emitter.finish()

    #expect(packetWriter.events == Array(repeating: .pcm(Data([0x00, 0x00]), .microphone), count: 4))
  }

  @Test
  func packetOutputFailureDisablesOnlyThatSourceAndEmitsOneFailure() throws {
    let packetWriter = FailingPCMWriter()
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FixedConverter(),
      packetWriter: packetWriter
    )
    let sampleBuffer = try syntheticSampleBuffer(frameCount: 480)

    emitter.process(sampleBuffer)
    emitter.finish()
    emitter.process(sampleBuffer)
    emitter.finish()

    #expect(packetWriter.events == [.failure(.system, .packetOutput)])
  }

  @Test
  func liveConversionFailureDoesNotPreventArchivalFinalization() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
    defer { try? FileManager.default.removeItem(at: directory) }

    let packetWriter = RecordingPacketWriter()
    let emitter = LiveAudioEmitter(
      source: .system,
      converter: FailingConverter(),
      packetWriter: packetWriter
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

private func syntheticSampleBuffer(frameCount: AVAudioFrameCount) throws -> CMSampleBuffer {
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
    presentationTimeStamp: .zero,
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
