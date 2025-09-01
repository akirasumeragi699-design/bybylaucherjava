// dynamicloader.h
#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

#ifdef __cplusplus
extern "C" {
#endif

// Tạo dynamic object với danh sách method
id createDynamicObject(NSArray<NSString*>* methods);

// Gọi method bất kỳ trên object dynamic
void callDynamicMethod(id obj, NSString *selName);

// Register callback cho method dynamic
void registerCallbackForMethod(NSString *methodName, void (^callback)(id));

#ifdef __cplusplus
}
#endif

NS_ASSUME_NONNULL_END
