@import CydiaSubstrate;
@import Darwin;
#import <assert.h>

void ModifyExecutableRegion(void *addr, size_t size, void(^callback)(void)) {
    vm_protect(mach_task_self(), (vm_address_t)addr, size, false, PROT_READ | PROT_WRITE | VM_PROT_COPY);
    callback();
    vm_protect(mach_task_self(), (vm_address_t)addr, size, false, PROT_READ | PROT_EXEC);
}

%ctor {
    dlopen("/System/Library/PrivateFrameworks/MTLCompiler.framework/MTLCompiler", RTLD_GLOBAL);
    MSImageRef image = MSGetImageByName("/System/Library/PrivateFrameworks/MTLCompiler.framework/MTLCompiler");
    assert(image);
    uint32_t *symbol = MSFindSymbol(image, "__ZN17MTLCompilerObject27readModuleFromBinaryRequestERK20ReadModuleParametersRN4llvm11LLVMContextEP15MTLFunctionTypePPvPmb");
    assert(symbol);
    
    // 0x1eaaa17c4 <+608>:  ldr    w8, [sp, #0x84]
    // 0x1eaaa17c8 <+612>:  cmp    w8, #0x7
    // 0x1eaaa17cc <+616>:  b.ne   0x1eaaa1840 (throws "Target OS is incompatible.")
    while(symbol[0] != 0x71001d1f) {
        symbol++;
    }
    ModifyExecutableRegion(symbol, sizeof(uint32_t), ^{
        symbol[0] = 0x6b08011f; // cmp w8, w8
    });
}
