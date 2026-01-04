@import Darwin;

void ModifyExecutableRegion(void *addr, size_t size, void(^callback)(void));
