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

static BOOL shouldUseCoreSymbolication = NO;

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

static NSArray *symbolAddressesForImageWithHeader(VMUMachOHeader *header) {
    NSMutableArray *addresses = [NSMutableArray new];

    uint64_t offset = linkCommandOffsetForHeader(header, LC_FUNCTION_STARTS);
    if (offset != 0) {
        id<VMUMemoryView> view = (id<VMUMemoryView>)[[header memory] view];
        uint64_t viewoff = [view cursor];
        @try {
            [view setCursor:[header address] + offset + 8];
            uint32_t dataoff = [view uint32];
            [view setCursor:(viewoff + dataoff)];
            uint64_t offset;
            uint64_t symbolAddress = [[header segmentNamed:@"__TEXT"] vmaddr];

            // FIXME: This is slow.
            while ((offset = [view ULEB128])) {
                symbolAddress += offset;
                [addresses addObject:[NSNumber numberWithUnsignedLongLong:symbolAddress]];
            }
        } @catch (NSException *exception) {
            fprintf(stderr, "WARNING: Exception '%s' generated when extracting symbol addresses for %s.\n",
                    [[exception reason] UTF8String], [[header path] UTF8String]);
        }
    }

    NSArray *sortedAddresses = [addresses sortedArrayUsingFunction:(NSInteger (*)(id, id, void *))CFNumberCompare context:NULL];
    [addresses release];

    NSMutableArray *reverseSortedAddresses = [NSMutableArray array];
    for (NSNumber *number in [sortedAddresses reverseObjectEnumerator]) {
        [reverseSortedAddresses addObject:number];
    }
    return reverseSortedAddresses;
}

@implementation SCBinaryInfo {
    BOOL headerIsUnavailable_;

    VMUMachOHeader *header_;
    VMUSymbolOwner *owner_;

    CSSymbolicatorRef symbolicatorRef_;
    CSSymbolOwnerRef ownerRef_;
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
    if (!CSIsNull(symbolicatorRef_)) {
        CSRelease(symbolicatorRef_);
    }

    [architecture_ release];
    [header_ release];
    [methods_ release];
    [owner_ release];
    [path_ release];
    [uuid_ release];
    [symbolAddresses_ release];
    [super dealloc];
}

- (BOOL)isEncrypted {
    cpu_type_t cputype = CPU_TYPE_ANY;
    cpu_subtype_t cpusubtype = CPU_SUBTYPE_MULTIPLE;

    NSString *requiredArchitecture = [self architecture];
    if ([requiredArchitecture isEqualToString:@"arm64"]) {
        cputype = CPU_TYPE_ARM64;
        cpusubtype = CPU_SUBTYPE_ARM64_ALL;
    } else if (
            [requiredArchitecture isEqualToString:@"armv7s"] ||
            [requiredArchitecture isEqualToString:@"armv7k"] ||
            [requiredArchitecture isEqualToString:@"armv7f"]) {
        cputype = CPU_TYPE_ARM;
        cpusubtype = CPU_SUBTYPE_ARM_V7S;
    } else if ([requiredArchitecture isEqualToString:@"armv7"]) {
        cputype = CPU_TYPE_ARM;
        cpusubtype = CPU_SUBTYPE_ARM_V7;
    } else if ([requiredArchitecture isEqualToString:@"armv6"]) {
        cputype = CPU_TYPE_ARM;
        cpusubtype = CPU_SUBTYPE_ARM_V6;
    } else if ([requiredArchitecture isEqualToString:@"arm"]) {
        cputype = CPU_TYPE_ARM;
        cpusubtype = CPU_SUBTYPE_ARM_ALL;
    }
    return isEncrypted([[self path] UTF8String], cputype, cpusubtype);
}

- (BOOL)isExecutable {
    return ([[self header] fileType] == MH_EXECUTE);
}

- (NSArray *)methods {
    if (methods_ == nil) {
        cpu_type_t cputype = CPU_TYPE_ANY;
        cpu_subtype_t cpusubtype = CPU_SUBTYPE_MULTIPLE;

        NSString *requiredArchitecture = [self architecture];
        if ([requiredArchitecture isEqualToString:@"arm64"]) {
            cputype = CPU_TYPE_ARM64;
            cpusubtype = CPU_SUBTYPE_ARM64_ALL;
        } else if (
                [requiredArchitecture isEqualToString:@"armv7s"] ||
                [requiredArchitecture isEqualToString:@"armv7k"] ||
                [requiredArchitecture isEqualToString:@"armv7f"]) {
            cputype = CPU_TYPE_ARM;
            cpusubtype = CPU_SUBTYPE_ARM_V7S;
        } else if ([requiredArchitecture isEqualToString:@"armv7"]) {
            cputype = CPU_TYPE_ARM;
            cpusubtype = CPU_SUBTYPE_ARM_V7;
        } else if ([requiredArchitecture isEqualToString:@"armv6"]) {
            cputype = CPU_TYPE_ARM;
            cpusubtype = CPU_SUBTYPE_ARM_V6;
        } else if ([requiredArchitecture isEqualToString:@"arm"]) {
            cputype = CPU_TYPE_ARM;
            cpusubtype = CPU_SUBTYPE_ARM_ALL;
        }
        methods_ = [methodsForBinaryFile([[self path] UTF8String], cputype, cpusubtype) retain];
    }
    return methods_;
}

- (int64_t)slide {
    uint64_t textStart = [[[self header] segmentNamed:@"__TEXT"] vmaddr];
    return (textStart - [self address]);
}

// NOTE: The symbol addresses array is sorted greatest to least so that it can
//       be used with CFArrayBSearchValues().
- (NSArray *)symbolAddresses {
    if (symbolAddresses_ == nil) {
        NSMutableArray *addresses = [[NSMutableArray alloc] init];

        CSSymbolOwnerRef owner = [self ownerRef];
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

- (VMUSegmentLoadCommand *)segmentNamed:(NSString *)name {
    return [[self header] segmentNamed:name];
}

- (uint64_t)sharedCacheOffset {
    return [[self header] address];
}

- (SCSymbolInfo *)sourceInfoForAddress:(uint64_t)address {
    SCSymbolInfo *symbolInfo = nil;

    const char *path = NULL;
    unsigned lineNumber = 0;

    CSSymbolOwnerRef owner = [self ownerRef];
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

    CSSymbolOwnerRef owner = [self ownerRef];
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

#pragma mark - Firmware_LT_80 (Symbolication.framework)

- (VMUMachOHeader *)header {
    if (header_ == nil) {
        if (!headerIsUnavailable_) {
            // Get Mach-O header for the image
            VMUMachOHeader *header = nil;
            NSString *path = [self path];
            VMUMemory_File *mappedCache = [[SCSymbolicator sharedInstance] mappedCache];
            if (mappedCache != nil) {
                uint64_t address = [mappedCache sharedCacheHeaderOffsetForPath:path];
                NSString *name = [path lastPathComponent];
                id timestamp = [mappedCache lastModifiedTimestamp];
                header = [%c(VMUHeader) headerWithMemory:mappedCache address:address name:name path:path timestamp:timestamp];
                if (header != nil) {
                    fromSharedCache_ = YES;
                }
            }
            if (header == nil) {
                header = [%c(VMUMemory_File) headerWithPath:path];
            }
            if ((header != nil) && ![header isKindOfClass:%c(VMUMachOHeader)]) {
                // Extract required architecture from archive.
                // TODO: Confirm if arm7f and arm7k should use own cpu subtype.
                VMUArchitecture *architecture = nil;
                NSString *requiredArchitecture = [self architecture];
                if ([requiredArchitecture isEqualToString:@"arm64"]) {
                    architecture = [[VMUArchitecture alloc] initWithCpuType:CPU_TYPE_ARM64 cpuSubtype:CPU_SUBTYPE_ARM64_ALL];
                } else if (
                        [requiredArchitecture isEqualToString:@"armv7s"] ||
                        [requiredArchitecture isEqualToString:@"armv7k"] ||
                        [requiredArchitecture isEqualToString:@"armv7f"]) {
                    architecture = [[VMUArchitecture alloc] initWithCpuType:CPU_TYPE_ARM cpuSubtype:CPU_SUBTYPE_ARM_V7S];
                } else if ([requiredArchitecture isEqualToString:@"armv7"]) {
                    architecture = [[VMUArchitecture alloc] initWithCpuType:CPU_TYPE_ARM cpuSubtype:CPU_SUBTYPE_ARM_V7];
                } else if ([requiredArchitecture isEqualToString:@"armv6"]) {
                    architecture = [[VMUArchitecture alloc] initWithCpuType:CPU_TYPE_ARM cpuSubtype:CPU_SUBTYPE_ARM_V6];
                } else if ([requiredArchitecture isEqualToString:@"arm"]) {
                    architecture = [[VMUArchitecture alloc] initWithCpuType:CPU_TYPE_ARM cpuSubtype:CPU_SUBTYPE_ARM_ALL];
                }
                if (architecture != nil) {
                    header = [[%c(VMUHeader) extractMachOHeadersFromHeader:header matchingArchitecture:architecture considerArchives:NO] lastObject];
                    [architecture release];
                } else {
                    header = nil;
                }
            }
            if (header != nil) {
                // Check UUID signature of binary.
                NSString *uuid = [[[header uuid] description] stringByReplacingOccurrencesOfString:@" " withString:@""];
                if ([uuid isEqualToString:[self uuid]]) {
                    header_ = [header retain];
                } else {
                    fprintf(stderr, "INFO: Symbolicating device does not have required version of binary image: %s\n", [path UTF8String]);
                    headerIsUnavailable_ = YES;
                }
            } else {
                fprintf(stderr, "INFO: Symbolicating device does not have required binary image: %s\n", [path UTF8String]);
                headerIsUnavailable_ = YES;
            }
        }
    }
    return header_;
}

- (VMUSymbolOwner *)owner {
    if (owner_ == nil) {
        if (!headerIsUnavailable_) {
            // NOTE: The following method is quite slow.
            owner_ = [[%c(VMUSymbolExtractor) extractSymbolOwnerFromHeader:[self header]] retain];
        }
    }
    return owner_;
}

#pragma mark - Firmware_GTE_80 (CoreSymbolication.framework)

- (CSSymbolicatorRef)symbolicatorRef {
    if (CSIsNull(symbolicatorRef_)) {
        CSArchitecture arch = architectureForName([[self architecture] UTF8String]);
        if (arch.cpu_type != 0) {
            CSSymbolicatorRef symbolicator = CSSymbolicatorCreateWithPathAndArchitecture([[self path] UTF8String], arch);
            if (!CSIsNull(symbolicator)) {
                symbolicatorRef_ = symbolicator;
            }
        }
    }
    return symbolicatorRef_;
}

- (CSSymbolOwnerRef)ownerRef {
    if (CSIsNull(ownerRef_)) {
        CSSymbolicatorRef symbolicator = [self symbolicatorRef];
        if (!CSIsNull(symbolicator)) {
            // NOTE: Must ignore "<>" characters in UUID string.
            // FIXME: Do not store the UUID with these characters included.
            CFUUIDRef uuid = CFUUIDCreateFromUnformattedCString(&([[self uuid] UTF8String][1]));
            CSSymbolOwnerRef owner = CSSymbolicatorGetSymbolOwnerWithUUIDAtTime(symbolicator, uuid, kCSNow);
            if (!CSIsNull(owner)) {
                ownerRef_ = owner;
            }
            CFRelease(uuid);
        }
    }
    return ownerRef_;
}

@end

#if TARGET_OS_IPHONE
    #ifndef kCFCoreFoundationVersionNumber_iOS_8_0
    #define kCFCoreFoundationVersionNumber_iOS_8_0 1140.10
    #endif
#else
    #ifndef kCFCoreFoundationVersionNumber10_10
    #define kCFCoreFoundationVersionNumber10_10 1151.16
    #endif
#endif

%ctor {
#if TARGET_OS_IPHONE
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber_iOS_8_0) {
#else
        if (kCFCoreFoundationVersionNumber >= kCFCoreFoundationVersionNumber10_10) {
#endif
            shouldUseCoreSymbolication = YES;
        }
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
