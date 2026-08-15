//
//  KeyboardBacklightManager.h
//  Sapphire
//
//  Created by Shariq Charolia on 2025-08-22.
//


//
//  KeyboardBacklightManager.h
//  Sapphire
//
//  Created by Gemini Assistant.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface KeyboardBacklightManager : NSObject

+ (id)sharedManager;

/// Loads private frameworks and prepares for keyboard brightness control.
/// Must be called once at app startup.
- (void)configure;

/// Gets the current keyboard brightness level.
/// @return A float value between 0.0 and 1.0.
- (float)getBrightness;

/// Sets the keyboard brightness level with a smooth, native fade.
/// @param brightness The target brightness level, from 0.0 to 1.0.
- (void)setBrightness:(float)brightness;

@end

NS_ASSUME_NONNULL_END