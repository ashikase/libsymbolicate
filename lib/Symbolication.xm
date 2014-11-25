#import "Headers.h"

#if TARGET_OS_IPHONE
    #ifndef kCFCoreFoundationVersionNumber_iOS_8_0
    #define kCFCoreFoundationVersionNumber_iOS_8_0 1140.10
    #endif
#else
    #ifndef kCFCoreFoundationVersionNumber10_10
    #define kCFCoreFoundationVersionNumber10_10 1151.16
    #endif
#endif

%hook VMUMemory_File

%new
+ (VMUHeader *)headerWithPath:(NSString *)path {
    return nil;
}

%new
- (VMUMemory_File *)initWithPath:(NSString *)path fileRange:(VMURange)fileRange mapToAddress:(uint64_t)address architecture:(VMUArchitecture *)architecture {
    return nil;
}

%end

//==============================================================================

static void registerClass(const char * const className, const char * const superclassName) {
    Class klass = objc_getClass(className);
    if (klass == Nil) {
        Class superKlass = objc_getClass(superclassName);
        if (superKlass != Nil) {
            klass = objc_allocateClassPair(superKlass, className, 0);
            if (klass != Nil) {
                objc_registerClassPair(klass);
            }
        }
    }
}

%ctor { @autoreleasepool {

#if TARGET_OS_IPHONE
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
#else
    if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_10) {
#endif
        registerClass("VMUHeader", "NSObject");
        registerClass("VMUFatHeader", "VMUHeader");
        registerClass("VMUMachOHeader", "VMUHeader");
        registerClass("VMUMachO32Header", "VMUMachOHeader");
        registerClass("VMUMachO64Header", "VMUMachOHeader");

        registerClass("VMULoadCommand", "NSObject");
        registerClass("VMUMemory_File", "NSObject");
        registerClass("VMUSymbolExtractor", "NSObject");
        registerClass("VMUSymbolOwner", "NSObject");

        %init();
    }
}}

/* vim: set ft=logos ff=unix sw=4 ts=4 expandtab tw=80: */
