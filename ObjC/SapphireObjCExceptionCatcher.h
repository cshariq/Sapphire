//
//  SapphireObjCExceptionCatcher.h
//  Sapphire
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Runs `block` inside an Objective-C `@try/@catch`. Returns YES on success.
/// Firestore LevelDB assertions raise `NSInternalInconsistencyException`, which
/// Swift `do/catch` cannot intercept.
FOUNDATION_EXPORT BOOL SapphireTryObjC(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error);

NS_ASSUME_NONNULL_END
