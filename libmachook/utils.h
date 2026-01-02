@import Darwin;
#import "xpc.h"

void ModifyExecutableRegion(void *addr, size_t size, void(^callback)(void));
