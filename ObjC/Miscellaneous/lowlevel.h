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
bool preventSleepAssertionsAreActive(void);

bool setClamshellSleepDisabled(bool disabled);
bool clamshellSleepDisabledIsActive(void);

#endif /* lowlevel_h */
