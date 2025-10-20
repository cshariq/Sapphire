//
//  ShortcutsActionRunner.h
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-21.
//


// --- START OF FILE ShortcutsActionRunner.h ---

#import <Foundation/Foundation.h>

// An enum to make the Swift side clean and type-safe.
typedef NS_ENUM(NSInteger, StopwatchAction) {
    StopwatchActionPause,
    StopwatchActionResume,
    StopwatchActionLap,
    StopwatchActionReset
};

typedef NS_ENUM(NSInteger, TimerAction) {
    TimerActionPause,
    TimerActionResume,
    TimerActionStop
};

NS_ASSUME_NONNULL_BEGIN

@protocol ActionRunning
- (void)runStopwatchAction:(StopwatchAction)action;
- (void)runTimerAction:(TimerAction)action withId:(NSString *)timerID;
@end

@interface ShortcutsActionRunner : NSObject <ActionRunning>
@end

NS_ASSUME_NONNULL_END
// --- END OF FILE ShortcutsActionRunner.h ---
