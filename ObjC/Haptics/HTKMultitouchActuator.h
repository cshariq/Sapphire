//
//  HTKMultitouchActuator.h
//  HapticKey
//
//  Created by Yoshimasa Niwa on 12/3/17.
//  Copyright © 2017 Yoshimasa Niwa. All rights reserved.
//

@import Foundation;

NS_ASSUME_NONNULL_BEGIN

@interface HTKMultitouchActuator : NSObject

+ (instancetype)sharedActuator;

// MODIFIED: Added intensity parameter
- (BOOL)actuateActuationID:(SInt32)actuationID intensity:(Float32)intensity;

@end

NS_ASSUME_NONNULL_END
