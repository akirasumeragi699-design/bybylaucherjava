#import <Foundation/Foundation.h>
#include <sys/mman.h>
#include <ffi.h>

@interface DynamicLoader : NSObject

+ (void*)loadCode:(const void*)code size:(size_t)size;
+ (void)callFunction:(void*)func args:(void**)args;

@end
