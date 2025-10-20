// --- START OF FILE MTPrivateTimerController.h ---

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface MTPrivateTimerController : NSObject
- (void)pauseTimerWithId:(NSString *)timerID;
- (void)resumeTimerWithId:(NSString *)timerID;
- (void)stopTimerWithId:(NSString *)timerID;

- (void)pauseStopwatch;
- (void)resumeStopwatch;
- (void)resetStopwatch;
- (void)lapStopwatch;
@end

NS_ASSUME_NONNULL_END
// --- END OF FILE MTPrivateTimerController.h ---
