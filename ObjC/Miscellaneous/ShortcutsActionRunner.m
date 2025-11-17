// --- START OF FILE ShortcutsActionRunner.m ---

#import "ShortcutsActionRunner.h"
#import <Intents/Intents.h>

// Forward-declare the Intent classes. These are the correct names.
@interface LapStopwatchIntent : INIntent
@end
@interface ResetStopwatchIntent : INIntent
@end
@interface StartStopwatchIntent : INIntent
@end
@interface StopStopwatchIntent : INIntent // This intent is used for "pausing"
@end

@interface PauseTimerIntent : INIntent
@property (copy, nonatomic, nullable) NSString *timerID;
@end
@interface ResumeTimerIntent : INIntent
@property (copy, nonatomic, nullable) NSString *timerID;
@end
@interface StopTimerIntent : INIntent // This intent is used for "canceling/stopping"
@property (copy, nonatomic, nullable) NSString *timerID;
@end

@implementation ShortcutsActionRunner

- (void)runStopwatchAction:(StopwatchAction)action {
    INIntent *intent = nil;

    switch (action) {
        case StopwatchActionLap:
            intent = [NSClassFromString(@"LapStopwatchIntent") new];
            break;
        case StopwatchActionReset:
            intent = [NSClassFromString(@"ResetStopwatchIntent") new];
            break;
        case StopwatchActionResume: // "Start Stopwatch" is used for both starting and resuming.
            intent = [NSClassFromString(@"StartStopwatchIntent") new];
            break;
        case StopwatchActionPause: // "Stop the Stopwatch" is the action for pausing.
            intent = [NSClassFromString(@"StopStopwatchIntent") new];
            break;
    }
    
    if (intent) {
        NSLog(@"[ShortcutsActionRunner] Donating stopwatch intent: %@", NSStringFromClass([intent class]));
        [self donateIntent:intent withIdentifier:@"com.apple.mobiletimer.stopwatch-action"];
    }
}

- (void)runTimerAction:(TimerAction)action withId:(NSString *)timerID {
    INIntent *intent = nil;

    switch (action) {
        case TimerActionPause:
            intent = [NSClassFromString(@"PauseTimerIntent") new];
            [intent setValue:timerID forKey:@"timerID"];
            break;
        case TimerActionResume:
            intent = [NSClassFromString(@"ResumeTimerIntent") new];
            [intent setValue:timerID forKey:@"timerID"];
            break;
        case TimerActionStop:
            intent = [NSClassFromString(@"StopTimerIntent") new];
            [intent setValue:timerID forKey:@"timerID"];
            break;
    }

    if (intent) {
        NSLog(@"[ShortcutsActionRunner] Donating timer intent: %@ with ID %@", NSStringFromClass([intent class]), timerID);
        [self donateIntent:intent withIdentifier:@"com.apple.mobiletimer.timer-action"];
    }
}

- (void)donateIntent:(INIntent *)intent withIdentifier:(NSString *)identifier {
    INInteraction *interaction = [[INInteraction alloc] initWithIntent:intent response:nil];
    interaction.identifier = identifier;
    
    [interaction donateInteractionWithCompletion:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"[ShortcutsActionRunner] Failed to donate interaction: %@", error);
        } else {
            NSLog(@"[ShortcutsActionRunner] Successfully donated '%@' interaction.", NSStringFromClass([intent class]));
        }
    }];
}

@end
// --- END OF FILE ShortcutsActionRunner.m ---
