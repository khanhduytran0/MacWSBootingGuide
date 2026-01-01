//
//  launchservicesd.m
//  
//
//  Created by Duy Tran on 3/8/25.
//

@import Darwin;
@import MachO;
#import <assert.h>

void *dlopen_entry_point(const char *path, int flags) {
    int index = _dyld_image_count();
    void *handle = dlopen(path, flags);
    if(!handle) {
        printf("Failed to load launchservicesd.dylib: %s\n", dlerror());
        return NULL;
    }
    
    uint32_t entryoff = 0;
    const struct mach_header_64 *header = (struct mach_header_64 *)_dyld_get_image_header(index);
    uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
    struct load_command *command = (struct load_command *)imageHeaderPtr;
    for(int i = 0; i < header->ncmds; ++i) {
        if(command->cmd == LC_MAIN) {
            struct entry_point_command ucmd = *(struct entry_point_command *)imageHeaderPtr;
            entryoff = ucmd.entryoff;
            break;
        }
        imageHeaderPtr += command->cmdsize;
        command = (struct load_command *)imageHeaderPtr;
    }
    assert(entryoff > 0);
    return (void *)header + entryoff;
}

int main(int argc, const char **argv, const char **envp, const char **apple) {
    int( *original_main)(int argc, const char **argv, const char **envp, const char **apple) = dlopen_entry_point("@loader_path/launchservicesd.dylib", RTLD_GLOBAL);
    __attribute__((musttail))return original_main(argc, argv, envp, apple);
}
