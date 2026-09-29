import AVFoundation
import CoreMedia
import Foundation

private final class ConverterInput: @unchecked Sendable {
  private let buffer: AVAudioPCMBuffer
  private var supplied = false

  init(buffer: AVAudioPCMBuffer) {
    self.buffer = buffer
  }

  func next(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
    if supplied {
      status.pointee = .noDataNow
      return nil
    }

    supplied = true
    status.pointee = .haveData
    return buffer
  }
}

protocol PCMConverting: Sendable {
  func convert(_ sampleBuffer: CMSampleBuffer) throws -> Data
  func finish() throws -> Data
}

final class CanonicalPCMConverter: PCMConverting, @unchecked Sendable {
  enum Error: Swift.Error {
    case missingFormat
    case unsupportedFormat
    case cannotCreateBuffer
    case cannotCopySamples(OSStatus)
    case cannotCreateConverter
    case conversionFailed(Swift.Error?)
    case emptyOutput
  }

  private let lock = NSLock()
  private var converter: AVAudioConverter?
  private var inputFormat: AVAudioFormat?
  private var outputCapacity: AVAudioFrameCount?

  static func canonicalFormat() -> AVAudioFormat {
    AVAudioFormat(
      commonFormat: .pcmFormatInt16,
      sampleRate: 16_000,
      channels: 1,
      interleaved: true
    )!
  }

  func convert(_ sampleBuffer: CMSampleBuffer) throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
          let streamDescription = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription),
          let sourceFormat = AVAudioFormat(streamDescription: streamDescription)
    else {
      throw Error.missingFormat
    }

    guard sourceFormat.channelCount > 0, sourceFormat.sampleRate > 0 else {
      throw Error.unsupportedFormat
    }

    let frameCount = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))
    guard frameCount > 0,
          let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: frameCount)
    else {
      throw Error.cannotCreateBuffer
    }

    sourceBuffer.frameLength = frameCount
    let copyStatus = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(frameCount),
      into: sourceBuffer.mutableAudioBufferList
    )
    guard copyStatus == noErr else {
      throw Error.cannotCopySamples(copyStatus)
    }

    let targetFormat = Self.canonicalFormat()

    let converter = try converter(from: sourceFormat, to: targetFormat)
    let ratio = targetFormat.sampleRate / sourceFormat.sampleRate
    let targetCapacity = AVAudioFrameCount(ceil(Double(frameCount) * ratio)) + 1
    guard let targetBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: targetCapacity) else {
      throw Error.cannotCreateBuffer
    }

    let input = ConverterInput(buffer: sourceBuffer)
    var conversionError: NSError?
    let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
      input.next(status: inputStatus)
    }

    guard status == .haveData || status == .inputRanDry, targetBuffer.frameLength > 0 else {
      throw Error.conversionFailed(conversionError)
    }

    let byteCount = Int(targetBuffer.frameLength) * Int(targetFormat.streamDescription.pointee.mBytesPerFrame)
    guard byteCount > 0 else {
      throw Error.emptyOutput
    }

    let audioBuffer = targetBuffer.audioBufferList.pointee.mBuffers
    guard let bytes = audioBuffer.mData else {
      throw Error.emptyOutput
    }

    outputCapacity = targetCapacity
    return Data(bytes: bytes, count: byteCount)
  }

  func finish() throws -> Data {
    lock.lock()
    defer { lock.unlock() }

    guard let converter, let outputCapacity else {
      return Data()
    }

    let targetFormat = Self.canonicalFormat()
    var pcm = Data()

    while true {
      guard let targetBuffer = AVAudioPCMBuffer(
        pcmFormat: targetFormat,
        frameCapacity: outputCapacity
      ) else {
        throw Error.cannotCreateBuffer
      }

      var conversionError: NSError?
      let status = converter.convert(to: targetBuffer, error: &conversionError) { _, inputStatus in
        inputStatus.pointee = .endOfStream
        return nil
      }

      switch status {
      case .haveData:
        pcm.append(try data(from: targetBuffer, format: targetFormat))
      case .endOfStream:
        return pcm
      case .inputRanDry, .error:
        throw Error.conversionFailed(conversionError)
      @unknown default:
        throw Error.conversionFailed(conversionError)
      }
    }
  }

  private func converter(from sourceFormat: AVAudioFormat, to targetFormat: AVAudioFormat) throws -> AVAudioConverter {
    if inputFormat == sourceFormat, let converter {
      return converter
    }

    guard let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
      throw Error.cannotCreateConverter
    }

    self.inputFormat = sourceFormat
    self.converter = converter
    return converter
  }

  private func data(from buffer: AVAudioPCMBuffer, format: AVAudioFormat) throws -> Data {
    let byteCount = Int(buffer.frameLength) * Int(format.streamDescription.pointee.mBytesPerFrame)
    guard byteCount > 0, let bytes = buffer.audioBufferList.pointee.mBuffers.mData else {
      throw Error.emptyOutput
    }

    return Data(bytes: bytes, count: byteCount)
  }
}

final class LiveAudioEmitter: @unchecked Sendable {
  private let source: LiveAudioSource
  private let converter: PCMConverting
  private let packetWriter: PacketWriting
  private let stateLock = NSLock()
  private var enabled = true

  init(
    source: LiveAudioSource,
    converter: PCMConverting,
    packetWriter: PacketWriting
  ) {
    self.source = source
    self.converter = converter
    self.packetWriter = packetWriter
  }

  func process(_ sampleBuffer: CMSampleBuffer) {
    guard liveEnabled() else {
      return
    }

    let pcm: Data
    do {
      pcm = try converter.convert(sampleBuffer)
    } catch {
      fail(.conversion)
      return
    }

    guard liveEnabled() else {
      return
    }

    do {
      try packetWriter.writePCM(pcm, source: source)
    } catch {
      fail(.packetOutput)
    }
  }

  func finish() {
    guard liveEnabled() else {
      return
    }

    let pcm: Data
    do {
      pcm = try converter.finish()
    } catch {
      fail(.conversion)
      return
    }

    guard !pcm.isEmpty else {
      return
    }

    do {
      try packetWriter.writePCM(pcm, source: source)
    } catch {
      fail(.packetOutput)
    }
  }

  private func liveEnabled() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }
    return enabled
  }

  private func disable() -> Bool {
    stateLock.lock()
    defer { stateLock.unlock() }

    guard enabled else {
      return false
    }

    enabled = false
    return true
  }

  private func fail(_ reason: LiveAudioFailureReason) {
    guard disable() else {
      return
    }

    Self.attemptFailurePacket(source: source, reason: reason, packetWriter: packetWriter)
  }

  private static func attemptFailurePacket(
    source: LiveAudioSource,
    reason: LiveAudioFailureReason,
    packetWriter: PacketWriting
  ) {
    do {
      try packetWriter.writeFailure(source: source, reason: reason)
    } catch {
      // The failure packet is best-effort and is never retried.
    }
  }
}
