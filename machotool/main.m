//
//  launchservicesd2dylib.m
//
//
//  Created by Duy Tran on 31/12/25.
//

@import Darwin;
@import MachO;
@import Foundation;
@import Security;
#import <assert.h>

CF_ENUM(uint32_t){
    kSecCSRequirementInformation = 1 << 2,
};
extern CFStringRef kSecCodeInfoEntitlementsDict;
typedef CFTypeRef SecStaticCodeRef;
typedef uint32_t SecCSFlags;
OSStatus SecCodeCopySigningInformation(SecStaticCodeRef codeRef, SecCSFlags flags, CFDictionaryRef *signingInfo);
OSStatus SecStaticCodeCreateWithPathAndAttributes(CFURLRef path, SecCSFlags flags, CFDictionaryRef attributes, SecStaticCodeRef* CF_RETURNS_RETAINED staticCode);
NSDictionary* dumpEntitlementsFromBinaryAtPath(NSString *binaryPath);
@interface NSDictionary(MPSOD_Additions)
- (NSDictionary *)mp_deepMerge:(NSDictionary *)other;
@end

typedef void (^LCParseMachOCallback)(const char *path, struct mach_header_64 *header, int fd, void* filePtr);
NSString *LCParseMachO(const char *path, bool readOnly, LCParseMachOCallback callback) {
    int fd = open(path, readOnly ? O_RDONLY : O_RDWR, (mode_t)readOnly ? 0400 : 0600);
    if (fd < 0) {
        return [NSString stringWithFormat:@"Failed to open %s: %s", path, strerror(errno)];
    }
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

int printHelp(const char *argv0) {
    fprintf(stderr, "Usage: %s <command> <path/to/launchservicesd>\n", argv0);
    fprintf(stderr, "commands:\n");
    fprintf(stderr, "  arm64      - Patch cpusubtype to arm64 architecture\n");
    fprintf(stderr, "  dylib      - Convert launchservicesd executable to dylib\n");
    fprintf(stderr, "  platform   - Change Mach-O platform\n");
    fprintf(stderr, "  sign       - Sign and merge entitlements\n");
    return 1;
}

int cmdSignEntitlements(int argc, const char **argv) {
    NSString *entitlementsPath = [NSProcessInfo.processInfo.arguments[0].stringByDeletingLastPathComponent stringByAppendingPathComponent:@"../entitlements.plist"];
    if (![NSFileManager.defaultManager fileExistsAtPath:entitlementsPath]) {
        fprintf(stderr, "Error: entitlements.plist not found at path: %s\n", entitlementsPath.UTF8String);
        return 1;
    }
    
    NSDictionary *entitlements = dumpEntitlementsFromBinaryAtPath(@(argv[2]));
    if (!entitlements) {
//        fprintf(stderr, "Error: failed to dump entitlements from binary: %s\n", argv[2]);
//        return 1;
        entitlements = @{};
    }
    NSDictionary *newEntitlements = [NSDictionary dictionaryWithContentsOfFile:entitlementsPath];
    if (!newEntitlements) {
        fprintf(stderr, "Error: failed to read entitlements from file: %s\n", entitlementsPath.UTF8String);
        return 1;
    }
    
    dlopen("/System/Library/Frameworks/MediaPlayer.framework/MediaPlayer", 0);
    NSDictionary *new = [entitlements mp_deepMerge:newEntitlements];
    NSData *plistData = [NSPropertyListSerialization dataWithPropertyList:new format:NSPropertyListXMLFormat_v1_0 options:0 error:nil];
    if (!plistData) {
        fprintf(stderr, "Error: failed to serialize merged entitlements\n");
        return 1;
    }
    NSString *tempEntitlementsPath = [NSString stringWithFormat:@"entitlements_%d.plist", getpid()];
    [plistData writeToFile:tempEntitlementsPath atomically:YES];
    
    // Forward to codesign
    int (*_system)(const char *) = dlsym(RTLD_DEFAULT, "system");
    int result = _system([[NSString stringWithFormat:@"codesign --force --preserve-metadata=identifier --entitlements \"%@\" -s - \"%@\"", tempEntitlementsPath, @(argv[2])] UTF8String]);
    [NSFileManager.defaultManager removeItemAtPath:tempEntitlementsPath error:nil];
    if (result != 0) {
        fprintf(stderr, "Error: codesign failed with exit code %d\n", result);
    }
    return result;
}

int main(int argc, const char **argv, const char **envp, const char **apple) {
    if (argc < 2) return printHelp(argv[0]);
    
    BOOL convertToArm64 = !strcmp(argv[1], "arm64");
    BOOL convertToDylib = !strcmp(argv[1], "dylib");
    BOOL changePlatform = !strcmp(argv[1], "platform");
    BOOL signEntitlements = !strcmp(argv[1], "sign");
    if (!convertToArm64 && !convertToDylib && !changePlatform && !signEntitlements) {
        fprintf(stderr, "Error: unknown command: %s\n", argv[1]);
        return printHelp(argv[0]);
    } else if (argc != 3) {
       fprintf(stderr, "Error: no file or more than one file specified\n");
       return printHelp(argv[0]);
    }
    
    if (signEntitlements) {
        return cmdSignEntitlements(argc, argv);
    }
    
    NSString *execPath = @(argv[2]);
    NSString *error = LCParseMachO(execPath.UTF8String, false, ^(const char *path, struct mach_header_64 *header, int fd, void* filePtr) {
        if(header->cputype == CPU_TYPE_ARM64) {
            if (convertToArm64) {
                if (header->cpusubtype & CPU_SUBTYPE_ARM64E) {
                    printf("Patching cpusubtype from arm64e to arm64\n");
                    header->cpusubtype = 0;
                } else {
                    printf("Nothing to do, cpusubtype is not arm64e\n");
                }
                return;
            }
            
            uint8_t *imageHeaderPtr = (uint8_t*)header + sizeof(struct mach_header_64);
            if (convertToDylib) {
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
            }
            
            struct load_command *command = (struct load_command *)imageHeaderPtr;
            for(int i = 0; i < header->ncmds; i++) {
                if (convertToDylib && command->cmd == LC_LOAD_DYLINKER) {
                    printf("Patching LC_LOAD_DYLINKER to LC_ID_DYLIB\n");
                    replaceDylinkerWithIDDylibCommand((struct dylinker_command*)command, path);
                    break;
                }
                if (changePlatform && command->cmd == LC_BUILD_VERSION) {
                    printf("Found LC_BUILD_VERSION, modifying the load command\n");
                    struct build_version_command *buildver = (struct build_version_command *)command;
                    if (buildver->platform != 0x2) { // macOS
                        printf("Nothing to do, platform is not iOS\n");
                        break;
                    }
                    buildver->platform = 0x1; // set to macOS
                    int minos = buildver->minos >> 16;
                    if (minos < 26) {
                        buildver->minos = MAX(11, minos - 3) << 16;
                    }
                    int sdk = buildver->sdk >> 16;
                    if (sdk < 26) {
                        buildver->sdk = MAX(11, sdk - 3) << 16;
                    }
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

// from TrollStore
SecStaticCodeRef getStaticCodeRef(NSString *binaryPath) {
    if(binaryPath == nil) return NULL;
    
    CFURLRef binaryURL = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef)binaryPath, kCFURLPOSIXPathStyle, false);
    if(binaryURL == NULL) {
        NSLog(@"[getStaticCodeRef] failed to get URL to binary %@", binaryPath);
        return NULL;
    }
    
    SecStaticCodeRef codeRef = NULL;
    OSStatus result;
    
    result = SecStaticCodeCreateWithPathAndAttributes(binaryURL, 0, NULL, &codeRef);
    
    CFRelease(binaryURL);
    
    if(result != errSecSuccess) {
        NSLog(@"[getStaticCodeRef] failed to create static code for binary %@", binaryPath);
        return NULL;
    }
        
    return codeRef;
}

NSDictionary* dumpEntitlements(SecStaticCodeRef codeRef) {
    if(codeRef == NULL) {
        NSLog(@"[dumpEntitlements] attempting to dump entitlements without a StaticCodeRef");
        return nil;
    }
    
    CFDictionaryRef signingInfo = NULL;
    OSStatus result;
    
    result = SecCodeCopySigningInformation(codeRef, kSecCSRequirementInformation, &signingInfo);
    
    if(result != errSecSuccess) {
        NSLog(@"[dumpEntitlements] failed to copy signing info from static code");
        return nil;
    }
    
    NSDictionary *entitlementsNSDict = nil;
    
    CFDictionaryRef entitlements = CFDictionaryGetValue(signingInfo, kSecCodeInfoEntitlementsDict);
    if(entitlements == NULL) {
        NSLog(@"[dumpEntitlements] no entitlements specified");
    } else if(CFGetTypeID(entitlements) != CFDictionaryGetTypeID()) {
        NSLog(@"[dumpEntitlements] invalid entitlements");
    } else {
        entitlementsNSDict = (__bridge NSDictionary *)(entitlements);
        NSLog(@"[dumpEntitlements] dumped %@", entitlementsNSDict);
    }
    
    CFRelease(signingInfo);
    return entitlementsNSDict;
}

NSDictionary* dumpEntitlementsFromBinaryAtPath(NSString *binaryPath) {
    // This function is intended for one-shot checks. Main-event functions should retain/release their own SecStaticCodeRefs
    
    if(binaryPath == nil) return nil;
    
    SecStaticCodeRef codeRef = getStaticCodeRef(binaryPath);
    if(codeRef == NULL) return nil;
    
    NSDictionary *entitlements = dumpEntitlements(codeRef);
    CFRelease(codeRef);

    return entitlements;
}
