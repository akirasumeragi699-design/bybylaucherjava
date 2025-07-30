#import "DYNAMIC_LOADER.h"

@implementation DynamicLoader

+ (void*)loadCode:(const void*)code size:(size_t)size {
    // Cấp phát bộ nhớ có thể ghi (không dùng PROT_EXEC do hạn chế iOS)
    void* mem = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if (mem == MAP_FAILED) return NULL;
    
    // Copy code vào vùng nhớ (mô phỏng quá trình nạp code)
    memcpy(mem, code, size);
    
    // Lưu ý: Trên iOS thường không thể set PROT_EXEC
    return mem;
}

+ (void)callFunction:(void*)func args:(void**)args {
    ffi_cif cif;
    ffi_type* argTypes[] = { &ffi_type_pointer }; // Giả sử hàm nhận 1 tham số
    void* values[] = { args[0] };
    
    // Thiết lập và gọi hàm thông qua libffi
    if (ffi_prep_cif(&cif, FFI_DEFAULT_ABI, 1, &ffi_type_void, argTypes) == FFI_OK) {
        ffi_call(&cif, (void (*)(void))func, NULL, values);
    }
}

@end
