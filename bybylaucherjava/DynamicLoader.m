#import "DYNAMIC_LOADER.h"
#include <sys/mman.h>
#include <string.h>
#include <ffi.h>

@implementation DynamicLoader

+ (void *)loadCode:(const void *)code size:(size_t)size {
    if (!code || size == 0) return NULL;

    void *mem = mmap(NULL, size, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE, -1, 0);

    if (mem == MAP_FAILED) return NULL;

    memcpy(mem, code, size);
    return mem;
}

+ (void)callFunction:(void *)func args:(void **)args {
    if (!func) return;

    ffi_cif cif;
    ffi_type *argTypes[] = { &ffi_type_pointer };
    void *values[] = { args };

    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_void, argTypes) == FFI_OK) {
        ffi_call(&cif, FFI_FN(func), NULL, values);
    }
}

@end
