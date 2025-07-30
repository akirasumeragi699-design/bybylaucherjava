#import "DYNAMIC_LOADER.h"
#import "FAKE_JRE_MEMORY.h"

void JNI_LoadDynamicCode(const char* name, const void* code, size_t size) {
    NSLog(@"[JNI] Loading dynamic code: %s", name);
    
    void* execMem = [DynamicLoader loadCode:code size:size];
    if (execMem) {
        // Gọi hàm đã nạp với tham số mẫu
        void* args[] = { "DynamicCode" };
        [DynamicLoader callFunction:execMem args:args];
    }
}

// Ví dụ sử dụng:
- (void)testDynamicLoad {
    const unsigned char fakeCode[] = { 0x90, 0x90, 0xC3 }; // Code máy giả (NOP + RET)
    JNI_LoadDynamicCode("fakeMethod", fakeCode, sizeof(fakeCode));
}
FAKE_JRE_MEMORY.c: #include "FAKE_JRE_MEMORY.h"
#include <stdlib.h>

static void* JRE_Malloc(size_t size) {
    return malloc(size);
}

static void JRE_Free(void* ptr) {
    free(ptr);
}

JRE_MemoryAPI* JRE_GetMemoryAPI() {
    static JRE_MemoryAPI api = {
        .malloc = &JRE_Malloc,
        .free = &JRE_Free
    };
    return &api;
}
FAKE_JRE_MEMORY.h: #include <stddef.h>

typedef struct {
    void* (*malloc)(size_t size);
    void (*free)(void* ptr);
} JRE_MemoryAPI;

JRE_MemoryAPI* JRE_GetMemoryAPI();
