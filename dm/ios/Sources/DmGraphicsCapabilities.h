// Query the actual device before offering a MetalFX path. Capability alone is
// not an implementation: interpolation still needs matched color/depth/motion
// history and correct presentation pacing; temporal upscaling needs jitter.
#pragma once
// MetalFX is iOS 16 and later. A build whose minimum is lower does not link it at all
// (a required MetalFX dylib would stop the app on iOS 15), so the query is compiled out.
#if TARGET_OS_OSX || __IPHONE_OS_VERSION_MIN_REQUIRED >= 160000
#import <MetalFX/MetalFX.h>
#endif

static inline void dm_graphics_capabilities(id<MTLDevice> device) {
#if TARGET_OS_OSX || __IPHONE_OS_VERSION_MIN_REQUIRED >= 160000
    int spatial = 0, temporal = 0, interpolation = 0, interpolation4 = 0;
    if (@available(iOS 16.0, macOS 13.0, *)) {
        spatial = [MTLFXSpatialScalerDescriptor supportsDevice:device];
        temporal = [MTLFXTemporalScalerDescriptor supportsDevice:device];
    }
    if (@available(iOS 26.0, macOS 26.0, *)) {
        interpolation = [MTLFXFrameInterpolatorDescriptor supportsDevice:device];
        interpolation4 = [MTLFXFrameInterpolatorDescriptor supportsMetal4FX:device];
    }
    LOG("graphics capabilities: device=%s MetalFX spatial=%d temporal=%d frame_interpolation=%d frame_interpolation_metal4=%d; interpolation integration pending",
        device.name.UTF8String, spatial, temporal, interpolation, interpolation4);
#else
    LOG("graphics capabilities: device=%s MetalFX needs iOS 16; this build's minimum is lower", device.name.UTF8String);
#endif
}
