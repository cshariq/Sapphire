//
//  SapphireMemoryFlush.h
//  Sapphire
//
//  Low-level memory reclamation helpers. These mirror what mlx-swift's
//  ObjC++ allocator does in `mlx/backend/metal/allocator.cpp` (see
//  https://github.com/ml-explore/mlx-swift) when it clears its GPU buffer
//  cache, done at the ObjC layer because that is where the autorelease
//  pools, malloc zones and IOSurface handles actually live:
//
//  - mlx wraps every Metal allocation/deallocation in a scoped
//    NSAutoreleasePool (`metal::new_scoped_memory_pool()`) so autoreleased
//    ObjC objects are released immediately instead of lingering in the
//    thread's pool. SapphireMemoryDrainAutoreleasePools() is the same
//    push/pop discipline for the app's teardown paths.
//
//  - mlx returns cached buffers to the system allocator, which then gives
//    the pages back. SapphireMemoryFlushAllMallocZones() relieves *every*
//    malloc zone (Swift's `malloc_zone_pressure_relief(nil, 0)` only hits
//    the default zone), so Core ML / Core Image / ObjC runtime allocations
//    from other zones can also return their free pages.
//
//  - mlx deallocates its recycled GPU buffers for real on clear. The app's
//    closest analog is IOSurface-backed CVPixelBuffers (camera copies,
//    inference targets), which stay wired in the GPU/IOKit driver until the
//    surface is marked purgeable or released. SapphireMemoryMarkPixelBufferPurgeable()
//    marks a buffer's surface empty so the OS reclaims the pages.
//
//  - mlx's buffer pool keeps recycled buffers alive by design; its
//    `clear_cache()` releases every pooled buffer. SapphireMemoryFlushPixelBufferPool()
//    does the same for the camera's CVPixelBufferPool by flushing every
//    unused buffer regardless of age.
//

#import <Foundation/Foundation.h>
#import <CoreVideo/CoreVideo.h>

NS_ASSUME_NONNULL_BEGIN

/// Push and pop autorelease pools immediately so autoreleased ObjC objects
/// created by Metal / Core Video / Core Image calls are released now, not on
/// the next run loop turn (mlx's scoped-memory-pool pattern).
FOUNDATION_EXPORT void SapphireMemoryDrainAutoreleasePools(void);

/// Call `malloc_zone_pressure_relief(zone, 0)` on every malloc zone of the
/// process, not just the default zone.
FOUNDATION_EXPORT void SapphireMemoryFlushAllMallocZones(void);

/// Mark an IOSurface-backed CVPixelBuffer's pages as reclaimable (Empty).
/// Returns true when the buffer was IOSurface-backed and the state change
/// succeeded. Only call this when about to drop the last references.
FOUNDATION_EXPORT bool SapphireMemoryMarkPixelBufferPurgeable(CVPixelBufferRef buffer);

/// Free every unused buffer in a pixel buffer pool (all ages), so pooled
/// camera / inference frame storage is returned instead of recycled.
FOUNDATION_EXPORT void SapphireMemoryFlushPixelBufferPool(CVPixelBufferPoolRef pool);

NS_ASSUME_NONNULL_END