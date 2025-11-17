//
//  KeyboardBacklightManager.m
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-22.
//


//
//  KeyboardBacklightManager.m
//  Sapphire
//
//  Created by Gemini Assistant.
//

#import "KeyboardBacklightManager.h"
#import "KBPPulseManager.h"
#import "KBPAnimator.h"

@implementation KeyboardBacklightManager

+ (id)sharedManager {
    static KeyboardBacklightManager *sharedManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedManager = [[self alloc] init];
    });
    return sharedManager;
}

- (void)configure {
    // This loads the private frameworks and sets up the brightness client.
    [KBPPulseManager configure];
}

- (float)getBrightness {
    // KBPAnimator provides a direct way to get the current brightness.
    return [KBPAnimator currentBrightness];
}

- (void)setBrightness:(float)brightness {
    // The KeyboardBrightnessClient header notes the manual fade speed is 350ms.
    // We use this for a smooth, native-feeling transition.
    int nativeFadeDuration = 350; // in milliseconds
    [KBPAnimator setBrightness:brightness withDuration:nativeFadeDuration];
}

@end