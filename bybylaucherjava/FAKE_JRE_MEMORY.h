#include <stddef.h>

typedef struct {
    void* (*malloc)(size_t size);
    void (*free)(void* ptr);
} JRE_MemoryAPI;

JRE_MemoryAPI* JRE_GetMemoryAPI();
