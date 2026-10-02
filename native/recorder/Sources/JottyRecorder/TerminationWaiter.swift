import Darwin
import Foundation

final class TerminationWaiter: @unchecked Sendable {
  struct ParentExited: Error, Equatable {}

  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Error>?
  private var result: Result<Void, Error>?
  private var interruptSource: DispatchSourceSignal?
  private var parentMonitor: DispatchSourceTimer?
  private var inputSource: DispatchSourceRead?

  init(
    monitorInterrupt: Bool = true,
    parentPID: pid_t? = getppid(),
    parentCheckInterval: DispatchTimeInterval = .seconds(1),
    inputDescriptor: Int32? = STDIN_FILENO
  ) {
    if monitorInterrupt {
      signal(SIGINT, SIG_IGN)
      let source = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
      source.setEventHandler { [weak self] in self?.finish(.success(())) }
      source.resume()
      interruptSource = source
    }

    if let parentPID {
      let monitor = DispatchSource.makeTimerSource(queue: .global())
      monitor.schedule(deadline: .now() + parentCheckInterval, repeating: parentCheckInterval)
      monitor.setEventHandler { [weak self] in
        if getppid() != parentPID {
          self?.finish(.failure(ParentExited()))
        }
      }
      monitor.resume()
      parentMonitor = monitor
    }

    if let inputDescriptor {
      let source = DispatchSource.makeReadSource(fileDescriptor: inputDescriptor, queue: .global())
      source.setEventHandler { [weak self] in
        var byte: UInt8 = 0

        if Darwin.read(inputDescriptor, &byte, 1) == 0 {
          self?.finish(.failure(ParentExited()))
        }
      }
      source.resume()
      inputSource = source
    }
  }

  func wait() async throws {
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { continuation in
        register(continuation)
      }
    } onCancel: {
      finish(.failure(CancellationError()))
    }
  }

  func fail(_ error: Error) {
    finish(.failure(error))
  }

  private func register(_ continuation: CheckedContinuation<Void, Error>) {
    lock.lock()

    if let result {
      lock.unlock()
      continuation.resume(with: result)
    } else {
      self.continuation = continuation
      lock.unlock()
    }
  }

  private func finish(_ result: Result<Void, Error>) {
    lock.lock()

    guard self.result == nil else {
      lock.unlock()
      return
    }

    self.result = result
    let continuation = continuation
    self.continuation = nil
    let interruptSource = interruptSource
    self.interruptSource = nil
    let parentMonitor = parentMonitor
    self.parentMonitor = nil
    let inputSource = inputSource
    self.inputSource = nil
    lock.unlock()

    interruptSource?.cancel()
    parentMonitor?.cancel()
    inputSource?.cancel()
    continuation?.resume(with: result)
  }
}
