#ifndef FAKE_JRE_MEMORY_H
#define FAKE_JRE_MEMORY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    void* (*malloc)(size_t size);
    void  (*free)(void* ptr);
} JRE_MemoryAPI;

JRE_MemoryAPI* JRE_GetMemoryAPI(void);

#ifdef __cplusplus
}
#endif

#endif // FAKE_JRE_MEMORY_H
