//
//  lowlevel.c
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//


#include "lowlevel.h"
#include <IOKit/pwr_mgt/IOPMLib.h>
#include <IOKit/IOKitLib.h>
#include <dlfcn.h>

void wakeDisplay(void)
{
    static IOPMAssertionID assertionID;
    IOPMAssertionDeclareUserActivity(CFSTR("BLEUnlock"), kIOPMUserActiveLocal, &assertionID);
}

void sleepDisplay(void)
{
    io_registry_entry_t reg = IORegistryEntryFromPath(kIOMasterPortDefault, "IOService:/IOResources/IODisplayWrangler");
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
