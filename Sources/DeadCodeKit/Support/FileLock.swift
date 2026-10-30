import Foundation

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#endif

/// A machine-wide lock: a second build-heavy run waits for the first.
///
/// Two package builds at once finish later than the same two in sequence, so `scan` and
/// `prune-imports` take this lock before building.
public final class FileLock {
  private let descriptor: Int32

  /// Takes the lock named `name` in the temporary directory, waiting while another process
  /// holds it. `onWait` runs once if the lock is busy.
  public init(name: String, onWait: () -> Void) throws {
    let path = FileManager.default.temporaryDirectory.appendingPathComponent(name).path
    descriptor = open(path, O_CREAT | O_RDWR, 0o644)
    guard descriptor >= 0 else {
      throw DeadCodeError.usage("cannot open lock file \(path)")
    }
    if flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
      onWait()
      guard flock(descriptor, LOCK_EX) == 0 else {
        close(descriptor)
        throw DeadCodeError.usage("cannot lock \(path)")
      }
    }
  }

  deinit {
    flock(descriptor, LOCK_UN)
    close(descriptor)
  }
}
