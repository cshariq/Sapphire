//
//  SapphireObjCExceptionCatcher.m
//  Sapphire
//

#import "SapphireObjCExceptionCatcher.h"

BOOL SapphireTryObjC(void (NS_NOESCAPE ^block)(void), NSError *_Nullable *_Nullable error) {
    @try {
        block();
        return YES;
    } @catch (NSException *exception) {
        if (error != NULL) {
            NSMutableDictionary *info = [NSMutableDictionary dictionary];
            info[NSLocalizedDescriptionKey] = exception.reason ?: exception.name;
            info[@"exception.name"] = exception.name;
            if (exception.reason != nil) {
                info[@"exception.reason"] = exception.reason;
            }
            *error = [NSError errorWithDomain:@"Sapphire.ObjCException" code:1 userInfo:info];
        }
        return NO;
    }
}
