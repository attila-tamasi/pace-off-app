// OnceFlag.swift
// A thread-safe "first caller wins" flag, for work that two paths may try
// to finish, such as a background task whose work ends just as iOS expires
// it: only one of them may report it complete.

import Foundation

public final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var claimed = false

    public init() {}

    /// True for the first caller only, from any thread.
    public func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !claimed else { return false }
        claimed = true
        return true
    }
}
