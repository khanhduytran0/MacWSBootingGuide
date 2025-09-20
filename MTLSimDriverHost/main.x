@import Darwin;
@import Foundation;
@import Metal;
#include <rootless.h>

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

// decompiled from MTLSimDriverHost.xpc with some modifications
xpc_connection_t xpc_connection_create_listener(const char* name, dispatch_queue_t queue);
xpc_connection_t xpc_connection_create_mach_service(const char *name, dispatch_queue_t targetq, uint64_t flags);
int main(int argc, const char **argv, const char **envp) {
    xpc_object_t (*xpc_connection_create_mach_service)(const char *name, dispatch_queue_t targetq, uint64_t flags) = dlsym(RTLD_DEFAULT, "xpc_connection_create_mach_service");
    xpc_connection_t peerConnection = xpc_connection_create_mach_service("com.apple.metal.simulator", dispatch_get_main_queue(), XPC_CONNECTION_MACH_SERVICE_LISTENER);
    dispatch_async(dispatch_get_main_queue(), ^{
        char *frameworkPath = JBROOT_PATH("/usr/macOS/Frameworks/MTLSimImplementation.framework/MTLSimImplementation");
        void *handle = dlopen(frameworkPath, RTLD_GLOBAL);
        NSCAssert(handle, @"Failed to load MTLSimImplementation framework: %s", dlerror());
        void (*init_with_xpc_connection)(xpc_connection_t, uint64_t, uint64_t) = dlsym(handle, "init_with_xpc_connection");
        init_with_xpc_connection(peerConnection, MTLCreateSystemDefaultDevice().registryID, 0LL);
    });
    dispatch_main();
}
