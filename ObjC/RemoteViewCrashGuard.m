//
//  RemoteViewCrashGuard.m
//  Sapphire
//
//  Crash guard for an Apple ViewBridge bug that kills apps on macOS 26/27 when
//  a window containing an NSRemoteView is ordered on screen. NSRemoteView is
//  ViewBridge's out-of-process (XPC-hosted) view; on macOS 26+ every SwiftUI
//  hosting view carries one.
//
//  The remote view registers itself for per-window _NSWindowWillBecomeVisible /
//  _NSWindowDidBecomeVisible notifications of its containing window. A stale
//  registration (Apple leaked it in -[NSRemoteView
//  maintainContainingWindowNotifications:] whenever the weak containing-window
//  ivar was already nil) or a transient mid-layout state leaves the view
//  registered for a window that is no longer its own. When that notification
//  fires, -[NSRemoteView containingWindowWillOrderOnScreen:] compares
//  [self window] against the notification's object and throws
//
//      NSInternalInconsistencyException
//      '<NSRemoteView: 0x…> notified of <NSWindow: 0x…> but expected (null)'
//
//  The exception is uncaught, so the app aborts. Sapphire has hit this from
//  several triggers: ordering the lock screen widgets (SwiftUI-backed borderless
//  windows) on screen, and creating the menu bar status items, whose windows are
//  ordered on screen as soon as NSStatusBar.system.statusItem(withLength:) is
//  called. Every SwiftUI window in the app is equally exposed.
//
//  Apple fixed the underlying registration leak in macOS 27 beta5 (26A5406e) —
//  tracked at https://github.com/jizhi0v0/macos27-beta-issues/issues/17 and
//  Apple Developer Forums thread 837342 — but affected builds still crash.
//  This guard swizzles all six per-window notification handlers that
//  NSRemoteView registers and suppresses ONLY the specific assertion,
//  re-raising every other exception. The two order-on-screen handlers are the
//  verified assertion sites (containingWindowWillOrderOnScreen: has one; the
//  Did counterpart has two more, verified by disassembly of ViewBridge on
//  macOS 27 beta5), but the off-screen / move / occlusion handlers are guarded
//  too since a stale registration can be notified through any of them.
//
//  This is a crash guard, not a fix: swallowing the assertion leaves the remote
//  view in the state AppKit flagged as inconsistent. Verified by disassembly
//  that skipping the Will handler does not cascade (its ordering state machine
//  has no assertion sites), but whether the window then draws correctly is
//  unverified, and the file should be removed once Apple ships the fix to all
//  supported macOS versions.
//
//  This swizzles a private class and private methods via NSClassFromString /
//  NSSelectorFromString (no static symbol references). Sapphire already loads
//  and calls private SkyLight symbols directly, so this matches the app's
//  posture; it would not be appropriate for a Mac App Store submission.
//

#import "RemoteViewCrashGuard.h"
#import <AppKit/AppKit.h>
#import <objc/runtime.h>
#import <os/log.h>
#import <dlfcn.h>

static os_log_t RemoteViewGuardLog(void) {
    static os_log_t log;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        log = os_log_create("Sapphire", "RemoteViewCrashGuard");
    });
    return log;
}

/// Only macOS 26+ is known to carry this bug (Sapphire has reproduced the
/// assertion on both 26 and 27; Apple's fix landed in macOS 27 beta5).
static BOOL RemoteViewGuardShouldInstall(void) {
    return NSProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 26;
}

/// Shared predicate for the ViewBridge bug: it surfaces as
/// NSInternalInconsistencyException whose reason names the remote view (e.g.
/// '<NSRemoteView: …> notified of <NSWindow: …> but expected (null)'). Keep it
/// narrow: every other exception must re-raise.
static BOOL RemoteViewGuardIsViewBridgeAssertion(NSException *e) {
    return [e.name isEqualToString:NSInternalInconsistencyException]
        && [e.reason containsString:@"NSRemoteView"];
}

/// -isValid is private on NSRemoteView; read it defensively and report "?"
/// rather than assuming it exists. It is the first thing the real method checks.
static NSString *RemoteViewGuardIsValidDescription(id remoteView) {
    SEL sel = NSSelectorFromString(@"isValid");
    if (![remoteView respondsToSelector:sel]) return @"?";
    NSMethodSignature *sig = [remoteView methodSignatureForSelector:sel];
    if (strcmp(sig.methodReturnType, @encode(BOOL)) != 0) return @"?";
    NSInvocation *inv = [NSInvocation invocationWithMethodSignature:sig];
    inv.selector = sel;
    [inv invokeWithTarget:remoteView];
    BOOL valid = NO;
    [inv getReturnValue:&valid];
    return valid ? @"YES" : @"NO";
}

/// Wrap one notification-handling selector: call the original through,
/// suppressing only the specific ViewBridge assertion and re-raising everything
/// else. The handlers compare [self window] against the notification's object
/// and assert on mismatch, so every registered handler is guarded.
static void RemoteViewGuardGuardSelector(NSString *selName, Class cls) {
    SEL sel = NSSelectorFromString(selName);
    Method method = class_getInstanceMethod(cls, sel);
    if (!method) {
        os_log_error(RemoteViewGuardLog(), "not installed: %{public}@ not found", selName);
        return;
    }
    IMP originalIMP = method_getImplementation(method);
    // imp_implementationWithBlock drops _cmd: the block receives (self, arg1).
    // The argument is an NSNotification — not an NSWindow as the version
    // circulating on the forums types it (harmless, but misleading).
    IMP guarded = imp_implementationWithBlock(^(NSView *rv, NSNotification *note) {
        id noteObject = note.object;
        NSWindow *ownWindow = rv.window; // -window is public API on NSView
        if (ownWindow != noteObject) {
            os_log_error(RemoteViewGuardLog(),
                         "BAD STATE in %{public}@: rv=%p isValid=%{public}@ window=%p note.object=%p",
                         selName, rv, RemoteViewGuardIsValidDescription(rv), ownWindow, noteObject);
        }
        @try {
            ((void (*)(id, SEL, NSNotification *))originalIMP)(rv, sel, note);
        } @catch (NSException *e) {
            if (!RemoteViewGuardIsViewBridgeAssertion(e)) @throw;
            os_log_error(RemoteViewGuardLog(),
                         "SUPPRESSED ViewBridge assertion in %{public}@: %{public}@",
                         selName, e.reason);
        }
    });
    method_setImplementation(method, guarded);
    os_log_info(RemoteViewGuardLog(), "guarded %{public}@", selName);
}

void RemoteViewCrashGuardInstall(void) {
    if (!RemoteViewGuardShouldInstall()) return;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        // ViewBridge loads lazily — the first remote view (open/save panel,
        // QuickLook, share sheet, status item, …) pulls it in. Installed at
        // applicationWillFinishLaunching:, NSClassFromString returns nil and the
        // guard would silently install nothing, so force the framework in
        // first. dlopen works even though ViewBridge lives only in the dyld
        // shared cache.
        if (!NSClassFromString(@"NSRemoteView")) {
            dlopen("/System/Library/PrivateFrameworks/ViewBridge.framework/ViewBridge", RTLD_LAZY);
        }
        Class cls = NSClassFromString(@"NSRemoteView");
        if (!cls) {
            os_log_error(RemoteViewGuardLog(), "not installed: NSRemoteView not found even after loading ViewBridge");
            return;
        }
        // The six notification→selector pairs NSRemoteView registers per
        // containing window. The two order-on-screen handlers hold the verified
        // assertion sites; the rest are guarded for the same stale-registration
        // shape via their own notifications.
        NSArray<NSString *> *handlers = @[
            @"containingWindowWillOrderOnScreen:",
            @"containingWindowDidOrderOnScreen:",
            @"containingWindowWillOrderOffScreen:",
            @"containingWindowDidOrderOffScreen:",
            @"containingWindowDidMove:",
            @"containingWindowDidChangeOcclusionState:",
        ];
        for (NSString *selName in handlers) {
            RemoteViewGuardGuardSelector(selName, cls);
        }
        os_log_info(RemoteViewGuardLog(), "installed for macOS %ld.x",
                    (long)NSProcessInfo.processInfo.operatingSystemVersion.majorVersion);
    });
}

/// Runs `block`, suppressing only the ViewBridge NSInternalInconsistencyException
/// (the same narrow predicate as the notification-handler guard) and re-raising
/// every other exception.
///
/// Some ViewBridge raise sites are reached synchronously inside window-ordering
/// calls (-[NSWindow _doOrderWindow:] etc.) rather than through the six swizzled
/// notification handlers, so callers that order windows on screen should wrap the
/// operation in this to stay up on the same Apple bug. The window operation may be
/// left in the state AppKit flagged as inconsistent — this is a crash guard, not a
/// fix — but the process survives.
void RemoteViewCrashGuardRunBlock(void (^block)(void)) {
    @try {
        block();
    } @catch (NSException *e) {
        if (!RemoteViewGuardIsViewBridgeAssertion(e)) @throw;
        os_log_error(RemoteViewGuardLog(),
                     "SUPPRESSED ViewBridge assertion in guarded block: %{public}@",
                     e.reason);
    }
}
