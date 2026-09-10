import Darwin
import Foundation

/// Keeps one PolyPals process alive per signed-in macOS user, even when the
/// executable is launched from Xcode, a local build, or /Applications.
final class SingleInstanceLock {
    let isAcquired: Bool

    private var descriptor: Int32 = -1

    init(identifier: String) {
        let lockPath = "/tmp/\(identifier).\(getuid()).instance.lock"
        descriptor = Darwin.open(lockPath, O_CREAT | O_RDWR | O_CLOEXEC, S_IRUSR | S_IWUSR)

        // A temporary-directory failure should not make the app unusable. In
        // that rare case, allow launch and rely on normal AppKit activation.
        guard descriptor >= 0 else {
            isAcquired = true
            return
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            isAcquired = true
        } else {
            isAcquired = false
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    deinit {
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}
