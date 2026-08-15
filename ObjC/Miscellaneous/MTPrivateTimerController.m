// --- START OF FILE MTPrivateTimerController.m ---

#import "MTPrivateTimerController.h"
#import <dlfcn.h>

// --- Declare the private interfaces we now know are correct ---
@interface MTTimerManager : NSObject
- (void)pauseTimerWithID:(NSString *)timerID;
- (void)resumeTimerWithID:(NSString *)timerID;
- (void)stopTimerWithID:(NSString *)timerID;
@end

@interface MTStopwatchManager : NSObject
- (void)pause;
- (void)start;
- (void)lap;
- (void)reset;
@end

// We declare the utility class that we believe provides the managers.
@interface MTSessionUtilities : NSObject
+ (MTTimerManager *)timerManager;
+ (MTStopwatchManager *)stopwatchManager;
@end


@implementation MTPrivateTimerController

// --- Caches for Discovered Classes and Managers ---
static dispatch_once_t discoveryToken;

static id timerManagerInstance = nil;
static id stopwatchManagerInstance = nil;

// --- One-time Discovery and Initialization Function ---
static void findAndCacheManagers() {
    NSLog(@"[MTPrivateTimerController] Finding and caching manager instances...");
    
    // We need to load both frameworks to be safe, as classes might reference each other.
    dlopen("/System/Library/PrivateFrameworks/MobileTimerSupport.framework/MobileTimerSupport", RTLD_LAZY);
    const char *mainFrameworkPath = "/System/Library/PrivateFrameworks/MobileTimer.framework/MobileTimer";
    void *handle = dlopen(mainFrameworkPath, RTLD_LAZY);
    
    if (!handle) {
        NSLog(@"[MTPrivateTimerController] CRITICAL: Failed to load MobileTimer.framework: %s", dlerror());
        return;
    }
    
    // Find the central utility class that provides the managers.
    Class sessionUtilsClass = NSClassFromString(@"MTSessionUtilities");

    if (sessionUtilsClass && [sessionUtilsClass respondsToSelector:@selector(timerManager)] && [sessionUtilsClass respondsToSelector:@selector(stopwatchManager)]) {
        NSLog(@"[MTPrivateTimerController] VERIFIED: Found MTSessionUtilities and required provider methods.");
        
        // Get the singleton instances and cache them.
        timerManagerInstance = [sessionUtilsClass timerManager];
        stopwatchManagerInstance = [sessionUtilsClass stopwatchManager];
        
        if (timerManagerInstance) {
            NSLog(@"[MTPrivateTimerController] Successfully cached Timer Manager instance: %@", timerManagerInstance);
        } else {
            NSLog(@"[MTPrivateTimerController] WARNING: Could not get Timer Manager instance from MTSessionUtilities.");
        }
        
        if (stopwatchManagerInstance) {
            NSLog(@"[MTPrivateTimerController] Successfully cached Stopwatch Manager instance: %@", stopwatchManagerInstance);
        } else {
            NSLog(@"[MTPrivateTimerController] WARNING: Could not get Stopwatch Manager instance from MTSessionUtilities.");
        }
        
    } else {
        NSLog(@"[MTPrivateTimerController] CRITICAL: Could not find MTSessionUtilities or its manager provider methods. Controls will be disabled.");
    }
}

#pragma mark - Timer Controls

- (void)pauseTimerWithId:(NSString *)timerID {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (timerManagerInstance) {
        [timerManagerInstance pauseTimerWithID:timerID];
    }
}

- (void)resumeTimerWithId:(NSString *)timerID {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (timerManagerInstance) {
        [timerManagerInstance resumeTimerWithID:timerID];
    }
}

- (void)stopTimerWithId:(NSString *)timerID {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (timerManagerInstance) {
        [timerManagerInstance stopTimerWithID:timerID];
    }
}

#pragma mark - Stopwatch Controls

- (void)pauseStopwatch {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (stopwatchManagerInstance) {
        [stopwatchManagerInstance pause];
    }
}

- (void)resumeStopwatch {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (stopwatchManagerInstance) {
        [stopwatchManagerInstance start];
    }
}

- (void)resetStopwatch {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (stopwatchManagerInstance) {
        [stopwatchManagerInstance reset];
    }
}

- (void)lapStopwatch {
    dispatch_once(&discoveryToken, ^{ findAndCacheManagers(); });
    if (stopwatchManagerInstance) {
        [stopwatchManagerInstance lap];
    }
}

@end
// --- END OF FILE MTPrivateTimerController.m ---
