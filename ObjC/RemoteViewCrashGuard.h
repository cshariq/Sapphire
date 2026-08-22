//
//  RemoteViewCrashGuard.h
//  Sapphire
//
//  See RemoteViewCrashGuard.m for the full rationale: Apple ViewBridge can
//  throw an uncaught NSInternalInconsistencyException when a window containing
//  an NSRemoteView (any SwiftUI hosting view) is ordered on screen on
//  macOS 26/27. This installs a narrow crash guard for that assertion.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Installs the crash guard. Safe to call any number of times from any thread
/// (installs exactly once). No-op on macOS versions that don't carry the bug
/// and when ViewBridge's NSRemoteView is unavailable.
FOUNDATION_EXPORT void RemoteViewCrashGuardInstall(void);

/// Runs `block` synchronously, suppressing only the ViewBridge
/// NSInternalInconsistencyException (the same narrow predicate as the
/// notification-handler guard) and re-raising every other exception. Wrap
/// window-ordering operations in this to stay up on ViewBridge raise sites that
/// are hit synchronously inside -[NSWindow _doOrderWindow:] and are not covered
/// by the swizzled handlers.
FOUNDATION_EXPORT void RemoteViewCrashGuardRunBlock(void (^block)(void));

NS_ASSUME_NONNULL_END
