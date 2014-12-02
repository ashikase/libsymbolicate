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
#include <mach-o/loader.h>
#include <objc/runtime.h>
#include "CoreSymbolication.h"

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

uint8_t byteFromHexString(const char *string) {
    unsigned long long result = 0;
    int i;
    for (i = 0; i < 2; ++i) {
        char c = string[i];
        if ((c >= '0') && (c <= '9')) {
            result = result * 16 + (c - '0');
        } else if ((c >= 'a') && (c <= 'f')) {
            result = result * 16 + (c - 'a' + 10);
        } else if ((c >= 'A') && (c <= 'F')) {
            result = result * 16 + (c - 'A' + 10);
        } else if (c != 'x') {
            break;
        }
    }
    return result;
}

CFUUIDBytes CFUUIDBytesFromCString(const char *cstring) {
    CFUUIDBytes bytes;

    size_t len = strlen(cstring);
    if (len >= 32) {
        unsigned i = 0;
        bytes.byte0 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte1 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte2 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte3 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte4 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte5 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte6 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte7 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte8 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte9 =  byteFromHexString(&cstring[i]); i += 2;
        bytes.byte10 = byteFromHexString(&cstring[i]); i += 2;
        bytes.byte11 = byteFromHexString(&cstring[i]); i += 2;
        bytes.byte12 = byteFromHexString(&cstring[i]); i += 2;
        bytes.byte13 = byteFromHexString(&cstring[i]); i += 2;
        bytes.byte14 = byteFromHexString(&cstring[i]); i += 2;
        bytes.byte15 = byteFromHexString(&cstring[i]);
    }

    return bytes;
}

static uint64_t linkCommandOffsetForHeader(VMUMachOHeader *header, uint64_t linkCommand) {
    uint64_t cmdsize = 0;
    Ivar ivar = class_getInstanceVariable(%c(VMULoadCommand), "_command");
    for (VMULoadCommand *lc in [header loadCommands]) {
        uint64_t cmd = (uint64_t)object_getIvar(lc, ivar);
        if (cmd == linkCommand) {
            return [header isMachO64] ?
                sizeof(mach_header_64) + cmdsize :
                sizeof(mach_header) + cmdsize;
        }
        cmdsize += [lc cmdSize];
    }
    return 0;
}

static BOOL isEncrypted(VMUMachOHeader *header) {
    BOOL isEncrypted = NO;

    uint64_t offset = linkCommandOffsetForHeader(header, LC_ENCRYPTION_INFO);
    if (offset != 0) {
        id<VMUMemoryView> view = (id<VMUMemoryView>)[[header memory] view];
        @try {
            [view setCursor:[header address] + offset + 16];
            isEncrypted = ([view uint32] > 0);
        } @catch (NSException *exception) {
            fprintf(stderr, "WARNING: Exception '%s' generated when determining encryption status for %s.\n",
                    [[exception reason] UTF8String], [[header path] UTF8String]);
        }
    }

    return isEncrypted;
}

#define RO_META     (1 << 0)
#define RW_REALIZED (1 << 31)

static NSArray *methodsForImageWithHeader(VMUMachOHeader *header) {
    NSMutableArray *methods = [NSMutableArray array];

    const BOOL isFromSharedCache = [header respondsToSelector:@selector(isFromSharedCache)] && [header isFromSharedCache];
    const BOOL is64Bit = [header isMachO64];

    VMUSegmentLoadCommand *textSeg = [header segmentNamed:@"__TEXT"];
    int64_t vmdiff_text = [textSeg fileoff] - [textSeg vmaddr];

    VMUSegmentLoadCommand *dataSeg = [header segmentNamed:@"__DATA"];
    int64_t vmdiff_data = [dataSeg fileoff] - [dataSeg vmaddr];

    id<VMUMemoryView> view = (id<VMUMemoryView>)[[header memory] view];
    uint64_t viewoff = [view cursor];

    VMUSection *clsListSect = [dataSeg sectionNamed:@"__objc_classlist"];
    @try {
        [view setCursor:(viewoff + [clsListSect offset])];
        const uint64_t numClasses = [clsListSect size] / (is64Bit ? sizeof(uint64_t) : sizeof(uint32_t));
        for (uint64_t i = 0; i < numClasses; ++i) {
            uint64_t class_t_address = is64Bit ? [view uint64] : [view uint32];
            uint64_t next_class_t = [view cursor];

            if (i == 0 && isFromSharedCache) {
                // FIXME: Determine what this offset is and how to properly obtain it.
                VMUSection *sect = [dataSeg sectionNamed:@"__objc_data"];
                vmdiff_data -= (class_t_address - [sect addr]) / 0x1000 * 0x1000;
            }
            [view setCursor:(viewoff + vmdiff_data + class_t_address)];

process_class:
            // Get address for meta class.
            // NOTE: This is needed for retrieving class (non-instance) methods.
            uint64_t isa;
            if (is64Bit) {
                isa = [view uint64];
                [view advanceCursor:24];
            } else {
                isa = [view uint32];
                [view advanceCursor:12];
            }

            // Confirm struct is actually class_ro_t (and not class_rw_t).
            const uint64_t class_ro_t_address = is64Bit ? [view uint64] : [view uint32];
            [view setCursor:(viewoff + vmdiff_data + class_ro_t_address)];
            const uint32_t flags = [view uint32];
            if (!(flags & RW_REALIZED)) {
                const char methodType = (flags & 1) ? '+' : '-';

                uint64_t class_ro_t_name;
                if (is64Bit) {
                    [view advanceCursor:20];
                    class_ro_t_name = [view uint64];
                } else {
                    [view advanceCursor:12];
                    class_ro_t_name = [view uint32];
                }
                if (i == 0 && isFromSharedCache && !(flags & RO_META)) {
                    // FIXME: Determine what this offset is and how to properly obtain it.
                    VMUSection *sect = [textSeg sectionNamed:@"__objc_classname"];
                    vmdiff_text -= (class_ro_t_name - [sect addr]) / 0x1000 * 0x1000;
                }
                [view setCursor:[header address] + vmdiff_text + class_ro_t_name];
                NSString *className = [view stringWithEncoding:NSUTF8StringEncoding];

                uint64_t baseMethods;
                if (is64Bit) {
                    [view setCursor:vmdiff_data + class_ro_t_address + 32];
                    baseMethods = [view uint64];
                } else {
                    [view setCursor:(viewoff + vmdiff_data + class_ro_t_address + 20)];
                    baseMethods = [view uint32];
                }
                if (baseMethods != 0) {
                    [view setCursor:(viewoff + vmdiff_data + baseMethods)];
                    const uint32_t entsize = [view uint32];
                    uint32_t count = [view uint32];
                    for (uint32_t j = 0; j < count; ++j) {
                        SCMethodInfo *mi = [SCMethodInfo new];
                        const uint64_t sel = is64Bit ? [view uint64] : [view uint32];
                        NSString *methodName = nil;
                        if (!is64Bit && ((entsize & 3) == 3)) {
                            // Preoptimized.
                            methodName = [[NSString alloc] initWithCString:(const char *)sel encoding:NSUTF8StringEncoding];
                        } else {
                            // Un-preoptimized.
                            const uint64_t loc = [view cursor];
                            [view setCursor:[header address] + vmdiff_text + sel];
                            methodName = [[view stringWithEncoding:NSUTF8StringEncoding] retain];
                            [view setCursor:loc];
                        }
                        [mi setName:[NSString stringWithFormat:@"%c[%@ %@]", methodType, className, methodName]];
                        [methodName release];
                        if (is64Bit) {
                            [view uint64]; // Skip 'types'
                            [mi setAddress:[view uint64]];
                        } else {
                            [view uint32]; // Skip 'types'
                            [mi setAddress:[view uint32]];
                        }
                        [methods addObject:mi];
                        [mi release];
                    }
                }
            }
            if (!(flags & RO_META)) {
                [view setCursor:(viewoff + vmdiff_data + isa)];
                goto process_class;
            } else {
                [view setCursor:next_class_t];
            }
        }
    } @catch (NSException *exception) {
        fprintf(stderr, "WARNING: Exception '%s' generated when extracting methods for %s.\n",
                [[exception reason] UTF8String], [[header path] UTF8String]);
    }

    [methods sortUsingFunction:(NSInteger (*)(id, id, void *))reversedCompareMethodInfos context:NULL];
    return methods;
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

    CSSymbolicatorRef symbolicatorRef_;
    CSSymbolOwnerRef ownerRef_;
}

@synthesize address = address_;
@synthesize architecture = architecture_;
@synthesize encrypted = encrypted_;
@synthesize executable = executable_;
@synthesize fromSharedCache = fromSharedCache_;
@synthesize header = header_;
@synthesize methods = methods_;
@synthesize owner = owner_;
@synthesize path = path_;
@synthesize slide = slide_;
@synthesize symbolAddresses = symbolAddresses_;
@synthesize uuid = uuid_;

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
    if (shouldUseCoreSymbolication) {
        if (!CSIsNull(symbolicatorRef_)) {
            CSRelease(symbolicatorRef_);
        }
    } else {
        [header_ release];
        [owner_ release];
    }

    [architecture_ release];
    [methods_ release];
    [path_ release];
    [uuid_ release];
    [symbolAddresses_ release];
    [super dealloc];
}

- (NSArray *)methods {
    if (methods_ == nil) {
        methods_ = [methodsForImageWithHeader([self header]) retain];
    }
    return methods_;
}

// NOTE: The symbol addresses array is sorted greatest to least so that it can
//       be used with CFArrayBSearchValues().
- (NSArray *)symbolAddresses {
    if (symbolAddresses_ == nil) {
        symbolAddresses_ = [symbolAddressesForImageWithHeader([self header]) retain];
    }
    return symbolAddresses_;
}

- (VMUSegmentLoadCommand *)segmentNamed:(NSString *)name {
    return [[self header] segmentNamed:name];
}

- (uint64_t)sharedCacheOffset {
    return [[self header] address];
}

- (VMUSourceInfo *)sourceInfoForAddress:(uint64_t)address {
    return [[self owner] sourceInfoForAddress:address];
}

- (VMUSymbol *)symbolForAddress:(uint64_t)address {
    return [[self owner] symbolForAddress:address];
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
                    uint64_t textStart = [[header segmentNamed:@"__TEXT"] vmaddr];
                    slide_ = textStart - [self address];
                    // NOTE: The following method is quite slow.
                    owner_ = [[%c(VMUSymbolExtractor) extractSymbolOwnerFromHeader:header] retain];
                    encrypted_ = isEncrypted(header);
                    executable_ = ([header fileType] == MH_EXECUTE);

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

#pragma mark - Firmware_GTE_80 (CoreSymbolication.framework)

- (CSSymbolicatorRef)symbolicatorRef {
    if (CSIsNull(symbolicatorRef_)) {
        if (shouldUseCoreSymbolication) {
            CSArchitecture arch = CSArchitectureGetArchitectureForName([[self architecture] UTF8String]);
            if (arch.cpu_type != 0) {
                CSSymbolicatorRef symbolicator = CSSymbolicatorCreateWithPathAndArchitecture([[self path] UTF8String], arch);
                if (!CSIsNull(symbolicator)) {
                    symbolicatorRef_ = symbolicator;
                }
            }
        }
    }
    return symbolicatorRef_;
}

- (CSSymbolOwnerRef)ownerRef {
    if (CSIsNull(ownerRef_)) {
        if (shouldUseCoreSymbolication) {
            CSSymbolicatorRef symbolicator = [self symbolicatorRef];
            if (!CSIsNull(symbolicator)) {
                // NOTE: Must ignore "<>" characters in UUID string.
                // FIXME: Do not store the UUID with these characters included.
                CFUUIDBytes uuidBytes = CFUUIDBytesFromCString(&([[self uuid] UTF8String][1]));
                CSSymbolOwnerRef owner = CSSymbolicatorGetSymbolOwnerWithCFUUIDBytesAtTime(symbolicator, &uuidBytes, kCSNow);
                if (!CSIsNull(owner)) {
                    ownerRef_ = owner;
                }
            }
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
