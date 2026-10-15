//
//  KBPPulseManager.m
//  Sapphire
//
//  Created by EthanRDoesMC on 10/20/21.
//

#import "KBPPulseManager.h"
#import "KBPAnimator.h"

@interface KBPPulseManager()
+(void)loadPrivateFrameworks;
+(void)modifyBacklightSettings;
@end

@implementation KBPPulseManager

+ (id)sharedInstance {
    static KBPPulseManager *sharedInstance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[self alloc] init];
    });
    return sharedInstance;
}

// --- FINAL FIX: Rewritten for clarity and to eliminate syntax errors ---
+(void)loadPrivateFrameworks {
    printf("Loading private frameworks\n");
    
    // Load CoreBrightness framework
    NSBundle *coreBrightnessBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"];
    BOOL coreBrightnessLoaded = [coreBrightnessBundle load];
    printf("CoreBrightness: %hhd\n", coreBrightnessLoaded);
    
    // Create and set the KeyboardBrightnessClient instance
    Class kbcClass = NSClassFromString(@"KeyboardBrightnessClient");
    if (kbcClass) {
        // This is the ARC-safe way to create the instance.
        id kbcInstance = [[kbcClass alloc] init];
        [KBPPulseManager.sharedInstance setBrightnessClient:kbcInstance];
    } else {
        printf("Keyboard backlight ERROR: KeyboardBrightnessClient class not found!\n");
    }
    
    // Load OSD framework
    NSBundle *osdBundle = [NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/OSD.framework"];
    BOOL osdLoaded = [osdBundle load];
    printf("OSD: %hhd\n", osdLoaded);
}

+(void)modifyBacklightSettings {
    printf("Disabling idle-dimming and auto-brightness\n");
    if (KBPPulseManager.brightnessClient) {
        [KBPPulseManager.brightnessClient setIdleDimTime:0 forKeyboard:1];
        [KBPPulseManager.brightnessClient enableAutoBrightness:false forKeyboard:1];
    }
}

+(void)configure {
    [self loadPrivateFrameworks];
    [self modifyBacklightSettings];
}

+(KeyboardBrightnessClient *)brightnessClient {
    return [KBPPulseManager.sharedInstance brightnessClient];
}

- (id)init {
    if (self = [super init]) {
        self.paused = false;
    }
    return self;
}

@end
