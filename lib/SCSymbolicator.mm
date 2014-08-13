/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#import "SCSymbolicator.h"

#import "SCBinaryInfo.h"
#import "SCMethodInfo.h"
#import "SCSymbolInfo.h"

#include <launch-cache/dsc_iterator.h>
#include <objc/runtime.h>
#include <string.h>
#include "demangle.h"
#include "localSymbols.h"

#ifndef kCFCoreFoundationVersionNumber_iOS_6_0
#define kCFCoreFoundationVersionNumber_iOS_7_0 793.00
#endif

#ifndef kCFCoreFoundationVersionNumber_iOS_7_0
#define kCFCoreFoundationVersionNumber_iOS_7_0 847.20
#endif

#ifndef kCFCoreFoundationVersionNumber10_7
#define kCFCoreFoundationVersionNumber10_7 635.00
#endif

#ifndef kCFCoreFoundationVersionNumber10_8
#define kCFCoreFoundationVersionNumber10_8 744.00
#endif

// NOTE: VMUMemory_File's buildSharedCacheMap method does not support newer
//       architectures (e.g. armv7s/arm64) on older versions of iOS and OS X.
//       (The lack of support is not in buildSharedCacheMap itself, but in a
//       function that it calls, dyld_shared_cache_iterate()).
static void buildSharedCacheMap(VMUMemory_File *mappedCache) {
    char *_mappedAddress = NULL;
    object_getInstanceVariable(mappedCache, "_mappedAddress", (void **)&_mappedAddress);

    // Determine architecture.
    BOOL isArmv7s = (strncmp(_mappedAddress, "dyld_v1  armv7", 14) == 0);
    BOOL isArm64 = (strcmp(_mappedAddress, "dyld_v1   arm64") == 0);

    // Determine whether to use our own impl. or call Symbolication's version.
    // NOTE: To prevent future issues, only override when absolutely necessary.
    //       For arm64, it is necessary for all versions of OS X.
    BOOL shouldOverride = YES;
#if TARGET_OS_IPHONE
    shouldOverride = ((isArmv7s && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_6_0))
        || (isArm64 && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_7_0)));
#else
    // TODO: Test on iOS 10.6 to confirm that it works with arm shared cache.
    // TODO: Confirm if arm64 override is needed for OS X 10.10.
    shouldOverride = (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber10_7)
        || (isArmv7s && (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber10_8))
        || isArm64;
#endif

    if (shouldOverride) {
        // Create a lookup table for addresses of dylibs in the cache.
        // TODO: Blocks are supported from iOS 4 and OS X 10.6. In order to
        //       support older versions, should switch to non-block iterator
        //       (dyld_shared_cache_iterate_segments_nb()).
        NSMutableDictionary *sharedCacheMap = [NSMutableDictionary new];
        int error = dyld_shared_cache_iterate(_mappedAddress, 0,
            ^(const dyld_shared_cache_dylib_info *dylibInfo, const dyld_shared_cache_segment_info *segInfo) {
                if (!strncmp(segInfo->name, "__TEXT", 6)) {
                    [sharedCacheMap setObject:[NSNumber numberWithLong:segInfo->fileOffset] forKey:[NSString stringWithUTF8String:dylibInfo->path]];
                }
            });

        if (error == -1) {
            NSException *exception = [NSException exceptionWithName:@"VMUMemory_File"
                reason:@"Failed while attempting to iterate over shared cache segments" userInfo:nil];
            @throw(exception);
        }

        // Update ivar of mapped cache object with the new value.
        NSMutableDictionary *_sharedCacheMap = nil;
        object_getInstanceVariable(mappedCache, "_sharedCacheMap", (void **)&_sharedCacheMap);
        [_sharedCacheMap release];
        object_setInstanceVariable(mappedCache, "_sharedCacheMap", sharedCacheMap);
    } else {
        [mappedCache buildSharedCacheMap];
    }
}

@implementation SCSymbolicator

@synthesize architecture = architecture_;
@synthesize symbolMaps = symbolMaps_;
@synthesize systemRoot = systemRoot_;
@synthesize mappedCache = mappedCache_;

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (void)dealloc {
    [architecture_ release];
    [symbolMaps_ release];
    [systemRoot_ release];
    [mappedCache_ release];
    [super dealloc];
}

- (NSString *)architecture {
    return architecture_ ?: @"armv7";
}

- (void)setArchitecture:(NSString *)architecture {
    if (![architecture_ isEqualToString:architecture]) {
        [architecture_ release];
        architecture_ = [architecture copy];

        // Path to shared cache has changed.
        [mappedCache_ release];
        mappedCache_ = nil;
    }
}

- (NSString *)systemRoot {
    return systemRoot_ ?: @"/";
}

- (void)setSystemRoot:(NSString *)systemRoot {
    if (![systemRoot_ isEqualToString:systemRoot]) {
        [systemRoot_ release];
        systemRoot_ = [systemRoot copy];

        // Path to shared cache has changed.
        [mappedCache_ release];
        mappedCache_ = nil;
    }
}

- (VMUMemory_File *)mappedCache {
    if (mappedCache_ == nil) {
        // Map the cache.
        NSString *sharedCachePath = [self sharedCachePath];
        VMURange range = (VMURange){0, 0};
        mappedCache_ = [[VMUMemory_File alloc] initWithPath:sharedCachePath fileRange:range mapToAddress:0 architecture:nil];
        if (mappedCache_ != nil) {
            buildSharedCacheMap(mappedCache_);
        } else {
            fprintf(stderr, "ERROR: Unable to map shared cache file '%s'.\n", [sharedCachePath UTF8String]);
        }
    }
    return mappedCache_;
}

- (NSString *)sharedCachePath {
    NSString *sharedCachePath = @"/System/Library/Caches/com.apple.dyld/dyld_shared_cache_";

    // Prepend the system root.
    sharedCachePath = [[self systemRoot] stringByAppendingPathComponent:sharedCachePath];

    // Add the architecture and return.
    return [sharedCachePath stringByAppendingString:[self architecture]];
}

CFComparisonResult reverseCompareUnsignedLongLong(CFNumberRef a, CFNumberRef b) {
    unsigned long long aValue;
    unsigned long long bValue;
    CFNumberGetValue(a, kCFNumberLongLongType, &aValue);
    CFNumberGetValue(b, kCFNumberLongLongType, &bValue);
    if (bValue < aValue) return kCFCompareLessThan;
    if (bValue > aValue) return kCFCompareGreaterThan;
    return kCFCompareEqualTo;
}

- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address inBinary:(SCBinaryInfo *)binaryInfo {
    SCSymbolInfo *symbolInfo = nil;

    VMUMachOHeader *header = [binaryInfo header];
    if (header != nil) {
        address += [binaryInfo slide];
        VMUSymbolOwner *owner = [binaryInfo owner];
        VMUSourceInfo *srcInfo = [owner sourceInfoForAddress:address];
        if (srcInfo != nil) {
            // Store source file name and line number.
            symbolInfo = [SCSymbolInfo new];
            [symbolInfo setSourcePath:[srcInfo path]];
            [symbolInfo setSourceLineNumber:[srcInfo lineNumber]];
        } else {
            // Determine symbol address.
            // NOTE: Only possible if LC_FUNCTION_STARTS exists in the binary.
            uint64_t symbolAddress = 0;
            NSArray *symbolAddresses = [binaryInfo symbolAddresses];
            NSUInteger count = [symbolAddresses count];
            if (count != 0) {
                NSNumber *targetAddress = [[NSNumber alloc] initWithUnsignedLongLong:address];
                CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)symbolAddresses, CFRangeMake(0, count), targetAddress, (CFComparatorFunction)reverseCompareUnsignedLongLong, NULL);
                [targetAddress release];
                if (matchIndex < (CFIndex)count) {
                    symbolAddress = [[symbolAddresses objectAtIndex:matchIndex] unsignedLongLongValue];
                }
            }

            // Attempt to retrieve symbol name and hex offset.
            NSString *name = nil;
            uint64_t offset = 0;
            VMUSymbol *symbol = [owner symbolForAddress:address];
            if (symbol != nil && ([symbol addressRange].location == (symbolAddress & ~1) || symbolAddress == 0)) {
                name = [symbol name];
                if ([name isEqualToString:@"<redacted>"]) {
                    NSString *sharedCachePath = [self sharedCachePath];
                    if (sharedCachePath != nil) {
                        NSString *localName = nameForLocalSymbol(sharedCachePath, [header address], [symbol addressRange].location);
                        if (localName != nil) {
                            name = localName;
                        } else {
                            fprintf(stderr, "Unable to determine name for: %s, 0x%08llx\n", [[binaryInfo path] UTF8String], [symbol addressRange].location);
                        }
                    }
                }
                // Attempt to demangle name
                // NOTE: It seems that Apple's demangler fails for some
                //       names, so we attempt to do it ourselves.
                name = demangle(name);
                offset = address - [symbol addressRange].location;
            } else {
                NSDictionary *symbolMap = [[self symbolMaps] objectForKey:[binaryInfo path]];
                if (symbolMap != nil) {
                    for (NSNumber *number in [[[symbolMap allKeys] sortedArrayUsingSelector:@selector(compare:)] reverseObjectEnumerator]) {
                        uint64_t mapSymbolAddress = [number unsignedLongLongValue];
                        if (address > mapSymbolAddress) {
                            name = demangle([symbolMap objectForKey:number]);
                            offset = address - mapSymbolAddress;
                            break;
                        }
                    }
                } else if (![binaryInfo isEncrypted]) {
                    // Determine methods, attempt to match with symbol address.
                    if (symbolAddress != 0) {
                        SCMethodInfo *method = nil;
                        NSArray *methods = [binaryInfo methods];
                        count = [methods count];
                        if (count != 0) {
                            SCMethodInfo *targetMethod = [SCMethodInfo new];
                            [targetMethod setAddress:address];
                            CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)methods, CFRangeMake(0, count), targetMethod, (CFComparatorFunction)reversedCompareMethodInfos, NULL);
                            [targetMethod release];

                            if (matchIndex < (CFIndex)count) {
                                method = [methods objectAtIndex:matchIndex];
                            }
                        }

                        if (method != nil && [method address] >= symbolAddress) {
                            name = [method name];
                            offset = address - [method address];
                        } else {
                            uint64_t textStart = [[header segmentNamed:@"__TEXT"] vmaddr];
                            name = [NSString stringWithFormat:@"0x%08llx", (symbolAddress - textStart)];
                            offset = address - symbolAddress;
                        }
                    }
                }
            }

            if (name != nil) {
                symbolInfo = [SCSymbolInfo new];
                [symbolInfo setName:name];
                [symbolInfo setOffset:offset];
            }
        }
    }

    return [symbolInfo autorelease];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
