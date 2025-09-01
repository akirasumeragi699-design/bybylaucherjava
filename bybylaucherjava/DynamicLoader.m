#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ============================
// 1️⃣ Global callback storage (ví dụ gọi bridge Java)
// ============================
static NSMutableDictionary<NSString*, void (^)(id)> *dynamicCallbacks;

void registerDynamicCallback(NSString *methodName, void (^callback)(id)) {
    if (!dynamicCallbacks) dynamicCallbacks = [NSMutableDictionary dictionary];
    dynamicCallbacks[methodName] = [callback copy];
}

// ============================
// 2️⃣ Dynamic dispatcher
// ============================
void dynamicDispatcher(id self, SEL _cmd, ...) {
    NSString *selName = NSStringFromSelector(_cmd);
    NSLog(@"Dynamic method called: %@", selName);

    void (^callback)(id) = dynamicCallbacks[selName];
    if (callback) {
        callback(self);
    } else {
        NSLog(@"No callback registered for method %@", selName);
    }
}

// ============================
// 3️⃣ HybridRuntime full dynamic
// ============================
@interface HybridRuntime : NSObject

+ (Class)createDynamicClass:(NSString *)name dynamicMethods:(NSArray<NSString*>*)methods;
+ (void)overrideMethod:(Class)cls selectorName:(NSString*)selName;

@end

@implementation HybridRuntime

+ (Class)createDynamicClass:(NSString *)name dynamicMethods:(NSArray<NSString*>*)methods {
    Class cls = objc_allocateClassPair([NSObject class], [name UTF8String], 0);

    for (NSString *selName in methods) {
        SEL sel = NSSelectorFromString(selName);
        class_addMethod(cls, sel, (IMP)dynamicDispatcher, "v@:");
    }

    objc_registerClassPair(cls);
    return cls;
}

+ (void)overrideMethod:(Class)cls selectorName:(NSString*)selName {
    SEL sel = NSSelectorFromString(selName);
    class_replaceMethod(cls, sel, (IMP)dynamicDispatcher, "v@:");
}

@end

// ============================
// 4️⃣ Export functions cho Java
// ============================
id createDynamicObject(NSArray<NSString*>* methods) {
    Class DynCls = [HybridRuntime createDynamicClass:@"DynFoo" dynamicMethods:methods];
    return [[DynCls alloc] init];
}

void callDynamicMethod(id obj, NSString *selName) {
    SEL sel = NSSelectorFromString(selName);
    if ([obj respondsToSelector:sel]) {
        [obj performSelector:sel];
    } else {
        NSLog(@"Method %@ not found!", selName);
    }
}

void registerCallbackForMethod(NSString *methodName, void (^callback)(id)) {
    registerDynamicCallback(methodName, callback);
}

// ============================
// 5️⃣ Main test
// ============================
int main() {
    @autoreleasepool {
        // 5.1 Register callback
        registerCallbackForMethod(@"dynamicMethod", ^(id obj){
            NSLog(@"Callback executed for %@", obj);
        });

        // 5.2 Create dynamic object
        id dynObj = createDynamicObject(@[@"dynamicMethod", @"anotherMethod"]);

        // 5.3 Call dynamic methods
        callDynamicMethod(dynObj, @"dynamicMethod");
        callDynamicMethod(dynObj, @"anotherMethod"); // cũng đi qua dispatcher
    }
}
