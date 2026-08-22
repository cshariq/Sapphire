//
//  SapphireMemoryFlush.m
//  Sapphire
//
//  See SapphireMemoryFlush.h for the intent — these are the Objective-C
//  counterparts of the memory-cache clearing mlx-swift performs in its
//  ObjC++ Metal allocator (`mlx/backend/metal/allocator.cpp`).
//

#import "SapphireMemoryFlush.h"
#import <malloc/malloc.h>
#import <mach/mach.h>
#import <IOSurface/IOSurface.h>

void SapphireMemoryDrainAutoreleasePools(void) {
    @autoreleasepool {
    }
    @autoreleasepool {
    }
}

void SapphireMemoryFlushAllMallocZones(void) {
    // Enumerate every malloc zone in the process. `malloc_get_all_zones`
    // is declared in <malloc/malloc.h>; reading with a NULL reader works
    // for the current task.
    vm_address_t *zones = NULL;
    unsigned int zoneCount = 0;
    if (malloc_get_all_zones(mach_task_self(), NULL, &zones, &zoneCount) == KERN_SUCCESS && zones != NULL) {
        for (unsigned int i = 0; i < zoneCount; i++) {
            malloc_zone_t *zone = (malloc_zone_t *)zones[i];
            if (zone != NULL) {
                malloc_zone_pressure_relief(zone, 0);
            }
        }
    }

    // Always hit the default zone even if enumeration failed.
    malloc_zone_pressure_relief(malloc_default_zone(), 0);
}

bool SapphireMemoryMarkPixelBufferPurgeable(CVPixelBufferRef buffer) {
    if (buffer == NULL) {
        return false;
    }
    IOSurfaceRef surface = CVPixelBufferGetIOSurface(buffer);
    if (surface == NULL) {
        return false;
    }
    IOSurfacePurgeabilityState oldState = kIOSurfacePurgeableNonVolatile;
    kern_return_t result = IOSurfaceSetPurgeable(surface, kIOSurfacePurgeableEmpty, &oldState);
    return result == KERN_SUCCESS;
}

void SapphireMemoryFlushPixelBufferPool(CVPixelBufferPoolRef pool) {
    if (pool == NULL) {
        return;
    }
    CVPixelBufferPoolFlush(pool, kCVPixelBufferPoolFlushExcessBuffers);
}