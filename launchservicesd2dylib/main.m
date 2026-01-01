//
//  launchservicesd2dylib.m
//
//
//  Created by Duy Tran on 31/12/25.
//

@import Darwin;
@import MachO;
@import Foundation;
#import <assert.h>

typedef void (^LCParseMachOCallback)(const char *path, struct mach_header_64 *header, int fd, void* filePtr);
NSString *LCParseMachO(const char *path, bool readOnly, LCParseMachOCallback callback) {
    int fd = open(path, readOnly ? O_RDONLY : O_RDWR, (mode_t)readOnly ? 0400 : 0600);
    struct stat s;
    fstat(fd, &s);
    void *map = mmap(NULL, s.st_size, readOnly ? PROT_READ : (PROT_READ | PROT_WRITE), readOnly ? MAP_PRIVATE : MAP_SHARED, fd, 0);
    if (map == MAP_FAILED) {
        return [NSString stringWithFormat:@"Failed to map %s: %s", path, strerror(errno)];
    }

    uint32_t magic = *(uint32_t *)map;
    if (magic == FAT_CIGAM) {
        // Find compatible slice
        struct fat_header *header = (struct fat_header *)map;
        struct fat_arch *arch = (struct fat_arch *)(map + sizeof(struct fat_header));
        for (int i = 0; i < OSSwapInt32(header->nfat_arch); i++) {
            if (OSSwapInt32(arch->cputype) == CPU_TYPE_ARM64) {
                callback(path, (struct mach_header_64 *)(map + OSSwapInt32(arch->offset)), fd, map);
            }
            arch = (struct fat_arch *)((void *)arch + sizeof(struct fat_arch));
        }
    } else if (magic == MH_MAGIC_64 || magic == MH_MAGIC) {
        callback(path, (struct mach_header_64 *)map, fd, map);
    } else {
        return @"Not a Mach-O file";
    }

    msync(map, s.st_size, MS_SYNC);
    munmap(map, s.st_size);
    close(fd);
    return nil;
}
void replaceDylinkerWithIDDylibCommand(struct dylinker_command* dylinkerCommand, const char *path) {
    uint32_t size = dylinkerCommand->cmdsize;
    struct dylib_command* newDylibCommand = (struct dylib_command*)dylinkerCommand;
    newDylibCommand->cmd = LC_ID_DYLIB;

    newDylibCommand->dylib.name.offset = sizeof(struct dylib_command);
    newDylibCommand->dylib.compatibility_version = 0x10000;
    newDylibCommand->dylib.current_version = 0x10000;
    newDylibCommand->dylib.timestamp = 2;
    uint32_t nameSize = size - sizeof(struct dylib_command);
    // we only have 8 bytes to use
    const char* name = basename((char *)path);
    strncpy((void *)newDylibCommand + newDylibCommand->dylib.name.offset, name, nameSize);
    *((char *)newDylibCommand + newDylibCommand->dylib.name.offset + nameSize - 1) = 0;
}

int main(int argc, const char **argv, const char **envp, const char **apple) {
    if (argc != 2) {
        fprintf(stderr, "Usage: %s <path/to/launchservicesd>\n", argv[0]);
        return 1;
    }
    NSString *execPath = @(argv[1]);
    NSString *error = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
        if(header->cputype == CPU_TYPE_ARM64) {
            uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
            int ans = 0;
            // Literally convert an executable to a dylib
            if (header->magic == MH_MAGIC_64) {
                //assert(header->flags & MH_PIE);
                header->filetype = MH_DYLIB;
                header->flags |= MH_NO_REEXPORTED_DYLIBS;
                header->flags &= ~MH_PIE;
            }
            
            // Patch __PAGEZERO to map just a single zero page, fixing "out of address space"
            struct segment_command_64 *seg = (struct segment_command_64 *)imageHeaderPtr;
            assert(seg->cmd == LC_SEGMENT_64 || seg->cmd == LC_ID_DYLIB);
            if (seg->cmd == LC_SEGMENT_64 && seg->vmaddr == 0) {
                seg->vmaddr = 0x100000000 - 0x4000;
                seg->vmsize = 0x4000;
            }
            
            struct load_command *command = (struct load_command *)imageHeaderPtr;
            for(int i = 0; i < header->ncmds; i++) {
                if (command->cmd == LC_LOAD_DYLINKER) {
                    printf("Patching LC_LOAD_DYLINKER to LC_ID_DYLIB in %s\n", path);
                    replaceDylinkerWithIDDylibCommand((struct dylinker_command*)command, path);
                    break;
                }
                command = (struct load_command *)((void *)command + command->cmdsize);
            }
        }
    });
    if (error) {
        fprintf(stderr, "Error: %s\n", error.UTF8String);
        return 1;
    }
    printf("Done\n");
    return 0;
}
