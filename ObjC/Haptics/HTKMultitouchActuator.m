//
//  HTKMultitouchActuator.m
//  HapticKey
//
//  Created by Yoshimasa Niwa on 12/3/17.
//  Copyright © 2017 Yoshimasa Niwa. All rights reserved.
//

#import "HTKMultitouchActuator.h"

@import IOKit;
@import os.log;

NS_ASSUME_NONNULL_BEGIN

// Private Framework Functions
CF_EXPORT CFTypeRef MTActuatorCreateFromDeviceID(UInt64 deviceID);
CF_EXPORT IOReturn MTActuatorOpen(CFTypeRef actuatorRef);
CF_EXPORT IOReturn MTActuatorClose(CFTypeRef actuatorRef);
// The last 3 arguments are unknown, but the 4th (a Float) appears to control intensity.
CF_EXPORT IOReturn MTActuatorActuate(CFTypeRef actuatorRef, SInt32 actuationID, UInt32 unknown1, Float32 intensity, Float32 unknown3);
CF_EXPORT bool MTActuatorIsOpen(CFTypeRef actuatorRef);

@interface HTKMultitouchActuator ()

@property (nonatomic) UInt64 lastKnownMultitouchDeviceMultitouchID;

@end

@implementation HTKMultitouchActuator
{
    CFTypeRef _actuatorRef;
}

+ (instancetype)sharedActuator
{
    static dispatch_once_t onceToken;
    static HTKMultitouchActuator *sharedActuator;
    dispatch_once(&onceToken, ^{
        sharedActuator = [[HTKMultitouchActuator alloc] init];
    });
    return sharedActuator;
}

- (void)dealloc
{
    [self _htk_main_closeActuator];
}

// MODIFIED: Method signature changed to accept intensity
- (BOOL)actuateActuationID:(SInt32)actuationID intensity:(Float32)intensity
{
    [self _htk_main_openActuator];
    // MODIFIED: Pass intensity to the internal actuate call
    BOOL result = [self _htk_main_actuateActuationID:actuationID intensity:intensity];

    if (!result) {
        [self _htk_main_closeActuator];
        [self _htk_main_openActuator];
        result = [self _htk_main_actuateActuationID:actuationID intensity:intensity];
    }

    return result;
}

- (void)_htk_main_openActuator
{
    if (_actuatorRef) {
        return;
    }

    if (self.lastKnownMultitouchDeviceMultitouchID) {
        const CFTypeRef actuatorRef = MTActuatorCreateFromDeviceID(self.lastKnownMultitouchDeviceMultitouchID);
        if (!actuatorRef) {
            os_log_error(OS_LOG_DEFAULT, "Fail to MTActuatorCreateFromDeviceID: 0x%llx", self.lastKnownMultitouchDeviceMultitouchID);
            return;
        }
        _actuatorRef = actuatorRef;
    } else {
        io_iterator_t itreator = IO_OBJECT_NULL;
        const CFMutableDictionaryRef matchingRef = IOServiceMatching("AppleMultitouchDevice");
        const kern_return_t result = IOServiceGetMatchingServices(kIOMainPortDefault, matchingRef, &itreator);
        if (result != KERN_SUCCESS) {
            os_log_info(OS_LOG_DEFAULT, "Failed to get matching services: 0x%x", result);
            return;
        }

        io_service_t service = IO_OBJECT_NULL;
        while ((service = IOIteratorNext(itreator)) != IO_OBJECT_NULL) {
            CFMutableDictionaryRef propertiesRef = NULL;
            const kern_return_t result = IORegistryEntryCreateCFProperties(service, &propertiesRef, CFAllocatorGetDefault(), 0);
            if (result != KERN_SUCCESS) {
                IOObjectRetain(service);
                continue;
            }

            NSMutableDictionary * const properties = (__bridge_transfer NSMutableDictionary *)propertiesRef;

            NSNumber * const acutuationSupportedProperty = (NSNumber *)properties[@"ActuationSupported"];
            NSNumber * const mtBuildInProperty = (NSNumber *)properties[@"MT Built-In"];
            if (!(acutuationSupportedProperty.boolValue && mtBuildInProperty.boolValue)) {
                IOObjectRetain(service);
                continue;
            }

            NSNumber * const multitouchIDProperty = (NSNumber *)properties[@"Multitouch ID"];
            const UInt64 multitouchDeviceMultitouchID = multitouchIDProperty.longLongValue;
            const CFTypeRef actuatorRef = MTActuatorCreateFromDeviceID(multitouchDeviceMultitouchID);
            if (!actuatorRef) {
                IOObjectRetain(service);
                continue;
            }
            
            _actuatorRef = actuatorRef;
            self.lastKnownMultitouchDeviceMultitouchID = multitouchDeviceMultitouchID;

            IOObjectRelease(service);
            break;
        }
        IOObjectRelease(itreator);

        if (!_actuatorRef) {
            os_log_info(OS_LOG_DEFAULT, "Fail to any MTActuatorCreateFromDeviceID");
            return;
        }
    }

    const IOReturn error = MTActuatorOpen(_actuatorRef);
    if (error != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Fail to MTActuatorOpen: %p error: 0x%x", _actuatorRef, error);
        CFRelease(_actuatorRef);
        _actuatorRef = NULL;
        return;
    }
}

- (void)_htk_main_closeActuator
{
    if (!_actuatorRef) {
        return;
    }

    const IOReturn error = MTActuatorClose(_actuatorRef);
    if (error != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Fail to MTActuatorClose: %p error: 0x%x", _actuatorRef, error);
    }
    CFRelease(_actuatorRef);
    _actuatorRef = NULL;
}

// MODIFIED: Method signature changed to accept intensity
- (BOOL)_htk_main_actuateActuationID:(SInt32)actuationID intensity:(Float32)intensity
{
    if (!_actuatorRef) {
        os_log_error(OS_LOG_DEFAULT, "The actuator is not opened yet.");
        return NO;
    }

    // MODIFIED: Pass the intensity parameter to the MTActuatorActuate function.
    // The other "unknown" parameters remain 0.
    const IOReturn error = MTActuatorActuate(_actuatorRef, actuationID, 0, intensity, 0.0);
    if (error != kIOReturnSuccess) {
        os_log_error(OS_LOG_DEFAULT, "Fail to MTActuatorActuate: %p, %d, %f error: 0x%x", _actuatorRef, actuationID, intensity, error);
        return NO;
    } else {
        return YES;
    }
}

@end

NS_ASSUME_NONNULL_END
