//
//  NativeChargeLimit.swift
//  Sapphire
//
//  Thin wrapper around macOS's native Charge Limit (PowerUI's PowerUISmartChargeClient).
//  Used on firmware where the SMC charge-inhibit keys are gated but the native limit works.
//  Every call fails soft if the framework, class or a selector is missing.
//

import Foundation
import ObjectiveC
import OSLog

private let nativeLimitLogger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "Sapphire", category: "NativeChargeLimit")

enum NativeChargeLimit {
    /// Firmware only accepts limits in this range.
    static let supportedRange = 80...100

    private static let ownsKey = "sapphire.nativeChargeLimit.owned"
    private static let priorEnabledKey = "sapphire.nativeChargeLimit.priorEnabled"
    private static let priorLimitKey = "sapphire.nativeChargeLimit.priorLimit"

    // Type encodings (verified at runtime via class_copyMethodList):
    //   initWithClientName:   @24@0:8@16
    //   isMCLSupported        B16@0:8
    //   isMCLCurrentlyEnabled: Q24@0:8^@16
    //   enableMCL: / disableMCL: B24@0:8^@16
    //   getMCLLimitWithError: C24@0:8^@16
    //   setMCLLimit:error:    B28@0:8C16^@20
    private typealias ErrorPointer = AutoreleasingUnsafeMutablePointer<NSError?>?
    private typealias AllocFn = @convention(c) (AnyObject, Selector) -> Unmanaged<AnyObject>?
    private typealias InitFn = @convention(c) (AnyObject, Selector, NSString) -> Unmanaged<AnyObject>?
    private typealias BoolFn = @convention(c) (AnyObject, Selector) -> Bool
    private typealias EnabledFn = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt64
    private typealias ToggleFn = @convention(c) (AnyObject, Selector, ErrorPointer) -> Bool
    private typealias GetLimitFn = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt8
    private typealias SetLimitFn = @convention(c) (AnyObject, Selector, UInt8, ErrorPointer) -> Bool

    // All mutable state below is only touched on `queue`.
    private static let queue = DispatchQueue(label: "com.shariq.sapphire.nativeChargeLimit")
    private static var client: AnyObject?
    private static var didAttemptLoad = false
    /// A limit the firmware silently refused; not retried until a different limit is requested.
    private static var rejectedLimit: Int?

    // MARK: - Public API

    static var isSupported: Bool {
        get async { await run { supportedOnQueue() } }
    }

    /// nil if the state could not be read.
    static var isEnabled: Bool? {
        get async { await run { enabledOnQueue() } }
    }

    /// nil if the limit could not be read.
    static var currentLimit: Int? {
        get async { await run { limitOnQueue() } }
    }

    /// True while Sapphire has taken over the native limit (persisted across launches).
    static var sapphireOwnsLimit: Bool {
        UserDefaults.standard.bool(forKey: ownsKey)
    }

    /// Applies `limit` natively (80...99 enables it, 100 releases it). Returns false on failure.
    @discardableResult
    static func apply(limit: Int) async -> Bool {
        await run { applyOnQueue(limit: limit) }
    }

    /// Gives the native limit back to the user's own prior setting, if Sapphire took it over.
    @discardableResult
    static func release() async -> Bool {
        await run { releaseOnQueue() }
    }

    // MARK: - Queue-confined implementation

    private static func run<T>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            queue.async {
                loadClientIfNeeded()
                continuation.resume(returning: work())
            }
        }
    }

    private static func applyOnQueue(limit: Int) -> Bool {
        guard supportedOnQueue() else { return false }
        guard supportedRange.contains(limit) else { return false }
        if limit >= 100 { return releaseOnQueue() }
        if rejectedLimit == limit { return false }
        rejectedLimit = nil

        let defaults = UserDefaults.standard
        if !defaults.bool(forKey: ownsKey) {
            // First takeover: remember the user's own native setting so it can be restored.
            defaults.set(enabledOnQueue() ?? false, forKey: priorEnabledKey)
            defaults.set(limitOnQueue() ?? 0, forKey: priorLimitKey)
            defaults.set(true, forKey: ownsKey)
        }

        // Compare against the live state: macOS calibration or the user in System Settings can change
        // the native limit behind Sapphire's back.
        if enabledOnQueue() == true, limitOnQueue() == limit { return true }

        guard setLimitOnQueue(limit), setEnabledOnQueue(true) else { return false }

        // setMCLLimit:error: can report success without changing anything (seen on an M5 with
        // macOS 27.0.1: the limit stays at the value chosen in System Settings), so read it back
        // and let the caller fall back to the adapter path if it didn't take.
        for attempt in 0..<5 {
            if limitOnQueue() == limit {
                nativeLimitLogger.info("[NativeChargeLimit] Applied native charge limit \(limit)%")
                return true
            }
            if attempt < 4 { Thread.sleep(forTimeInterval: 0.2) }
        }
        nativeLimitLogger.error("[NativeChargeLimit] setMCLLimit(\(limit)) reported success but the limit did not change")
        rejectedLimit = limit
        _ = releaseOnQueue()
        return false
    }

    private static func releaseOnQueue() -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: ownsKey) else { return true }
        guard supportedOnQueue() else { return false }

        let priorEnabled = defaults.bool(forKey: priorEnabledKey)
        let priorLimit = defaults.integer(forKey: priorLimitKey)
        var ok = true
        if priorEnabled, supportedRange.contains(priorLimit) {
            ok = setLimitOnQueue(priorLimit) && setEnabledOnQueue(true)
        } else if priorEnabled {
            ok = setEnabledOnQueue(true)
        } else {
            ok = setEnabledOnQueue(false)
        }

        // Keep ownership on failure so the next release attempt retries.
        guard ok else { return false }
        defaults.set(false, forKey: ownsKey)
        defaults.removeObject(forKey: priorEnabledKey)
        defaults.removeObject(forKey: priorLimitKey)
        nativeLimitLogger.info("[NativeChargeLimit] Released native charge limit (restored user setting)")
        return true
    }

    private static func supportedOnQueue() -> Bool {
        guard let client, let fn: BoolFn = function(on: client, "isMCLSupported") else { return false }
        return fn(client, NSSelectorFromString("isMCLSupported"))
    }

    private static func enabledOnQueue() -> Bool? {
        guard let client, let fn: EnabledFn = function(on: client, "isMCLCurrentlyEnabled:") else { return nil }
        var error: NSError?
        let value = fn(client, NSSelectorFromString("isMCLCurrentlyEnabled:"), &error)
        if let error {
            nativeLimitLogger.error("[NativeChargeLimit] isMCLCurrentlyEnabled failed: \(error.localizedDescription)")
            return nil
        }
        return value != 0
    }

    private static func limitOnQueue() -> Int? {
        guard let client, let fn: GetLimitFn = function(on: client, "getMCLLimitWithError:") else { return nil }
        var error: NSError?
        let value = fn(client, NSSelectorFromString("getMCLLimitWithError:"), &error)
        if let error {
            nativeLimitLogger.error("[NativeChargeLimit] getMCLLimit failed: \(error.localizedDescription)")
            return nil
        }
        return Int(value)
    }

    private static func setLimitOnQueue(_ limit: Int) -> Bool {
        guard let client, let fn: SetLimitFn = function(on: client, "setMCLLimit:error:") else { return false }
        var error: NSError?
        let ok = fn(client, NSSelectorFromString("setMCLLimit:error:"), UInt8(clamping: limit), &error)
        if !ok {
            nativeLimitLogger.error("[NativeChargeLimit] setMCLLimit(\(limit)) failed: \(error?.localizedDescription ?? "unknown")")
        }
        return ok
    }

    private static func setEnabledOnQueue(_ enabled: Bool) -> Bool {
        let name = enabled ? "enableMCL:" : "disableMCL:"
        guard let client, let fn: ToggleFn = function(on: client, name) else { return false }
        var error: NSError?
        let ok = fn(client, NSSelectorFromString(name), &error)
        if !ok {
            nativeLimitLogger.error("[NativeChargeLimit] \(name) failed: \(error?.localizedDescription ?? "unknown")")
        }
        return ok
    }

    /// Resolves the IMP for `selector` on the client's class and casts it to `T`.
    private static func function<T>(on client: AnyObject, _ selector: String) -> T? {
        guard let method = class_getInstanceMethod(object_getClass(client), NSSelectorFromString(selector)) else { return nil }
        return unsafeBitCast(method_getImplementation(method), to: T.self)
    }

    /// Loads PowerUI and creates the client once. Must run on `queue`.
    private static func loadClientIfNeeded() {
        guard !didAttemptLoad else { return }
        didAttemptLoad = true

        guard Bundle(path: "/System/Library/PrivateFrameworks/PowerUI.framework")?.load() == true,
              let cls = NSClassFromString("PowerUISmartChargeClient") as? NSObject.Type else {
            nativeLimitLogger.info("[NativeChargeLimit] PowerUISmartChargeClient unavailable")
            return
        }

        let initSel = NSSelectorFromString("initWithClientName:")
        let allocSel = NSSelectorFromString("alloc")
        guard let initMethod = class_getInstanceMethod(cls, initSel),
              let allocMethod = class_getClassMethod(cls, allocSel),
              let allocated = unsafeBitCast(method_getImplementation(allocMethod), to: AllocFn.self)(cls, allocSel)?.takeRetainedValue() else {
            nativeLimitLogger.info("[NativeChargeLimit] alloc/initWithClientName: unavailable")
            return
        }
        // The init IMP consumes `self` (+1) but Swift passes it at +0; balance with an extra retain.
        _ = Unmanaged.passRetained(allocated)

        let initFn = unsafeBitCast(method_getImplementation(initMethod), to: InitFn.self)
        client = initFn(allocated, initSel, "Sapphire")?.takeRetainedValue()
    }
}
