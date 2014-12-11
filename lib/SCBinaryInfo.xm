/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#import "SCBinaryInfo.h"

#import "SCMethodInfo.h"
#import "SCSymbolicator.h"
#import "SCSymbolInfo.h"
#import "binary.h"

#include <mach-o/loader.h>
#include <objc/runtime.h>
#include "CoreSymbolication.h"
#include "methods.h"

// ABI types.
#ifndef CPU_ARCH_ABI64
#define CPU_ARCH_ABI64 0x01000000
#endif

// CPU types.
#ifndef CPU_TYPE_ARM
#define CPU_TYPE_ARM 12
#endif

#ifndef CPU_TYPE_ARM64
#define CPU_TYPE_ARM64 (CPU_TYPE_ARM | CPU_ARCH_ABI64)
#endif

// ARM subtypes.
#ifndef CPU_SUBTYPE_ARM_ALL
#define CPU_SUBTYPE_ARM_ALL 0
#endif

#ifndef CPU_SUBTYPE_ARM_V6
#define CPU_SUBTYPE_ARM_V6 6
#endif

#ifndef CPU_SUBTYPE_ARM_V7
#define CPU_SUBTYPE_ARM_V7 9
#endif

#ifndef CPU_SUBTYPE_ARM_V7F
#define CPU_SUBTYPE_ARM_V7F 10 // Cortex A9
#endif

#ifndef CPU_SUBTYPE_ARM_V7S
#define CPU_SUBTYPE_ARM_V7S 11 // Swift
#endif

#ifndef CPU_SUBTYPE_ARM_V7K
#define CPU_SUBTYPE_ARM_V7K 12 // Kirkwood40
#endif

// ARM64 subtypes.
#ifndef CPU_SUBTYPE_ARM64_ALL
#define CPU_SUBTYPE_ARM64_ALL 0
#endif

#ifndef CPU_SUBTYPE_ARM64_V8
#define CPU_SUBTYPE_ARM64_V8 1
#endif

// NOTE: CoreSymbolication provides a similar function, but it is not available
//       in earlier versions of iOS.
// TODO: Determine from which version the function is available.
static CSArchitecture architectureForName(const char *name) {
    CSArchitecture arch;

    if (strcmp(name, "arm64") == 0) {
        arch.cpu_type = CPU_TYPE_ARM64;
        arch.cpu_subtype = CPU_SUBTYPE_ARM64_ALL;
    } else if (
            (strcmp(name, "armv7s") == 0) ||
            (strcmp(name, "armv7k") == 0) ||
            (strcmp(name, "armv7f") == 0)) {
        arch.cpu_type = CPU_TYPE_ARM;
        arch.cpu_subtype = CPU_SUBTYPE_ARM_V7S;
    } else if (strcmp(name, "armv7") == 0) {
        arch.cpu_type = CPU_TYPE_ARM;
        arch.cpu_subtype = CPU_SUBTYPE_ARM_V7;
    } else if (strcmp(name, "armv6") == 0) {
        arch.cpu_type = CPU_TYPE_ARM;
        arch.cpu_subtype = CPU_SUBTYPE_ARM_V6;
    } else if (strcmp(name, "arm") == 0) {
        arch.cpu_type = CPU_TYPE_ARM;
        arch.cpu_subtype = CPU_SUBTYPE_ARM_ALL;
    } else {
        arch.cpu_type = 0;
        arch.cpu_subtype = 0;
    }

    return arch;
}

// NOTE: CFUUIDCreateFromString() does not support unhyphenated UUID strings.
//       UUID must be hyphenated, must follow pattern "8-4-4-4-12".
CFUUIDRef CFUUIDCreateFromUnformattedCString(const char *string) {
    CFUUIDRef uuid = NULL;

    if (strlen(string) >= 32) {
        // Create buffer large enough to hold UUID, four hyphens, and null char.
        char buf[37];

        unsigned i = 0;
        unsigned j = 0;

        for (; i < 8; ++i, ++j) {
            buf[j] = string[i];
        }

        buf[j++] = '-';

        for (; i < 12; ++i, ++j) {
            buf[j] = string[i];
        }

        buf[j++] = '-';

        for (; i < 16; ++i, ++j) {
            buf[j] = string[i];
        }

        buf[j++] = '-';

        for (; i < 20; ++i, ++j) {
            buf[j] = string[i];
        }

        buf[j++] = '-';

        for (; i < 32; ++i, ++j) {
            buf[j] = string[i];
        }

        buf[j] = '\0';

        CFStringRef stringRef = CFStringCreateWithCString(kCFAllocatorDefault, buf, kCFStringEncodingASCII);
        if (stringRef != NULL) {
            uuid = CFUUIDCreateFromString(kCFAllocatorDefault, stringRef);
            CFRelease(stringRef);
        }
    }

    return uuid;
}

@implementation SCBinaryInfo {
    CSSymbolicatorRef symbolicator_;
    CSSymbolOwnerRef owner_;

    BOOL hasExtractedMethods_;
    BOOL hasExtractedOwner_;
}

@synthesize address = address_;
@synthesize architecture = architecture_;
@synthesize fromSharedCache = fromSharedCache_;
@synthesize methods = methods_;
@synthesize path = path_;
@synthesize symbolAddresses = symbolAddresses_;
@synthesize uuid = uuid_;

@dynamic encrypted;
@dynamic executable;
@dynamic slide;

#pragma mark - Creation & Destruction

- (id)initWithPath:(NSString *)path address:(uint64_t)address architecture:(NSString *)architecture uuid:(NSString *)uuid {
    self = [super init];
    if (self != nil) {
        path_ = [path copy];
        address_ = address;
        architecture_ = [architecture copy];
        uuid_ = [uuid copy];
    }
    return self;
}

- (void)dealloc {
    if (!CSIsNull(symbolicator_)) {
        CSRelease(symbolicator_);
    }

    [architecture_ release];
    [methods_ release];
    [path_ release];
    [uuid_ release];
    [symbolAddresses_ release];
    [super dealloc];
}

#pragma mark - Properties

// NOTE: This is the virtual address of the __TEXT segment.
- (uint64_t)baseAddress {
    uint64_t baseAddress = 0;
    CSSymbolOwnerRef owner = [self owner];
    if (!CSIsNull(owner)) {
        baseAddress = CSSymbolOwnerGetBaseAddress(owner);
    }
    return baseAddress;
}

- (BOOL)isEncrypted {
    CSArchitecture arch = architectureForName([[self architecture] UTF8String]);
    return isEncrypted([[self path] UTF8String], arch.cpu_type, arch.cpu_subtype);
}

- (BOOL)isExecutable {
    BOOL isExecutable = NO;

    CSSymbolOwnerRef owner = [self owner];
    if (!CSIsNull(owner)) {
        isExecutable = (BOOL)CSSymbolOwnerIsAOut(owner);
    }

    return isExecutable;
}

// NOTE: This method is used when CoreSymbolication fails to find a name for a
//       symbol. Therefore, this method must not rely on CoreSymbolication.
- (NSArray *)methods {
    if (methods_ == nil) {
        if (!hasExtractedMethods_) {
            hasExtractedMethods_ = YES;

            CSArchitecture arch = architectureForName([[self architecture] UTF8String]);
            methods_ = [methodsForBinaryFile([[self path] UTF8String], arch.cpu_type, arch.cpu_subtype) retain];
        }
    }
    return methods_;
}

- (int64_t)slide {
    return ([self baseAddress] - [self address]);
}

// NOTE: The symbol addresses array is sorted greatest to least so that it can
//       be used with CFArrayBSearchValues().
- (NSArray *)symbolAddresses {
    if (symbolAddresses_ == nil) {
        NSMutableArray *addresses = [[NSMutableArray alloc] init];

        CSSymbolOwnerRef owner = [self owner];
        if (!CSIsNull(owner)) {
            CSSymbolOwnerForeachSymbol(owner, ^(CSSymbolRef symbol) {
                if (CSSymbolIsFunction(symbol)) {
                    CSRange range = CSSymbolGetRange(symbol);
                    NSNumber *symbolAddress = [[NSNumber alloc] initWithUnsignedLongLong:(range.location)];
                    [addresses addObject:symbolAddress];
                    [symbolAddress release];
                }
                return 0;
            });
        }
        NSArray *sortedAddresses = [addresses sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))CFNumberCompare context:NULL];
        [addresses release];

        NSMutableArray *reverseSortedAddresses = [[NSMutableArray alloc] init];
        for (NSNumber *number in [sortedAddresses reverseObjectEnumerator]) {
            [reverseSortedAddresses addObject:number];
        }
        symbolAddresses_ = reverseSortedAddresses;
    }
    return symbolAddresses_;
}

#pragma mark - Public Methods

- (SCSymbolInfo *)sourceInfoForAddress:(uint64_t)address {
    SCSymbolInfo *symbolInfo = nil;

    const char *path = NULL;
    unsigned lineNumber = 0;

    CSSymbolOwnerRef owner = [self owner];
    if (!CSIsNull(owner)) {
        CSSourceInfoRef sourceInfo = CSSymbolOwnerGetSourceInfoWithAddress(owner, address);
        if (!CSIsNull(sourceInfo)) {
            lineNumber = CSSourceInfoGetLineNumber(sourceInfo);
            path = CSSourceInfoGetPath(sourceInfo);
        }
    }

    if (path != nil) {
        symbolInfo = [[[SCSymbolInfo alloc] init] autorelease];
        [symbolInfo setSourceLineNumber:lineNumber];

        NSString *string = [[NSString alloc] initWithUTF8String:path];
        [symbolInfo setSourcePath:string];
        [string release];
    }

    return symbolInfo;
}

- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address {
    SCSymbolInfo *symbolInfo = nil;

    const char *name = NULL;
    SCAddressRange addressRange;

    CSSymbolOwnerRef owner = [self owner];
    if (!CSIsNull(owner)) {
        CSSymbolRef symbol = CSSymbolOwnerGetSymbolWithAddress(owner, address);
        if (!CSIsNull(symbol)) {
            CSRange range = CSSymbolGetRange(symbol);
            addressRange = (SCAddressRange){range.location, range.length};
            name = CSSymbolGetName(symbol);
        }
    }

    if (name != nil) {
        symbolInfo = [[[SCSymbolInfo alloc] init] autorelease];
        [symbolInfo setAddressRange:addressRange];

        NSString *string = [[NSString alloc] initWithUTF8String:name];
        [symbolInfo setName:string];
        [string release];
    }

    return symbolInfo;
}

#pragma mark - Private Methods

- (CSSymbolicatorRef)symbolicator {
    if (CSIsNull(symbolicator_)) {
        CSArchitecture arch = architectureForName([[self architecture] UTF8String]);
        if (arch.cpu_type != 0) {
            CSSymbolicatorRef symbolicator = CSSymbolicatorCreateWithPathAndArchitecture([[self path] UTF8String], arch);
            if (!CSIsNull(symbolicator)) {
                symbolicator_ = symbolicator;
            }
        }
    }
    return symbolicator_;
}

- (CSSymbolOwnerRef)owner {
    if (CSIsNull(owner_)) {
        if (!hasExtractedOwner_) {
            hasExtractedOwner_ = YES;

            CSSymbolicatorRef symbolicator = [self symbolicator];
            if (!CSIsNull(symbolicator)) {
                // NOTE: Must ignore "<>" characters in UUID string.
                // FIXME: Do not store the UUID with these characters included.
                CFUUIDRef uuid = CFUUIDCreateFromUnformattedCString(&([[self uuid] UTF8String][1]));
                CSSymbolOwnerRef owner = CSSymbolicatorGetSymbolOwnerWithUUIDAtTime(symbolicator, uuid, kCSNow);
                if (!CSIsNull(owner)) {
                    owner_ = owner;
                } else {
                    fprintf(stderr, "WARNING: Device does not contain binary with matching UUID for file: %s\n", [[self path] UTF8String]);
                }
                CFRelease(uuid);
            }
        }
    }
    return owner_;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
