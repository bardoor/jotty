import Darwin
import Foundation

final class DynamicAECProcessor: AECProcessing, @unchecked Sendable {
  enum Error: Swift.Error, LocalizedError {
    case invalidFrame
    case invalidDelay
    case cannotLoadLibrary(String)
    case missingSymbol(String)
    case cannotCreateProcessor
    case processingFailed(Int32)

    var errorDescription: String? {
      switch self {
      case .invalidFrame:
        "AEC requires 160-sample mono Int16 frames"
      case .invalidDelay:
        "AEC stream delay cannot be negative"
      case .cannotLoadLibrary(let reason):
        "Cannot load AEC library: \(reason)"
      case .missingSymbol(let symbol):
        "AEC library is missing symbol \(symbol)"
      case .cannotCreateProcessor:
        "Cannot create AEC processor"
      case .processingFailed(let status):
        "AEC processing failed with status \(status)"
      }
    }
  }

  private typealias Create = @convention(c) () -> OpaquePointer?
  private typealias Destroy = @convention(c) (OpaquePointer?) -> Void
  private typealias ProcessRender =
    @convention(c) (OpaquePointer?, UnsafePointer<Int16>?, Int) -> Int32
  private typealias ProcessCapture =
    @convention(c) (
      OpaquePointer?,
      UnsafePointer<Int16>?,
      Int,
      Int32,
      UnsafeMutablePointer<Int16>?
    ) -> Int32

  private static let frameSampleCount = 160
  private static let frameByteCount = frameSampleCount * MemoryLayout<Int16>.size

  private let library: UnsafeMutableRawPointer
  private let processor: OpaquePointer
  private let destroyFunction: Destroy
  private let processRenderFunction: ProcessRender
  private let processCaptureFunction: ProcessCapture

  static func libraryURL(adjacentTo executableURL: URL) -> URL {
    executableURL.deletingLastPathComponent().appending(path: "libJottyAEC.dylib")
  }

  init(libraryPath: String) throws {
    guard let library = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
      throw Error.cannotLoadLibrary(String(cString: dlerror()))
    }

    do {
      let create: Create = try Self.loadSymbol("jotty_aec_create", from: library)
      let destroy: Destroy = try Self.loadSymbol("jotty_aec_destroy", from: library)
      let processRender: ProcessRender = try Self.loadSymbol(
        "jotty_aec_process_render",
        from: library
      )
      let processCapture: ProcessCapture = try Self.loadSymbol(
        "jotty_aec_process_capture",
        from: library
      )

      guard let processor = create() else {
        throw Error.cannotCreateProcessor
      }

      self.library = library
      self.processor = processor
      destroyFunction = destroy
      processRenderFunction = processRender
      processCaptureFunction = processCapture
    } catch {
      dlclose(library)
      throw error
    }
  }

  deinit {
    destroyFunction(processor)
    dlclose(library)
  }

  func processRender(_ render: Data) throws {
    guard render.count == Self.frameByteCount else {
      throw Error.invalidFrame
    }

    let status = render.withUnsafeBytes { renderBytes in
      processRenderFunction(
        processor,
        renderBytes.bindMemory(to: Int16.self).baseAddress,
        Self.frameSampleCount
      )
    }
    try validate(status)
  }

  func processCapture(_ capture: Data, delayMilliseconds: Int) throws -> Data {
    guard capture.count == Self.frameByteCount else {
      throw Error.invalidFrame
    }
    guard delayMilliseconds >= 0, let delay = Int32(exactly: delayMilliseconds) else {
      throw Error.invalidDelay
    }

    var output = Data(count: Self.frameByteCount)
    let status = capture.withUnsafeBytes { captureBytes in
      output.withUnsafeMutableBytes { outputBytes in
        processCaptureFunction(
          processor,
          captureBytes.bindMemory(to: Int16.self).baseAddress,
          Self.frameSampleCount,
          delay,
          outputBytes.bindMemory(to: Int16.self).baseAddress
        )
      }
    }
    try validate(status)
    return output
  }

  private func validate(_ status: Int32) throws {
    guard status == 0 else {
      throw Error.processingFailed(status)
    }
  }

  private static func loadSymbol<T>(
    _ name: String,
    from library: UnsafeMutableRawPointer
  ) throws -> T {
    guard let symbol = dlsym(library, name) else {
      throw Error.missingSymbol(name)
    }

    return unsafeBitCast(symbol, to: T.self)
  }
}
