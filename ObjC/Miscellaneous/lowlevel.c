//
//  lowlevel.c
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//


#include "lowlevel.h"
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/pwr_mgt/IOPMLibDefs.h>
#include <IOKit/IOKitLib.h>
#include <mach/mach.h>
#include <dlfcn.h>
#include <stdbool.h>

static IOPMAssertionID userIdleSystemSleepAssertionID = 0;
static IOPMAssertionID userIdleDisplaySleepAssertionID = 0;
static bool clamshellSleepDisabledActive = false;

static IOReturn rootDomain_setDisableClamShellSleep(io_connect_t connection, bool disable)
{
    uint32_t num_outputs = 0;
    uint64_t input = disable ? 1 : 0;
    return IOConnectCallScalarMethod(
        connection,
        kPMSetClamshellSleepState,
        &input,
        1,
        NULL,
        &num_outputs
    );
}

bool setClamshellSleepDisabled(bool disabled)
{
    io_service_t pmRootDomain = IOServiceGetMatchingService(
        kIOMainPortDefault,
        IOServiceMatching("IOPMrootDomain")
    );
    if (pmRootDomain == IO_OBJECT_NULL) {
        return false;
    }

    io_connect_t connection = IO_OBJECT_NULL;
    IOReturn openResult = IOServiceOpen(pmRootDomain, mach_task_self(), 0, &connection);
    IOObjectRelease(pmRootDomain);

    if (openResult != kIOReturnSuccess || connection == IO_OBJECT_NULL) {
        return false;
    }

    IOReturn result = rootDomain_setDisableClamShellSleep(connection, disabled);
    IOServiceClose(connection);

    if (result == kIOReturnSuccess) {
        clamshellSleepDisabledActive = disabled;
        return true;
    }

    return false;
}

bool clamshellSleepDisabledIsActive(void)
{
    return clamshellSleepDisabledActive;
}

bool acquirePreventSleepAssertions(void)
{
    bool anySuccess = false;
    IOReturn result;

    if (userIdleSystemSleepAssertionID == 0) {
        result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleSystemSleep,
            kIOPMAssertionLevelOn,
            CFSTR("Sapphire Caffeinate"),
            &userIdleSystemSleepAssertionID
        );
        anySuccess = anySuccess || (result == kIOReturnSuccess);
    } else {
        anySuccess = true;
    }

    if (userIdleDisplaySleepAssertionID == 0) {
        result = IOPMAssertionCreateWithName(
            kIOPMAssertPreventUserIdleDisplaySleep,
            kIOPMAssertionLevelOn,
            CFSTR("Sapphire Caffeinate"),
            &userIdleDisplaySleepAssertionID
        );
        anySuccess = anySuccess || (result == kIOReturnSuccess);
    } else {
        anySuccess = true;
    }

    return anySuccess;
}

void releasePreventSleepAssertions(void)
{
    if (userIdleSystemSleepAssertionID != 0) {
        IOPMAssertionRelease(userIdleSystemSleepAssertionID);
        userIdleSystemSleepAssertionID = 0;
    }
    if (userIdleDisplaySleepAssertionID != 0) {
        IOPMAssertionRelease(userIdleDisplaySleepAssertionID);
        userIdleDisplaySleepAssertionID = 0;
    }
}

bool preventSleepAssertionsAreActive(void)
{
    return userIdleSystemSleepAssertionID != 0
        || userIdleDisplaySleepAssertionID != 0;
}

void wakeDisplay(void)
{
    static IOPMAssertionID assertionID;
    IOPMAssertionDeclareUserActivity(CFSTR("BLEUnlock"), kIOPMUserActiveLocal, &assertionID);
}

void sleepDisplay(void)
{
    io_registry_entry_t reg = IORegistryEntryFromPath(kIOMainPortDefault, "IOService:/IOResources/IODisplayWrangler");
    if (reg) {
        IORegistryEntrySetCFProperty(reg, CFSTR("IORequestIdle"), kCFBooleanTrue);
        IOObjectRelease(reg);
    }
}

// This function uses dlsym to find the private SACLockScreenImmediate function at runtime.
int SACLockScreenImmediate(void) {
    void *sac = dlopen("/System/Library/PrivateFrameworks/login.framework/login", RTLD_LAZY);
    if (!sac) return -1;
    
    int (*SACLockScreenImmediate)(void) = dlsym(sac, "SACLockScreenImmediate");
    if (!SACLockScreenImmediate) return -1;
    
    return SACLockScreenImmediate();
}
