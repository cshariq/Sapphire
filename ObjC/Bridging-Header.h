//
//  Bridging-Header.h
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-02.
//

#import "NDNotificationCenterHackery.h"
#import <CoreGraphics/CoreGraphics.h>
#import "KeyboardBacklightManager.h"
#import "PrivateAPI.h"
#include "lowlevel.h"
#import "IMessageService.h" // We will create this next
#import "MTPrivateTimerController.h"
#import "ShortcutsActionRunner.h"

// Import the private headers you need
#import "IMChat.h"
#import "IMChatRegistry.h"
#import "IMMessage.h"
#import "IMAccountController.h"
#import "TUCall.h"
#import "TUCallCenter.h"

int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);
