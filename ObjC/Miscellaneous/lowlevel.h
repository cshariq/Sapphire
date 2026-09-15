//
//  lowlevel.c
//  Sapphire
//
//  Created by Shariq Charolia on 2025-09-13.
//


#ifndef lowlevel_h
#define lowlevel_h
#include <stdbool.h>

void sleepDisplay(void);
void wakeDisplay(void);
int SACLockScreenImmediate(void);

bool acquirePreventSleepAssertions(void);
void releasePreventSleepAssertions(void);
bool acquirePreventSystemSleepOnlyAssertion(void);
bool preventSleepAssertionsAreActive(void);

bool setClamshellSleepDisabled(bool disabled);
bool clamshellSleepDisabledIsActive(void);

// Delivers a real IOKit event whenever IOPMrootDomain reports the lid has
// opened or closed, instead of having callers poll for the state. Callback
// fires on the main run loop. Returns false if IOPMrootDomain (or its
// interest notification) could not be reached, in which case callers should
// fall back to polling.
typedef void (*ClamshellStateChangeCallback)(bool isClosed);
bool startClamshellStateNotifications(ClamshellStateChangeCallback callback);
void stopClamshellStateNotifications(void);

#endif /* lowlevel_h */
