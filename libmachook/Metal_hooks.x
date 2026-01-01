@import CydiaSubstrate;
@import Darwin;
@import Foundation;
@import Metal;
#import <rootless.h>
#import "utils.h"

void swizzle2(Class class, SEL originalAction, Class class2, SEL swizzledAction) {
    Method m1 = class_getInstanceMethod(class2, swizzledAction);
    if(class_getInstanceMethod(class, originalAction) == NULL) {
        class_addMethod(class, originalAction, method_getImplementation(m1), method_getTypeEncoding(m1));
    } else {
        class_addMethod(class, swizzledAction, method_getImplementation(m1), method_getTypeEncoding(m1));
        method_exchangeImplementations(class_getInstanceMethod(class, originalAction), class_getInstanceMethod(class, swizzledAction));
    }
}

@interface _MTLDevice : NSObject
- (uint32_t)acceleratorPort;
@end

@implementation _MTLDevice(MetalXPC)
- (void)_setAcceleratorService:(id)arg1 {}

- (uint32_t)peerGroupID {
    return self.acceleratorPort;
}
@end

static id(*MTLCreateSimulatorDevice)(void);
@interface MTLFakeDevice : _MTLDevice
@end
@implementation MTLFakeDevice
- (BOOL)initHooks {
    if(%c(MTLSimDevice)) {
        return YES; // Already hooked
    }
    
    void *handle = dlopen("@loader_path/../Frameworks/MetalSerializer.framework/MetalSerializer", RTLD_GLOBAL);
    if(!handle) {
        NSLog(@"Failed to load MetalSerializer framework: %s", dlerror());
        return NO;
    }
    
    handle = dlopen("@loader_path/../Frameworks/MTLSimDriver.framework/MTLSimDriver", RTLD_GLOBAL);
    if(!handle) {
        NSLog(@"Failed to load MTLSimDriver framework: %s", dlerror());
        return NO;
    }
    MTLCreateSimulatorDevice = dlsym(handle, "MTLCreateSimulatorDevice");
    
    Class MTLSimDeviceClass = %c(MTLSimDevice);
    swizzle2(MTLSimDeviceClass, @selector(newBufferWithBytesNoCopy:length:options:deallocator:), MTLFakeDevice.class, @selector(hooked_newBufferWithBytesNoCopy:length:options:deallocator:));
    swizzle2(MTLSimDeviceClass, @selector(newBufferWithLength:options:pointer:copyBytes:deallocator:), MTLFakeDevice.class, @selector(hooked_newBufferWithLength:options:pointer:copyBytes:deallocator:));
    swizzle2(MTLSimDeviceClass, @selector(acceleratorPort), MTLFakeDevice.class, @selector(hooked_acceleratorPort));
    swizzle2(MTLSimDeviceClass, @selector(location), MTLFakeDevice.class, @selector(hooked_location));
    swizzle2(MTLSimDeviceClass, @selector(locationNumber), MTLFakeDevice.class, @selector(hooked_locationNumber));
    swizzle2(MTLSimDeviceClass, @selector(maxTransferRate), MTLFakeDevice.class, @selector(hooked_maxTransferRate));
    
    uint32_t *imp;
    // This check isn't present in iOS 14 simulator, maybe it was added in iOS 15?
    // Patch -[MTLSimTexture initWithDescriptor:decompressedPixelFormat:iosurface:plane:textureRef:heap:device:] to bypass `IOSurface backed XR10 textures are not supported in the simulator`
    imp = (uint32_t *)method_getImplementation(class_getInstanceMethod(%c(MTLSimTexture), @selector(initWithDescriptor:decompressedPixelFormat:iosurface:plane:textureRef:heap:device:)));
    for(int i = 0; i < 50; i++) {
        //    MTLSimDriver[0xfb7c] <+144>: bl     0x2e660        ; objc_msgSend$pixelFormat
        // -> MTLSimDriver[0xfb80] <+148>: and    x8, x0, #0xfffffffffffffffc
        // -> MTLSimDriver[0xfb84] <+152>: cmp    x8, #0x228
        // -> MTLSimDriver[0xfb88] <+156>: b.eq   0xfdf8         ; <+780>
        if(imp[i] == 0x927ef408 && imp[i+1] == 0xf108a11f) {
            ModifyExecutableRegion(imp, sizeof(uint32_t[3]), ^{
                imp[i+1] = imp[i+2] = 0xd503201f; // nop
            });
            break;
        }
    }
    
    // Patch -[MTLSimBuffer newTextureWithDescriptor:offset:bytesPerRow:] to bypass `Linear texture can only be created on buffers with MTLStorageModePrivate in the simulator`
    imp = (uint32_t *)method_getImplementation(class_getInstanceMethod(%c(MTLSimBuffer), @selector(newTextureWithDescriptor:offset:bytesPerRow:)));
    for(int i = 0; i < 50; i++) {
        //    MTLSimDriver[0x85bc] <+84>:  bl     0x2eda0        ; objc_msgSend$storageMode
        // -> MTLSimDriver[0x85c0] <+88>:  cmp    x0, #0x2
        //    MTLSimDriver[0x85c4] <+92>:  b.ne   0x8798         ; <+560>
        if(imp[i] == 0xf100081f) {
            ModifyExecutableRegion(imp, sizeof(uint32_t), ^{
                imp[i] = imp[i+1] = 0xd503201f; // nop
            });
            break;
        }
    }
    
    return YES;
}

- (id)initWithAcceleratorPort:(int)port {
    if(![self initHooks]) {
        return nil;
    }
    if(!MTLCreateSimulatorDevice) {
        NSLog(@"Failed to find MTLCreateSimulatorDevice: %s", dlerror());
        return nil;
    }
    self = MTLCreateSimulatorDevice();
    objc_setAssociatedObject(self, @selector(acceleratorPort), @(port), OBJC_ASSOCIATION_ASSIGN);
    return self;
}

- (uint32_t)hooked_acceleratorPort {
    return ((NSNumber *)objc_getAssociatedObject(self, @selector(acceleratorPort))).unsignedIntValue;
}

- (NSUInteger)hooked_location {
    return 0; // MTLDeviceLocationBuiltIn
}

- (NSUInteger)hooked_locationNumber {
    return 0;
}

- (NSUInteger)hooked_maxTransferRate {
    return 0; // The maximum transfer rate for built-in GPUs is 0.
}

- (id<MTLBuffer>)hooked_newBufferWithBytesNoCopy:(void *)bytes length:(NSUInteger)length options:(MTLResourceOptions)options deallocator:(void (^)(void * pointer, NSUInteger length)) deallocator {
    if(malloc_size(bytes) > 0) {
        // XPC doesn't like malloced buffers since they don't have MAP_SHARED flag, so we mirror it to a shared region here
        vm_address_t mirrored = 0;
        vm_prot_t cur_prot, max_prot;
        kern_return_t ret = vm_remap(mach_task_self(), &mirrored, length, 0, VM_FLAGS_ANYWHERE, mach_task_self(), (vm_address_t)bytes, false, &cur_prot, &max_prot, VM_INHERIT_SHARE);
        if(ret != KERN_SUCCESS) {
            NSLog(@"Failed to mirror memory: %s", mach_error_string(ret));
            return nil;
        }
        vm_protect(mach_task_self(), mirrored, length, NO,
                VM_PROT_READ | VM_PROT_WRITE);
        
        return [self hooked_newBufferWithBytesNoCopy:(void *)mirrored length:length options:options deallocator:^(void * _Nonnull pointer, NSUInteger length) {
            vm_deallocate(mach_task_self(), (vm_address_t)pointer, length);
            if(deallocator) deallocator(bytes, length);
        }];
    } else {
        return [self hooked_newBufferWithBytesNoCopy:bytes length:length options:options deallocator:deallocator];
    }
}

- (id<MTLBuffer>)hooked_newBufferWithLength:(NSUInteger)length options:(MTLResourceOptions)options pointer:(void *)pointer copyBytes:(BOOL)copyBytes deallocator:(void (^)(void * pointer, NSUInteger length))deallocator {
    // Handle MTLResourceStorageModeManaged
    if(options & (1 << MTLResourceStorageModeShift)) {
        options &= ~(1 << MTLResourceStorageModeShift);
        options |= MTLResourceStorageModeShared;
    }
    return [self hooked_newBufferWithLength:length options:options pointer:pointer copyBytes:copyBytes deallocator:deallocator];
}
@end
%hookf(Class, getMetalPluginClassForService, int service) {
#ifdef FORCE_M1_DRIVER
    NSBundle *bundle = [NSBundle bundleWithPath:@"/System/Library/Extensions/AGXMetalG16G_B0.bundle"];
    [bundle load];
    return %c(AGXG16GDevice);
#else
    return MTLFakeDevice.class;
#endif
}

@interface MTLTextureDescriptorInternal : MTLTextureDescriptor
@end
%hook MTLTextureDescriptorInternal
- (MTLStorageMode)storageMode {
    MTLStorageMode mode = %orig;
    if(mode == 1) { // MTLStorageModeManaged
        self.storageMode = MTLStorageModeShared;
        return MTLStorageModeShared;
    }
    return mode;
}
%end

const char *metalSimService = "com.apple.metal.simulator";
xpc_connection_t (*orig_xpc_connection_create_mach_service)(const char * name, dispatch_queue_t targetq, uint64_t flags);
xpc_connection_t hooked_xpc_connection_create_mach_service(const char * name, dispatch_queue_t targetq, uint64_t flags) {
    flags &= ~XPC_CONNECTION_MACH_SERVICE_PRIVILEGED;
    if(!strncmp(name, metalSimService, strlen(metalSimService))) {
        return xpc_connection_create(metalSimService, 0);
    }
    return orig_xpc_connection_create_mach_service(name, targetq, flags);
}

extern int xpc_connection_enable_sim2host_4sim();
%hookf(int, xpc_connection_enable_sim2host_4sim) {
    return 0;
}

__attribute__((constructor)) static void InitMetalHooks() {
#ifndef FORCE_M1_DRIVER
    dispatch_async(dispatch_get_main_queue(), ^{
        // force Apple 5 profile
        CFPreferencesSetAppValue((const CFStringRef)@"EnableSimApple5", (__bridge CFPropertyListRef)@(YES), (const CFStringRef)@"com.apple.Metal");
    });
#endif
    
    MSImageRef sys = MSGetImageByName("/System/Library/Frameworks/Metal.framework/Metal");
    %init(getMetalPluginClassForService = MSFindSymbol(sys, "_getMetalPluginClassForService"));
    
    MSImageRef xpc = MSGetImageByName("/usr/lib/system/libxpc.dylib");
    MSHookFunction(MSFindSymbol(xpc, "_xpc_connection_create_mach_service"), hooked_xpc_connection_create_mach_service, (void *)&orig_xpc_connection_create_mach_service);
#ifndef FORCE_M1_DRIVER
    // register MTLSimDriverHost.xpc
    char *frameworkPath = JBROOT_PATH("/usr/macOS/Frameworks/MTLSimDriver.framework/XPCServices/MTLSimDriverHost.xpc");
    xpc_add_bundle(frameworkPath, 2);
#endif
}
