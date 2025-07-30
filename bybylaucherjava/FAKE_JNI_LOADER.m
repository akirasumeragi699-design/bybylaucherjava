#import "DYNAMIC_LOADER.h"
#import "FAKE_JRE_MEMORY.h"
#import <sys/mman.h>
#import <string.h>

void* FakeJIT_Compile(const uint8_t* machineCode, size_t length) {
    if (!machineCode || length == 0) return NULL;

    void* mem = mmap(NULL, length, PROT_READ | PROT_WRITE | PROT_EXEC,
                     MAP_ANON | MAP_PRIVATE, -1, 0);
    if (mem == MAP_FAILED) return NULL;

    memcpy(mem, machineCode, length);
    return mem;
}

void JNI_SubmitBytecode(const char* name, const uint8_t* code, size_t length) {
    if (!name || !code || length == 0) return;

    void* compiled = FakeJIT_Compile(code, length);
    if (compiled) {
        [DynamicLoader registerLoadedFunction:compiled withName:name];
    }
}
