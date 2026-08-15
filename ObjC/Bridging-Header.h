//
//  Bridging-Header.h
//  Sapphire
//
//  Created by Shariq Charolia on 2025-07-02.
//

#pragma once

#import <Foundation/Foundation.h>
#import <IOKit/hidsystem/IOHIDEventSystemClient.h>
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <CoreGraphics/CoreGraphics.h>
#import "NDNotificationCenterHackery.h"
#import "KeyboardBacklightManager.h"
#import "PrivateAPI.h"
#include "lowlevel.h"
#import "MTPrivateTimerController.h"
#import "ShortcutsActionRunner.h"
#import "HTKMultitouchActuator.h"

int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);


typedef CFTypeRef IOAVService;
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct IOReportSubscriptionRef* IOReportSubscriptionRef;

#ifdef __LP64__
typedef double IOHIDFloat;
#else
typedef float IOHIDFloat;
#endif

#define IOHIDEventFieldBase(type)   (type << 16)
#define kIOHIDEventTypeTemperature  15
#define kIOHIDEventTypePower        25
extern IOAVService IOAVServiceCreate(CFAllocatorRef allocator);
extern IOAVService IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceReadI2C(IOAVService service, uint32_t chipAddress, uint32_t offset, void* outputBuffer, uint32_t outputBufferSize);
extern IOReturn IOAVServiceWriteI2C(IOAVService service, uint32_t chipAddress, uint32_t dataAddress, void* inputBuffer, uint32_t inputBufferSize);
extern CFDictionaryRef CoreDisplay_DisplayCreateInfoDictionary(CGDirectDisplayID);

extern int DisplayServicesGetBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetBrightness(CGDirectDisplayID display, float brightness);
extern int DisplayServicesGetLinearBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetLinearBrightness(CGDirectDisplayID display, float brightness);

extern void CGSServiceForDisplayNumber(CGDirectDisplayID display, io_service_t* service);

bool CGSIsHDREnabled(CGDirectDisplayID display) __attribute__((weak_import));
bool CGSIsHDRSupported(CGDirectDisplayID display) __attribute__((weak_import));

@class NSString;

@protocol OSDUIHelperProtocol
- (void)showFullScreenImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecToAnimate:(unsigned int)arg4;
- (void)fadeClassicImageOnDisplay:(unsigned int)arg1;
- (void)showImageAtPath:(NSString *)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(NSString *)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 filledChiclets:(unsigned int)arg5 totalChiclets:(unsigned int)arg6 locked:(BOOL)arg7;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(NSString *)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4;
@end

@class NSXPCConnection;

@interface OSDManager : NSObject <OSDUIHelperProtocol>
{
    id <OSDUIHelperProtocol> _proxyObject;
    NSXPCConnection *connection;
}

+ (id)sharedManager;
@property(retain) NSXPCConnection *connection; // @synthesize connection;
- (void)showFullScreenImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecToAnimate:(unsigned int)arg4;
- (void)fadeClassicImageOnDisplay:(unsigned int)arg1;
- (void)showImageAtPath:(id)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(id)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 filledChiclets:(unsigned int)arg5 totalChiclets:(unsigned int)arg6 locked:(BOOL)arg7;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4 withText:(id)arg5;
- (void)showImage:(long long)arg1 onDisplayID:(unsigned int)arg2 priority:(unsigned int)arg3 msecUntilFade:(unsigned int)arg4;
@property(readonly) id <OSDUIHelperProtocol> remoteObjectProxy; // @dynamic remoteObjectProxy;

@end

 
 

 
 IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
 int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
 CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
 IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef, int64_t , int32_t, int64_t);
 CFTypeRef IOHIDServiceClientCopyProperty(IOHIDServiceClientRef service, CFStringRef property);
 IOHIDFloat IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
 
 NSDictionary* AppleSiliconSensors(int page, int usage, int32_t type);
 
 CFDictionaryRef IOReportCopyChannelsInGroup(CFStringRef a, CFStringRef b, uint64_t c, uint64_t d, uint64_t e);
 void IOReportMergeChannels(CFDictionaryRef a, CFDictionaryRef b, CFTypeRef null);
 IOReportSubscriptionRef IOReportCreateSubscription(void* a, CFMutableDictionaryRef b, CFMutableDictionaryRef* c, uint64_t d, CFTypeRef e);
 CFDictionaryRef IOReportCreateSamples(IOReportSubscriptionRef a, CFMutableDictionaryRef b, CFTypeRef c);
 int64_t IOReportSimpleGetIntegerValue(CFDictionaryRef samples, CFTypeRef a);
 CFStringRef IOReportChannelGetGroup(CFDictionaryRef a);
 CFStringRef IOReportChannelGetSubGroup(CFDictionaryRef a);
 CFStringRef IOReportChannelGetChannelName(CFDictionaryRef a);
 CFStringRef IOReportChannelGetUnitLabel(CFDictionaryRef a);
 int32_t IOReportStateGetCount(CFDictionaryRef a);
 CFStringRef IOReportStateGetNameForIndex(CFDictionaryRef a, int32_t b);
 int64_t IOReportStateGetResidency(CFDictionaryRef a, int32_t b);

 
 // Include the bridging header that defines the C functions
 
 NSDictionary* AppleSiliconSensors(int32_t page, int32_t usage, int32_t type) {
     NSDictionary* dictionary = @{@"PrimaryUsagePage":@(page),@"PrimaryUsage":@(usage)};
     
     IOHIDEventSystemClientRef system = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
     if (system == nil) return nil;
     IOHIDEventSystemClientSetMatching(system, (__bridge CFDictionaryRef)dictionary);
     CFArrayRef services = IOHIDEventSystemClientCopyServices(system);
     if (services == nil) {
         CFRelease(system);
         return nil;
     }
     
     NSMutableDictionary* dict = [NSMutableDictionary dictionary];
     for (int i = 0; i < CFArrayGetCount(services); i++) {
         IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
         if (service == nil) continue;
         
         NSString* name = CFBridgingRelease(IOHIDServiceClientCopyProperty(service, CFSTR("Product")));
         
         IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, type, 0, 0);
         if (event == nil) continue;
         
         if (name && event) {
             double value = IOHIDEventGetFloatValue(event, IOHIDEventFieldBase(type));
             dict[name]=@(value);
         }
         
         CFRelease(event);
     }
     
     CFRelease(services);
     CFRelease(system);
     
     return dict;
 }
