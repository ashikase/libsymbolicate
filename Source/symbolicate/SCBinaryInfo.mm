#import "SCBinaryInfo.h"

#import "SCMethodInfo.h"
#include <mach-o/loader.h>
#include <objc/runtime.h>

static uint64_t linkCommandOffsetForHeader(VMUMachOHeader *header, uint64_t linkCommand) {
    uint64_t cmdsize = 0;
    Ivar ivar = class_getInstanceVariable([VMULoadCommand class], "_command");
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
    VMUSection *clsListSect = [dataSeg sectionNamed:@"__objc_classlist"];
    @try {
        [view setCursor:[clsListSect offset]];
        const uint64_t numClasses = [clsListSect size] / (is64Bit ? sizeof(uint64_t) : sizeof(uint32_t));
        for (uint64_t i = 0; i < numClasses; ++i) {
            uint64_t class_t_address = is64Bit ? [view uint64] : [view uint32];
            uint64_t next_class_t = [view cursor];

            if (i == 0 && isFromSharedCache) {
                // FIXME: Determine what this offset is and how to properly obtain it.
                VMUSection *sect = [dataSeg sectionNamed:@"__objc_data"];
                vmdiff_data -= (class_t_address - [sect addr]) / 0x1000 * 0x1000;
            }
            [view setCursor:vmdiff_data + class_t_address];

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
            [view setCursor:vmdiff_data + class_ro_t_address];
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
                    [view setCursor:vmdiff_data + class_ro_t_address + 40];
                    baseMethods = [view uint64];
                } else {
                [view setCursor:vmdiff_data + class_ro_t_address + 20];
                    baseMethods = [view uint32];
                }
                if (baseMethods != 0) {
                    [view setCursor:vmdiff_data + baseMethods];
                    const uint32_t entsize = [view uint32];
                    if (entsize == 12 || entsize == 15) {
                        uint32_t count = [view uint32];
                        for (uint32_t j = 0; j < count; ++j) {
                            SCMethodInfo *mi = [SCMethodInfo new];
                            const uint64_t sel = is64Bit ? [view uint64] : [view uint32];
                            NSString *methodName = nil;
                            if (entsize == 15) {
                                // Pre-optimized selector
                                methodName = [[NSString alloc] initWithCString:(const char *)sel encoding:NSUTF8StringEncoding];
                            } else {
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
            }
            if (!(flags & RO_META)) {
                [view setCursor:vmdiff_data + isa];
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

CFComparisonResult reversedCompareNSNumber(NSNumber *a, NSNumber *b) {
    return [b compare:a];
}

static NSArray *symbolAddressesForImageWithHeader(VMUMachOHeader *header) {
    NSMutableArray *addresses = [NSMutableArray array];

    uint64_t offset = linkCommandOffsetForHeader(header, LC_FUNCTION_STARTS);
    if (offset != 0) {
        id<VMUMemoryView> view = (id<VMUMemoryView>)[[header memory] view];
        @try {
            [view setCursor:[header address] + offset + 8];
            uint32_t dataoff = [view uint32];
            [view setCursor:dataoff];
            uint64_t offset;
            uint64_t symbolAddress = [[header segmentNamed:@"__TEXT"] vmaddr];
            while ((offset = [view ULEB128])) {
                symbolAddress += offset;
                [addresses addObject:[NSNumber numberWithUnsignedLongLong:symbolAddress]];
            }
        } @catch (NSException *exception) {
            fprintf(stderr, "WARNING: Exception '%s' generated when extracting symbol addresses for %s.\n",
                    [[exception reason] UTF8String], [[header path] UTF8String]);
        }
    }

    [addresses sortUsingFunction:(NSInteger (*)(id, id, void *))reversedCompareNSNumber context:NULL];
    return addresses;
}

@implementation SCBinaryInfo

@synthesize header = _header;
@synthesize methods = _methods;
@synthesize symbolAddresses = _symbolAddresses;

- (id)initWithPath:(NSString *)path address:(uint64_t)address {
    self = [super init];
    if (self != nil) {
        _path = [path copy];
        _address = address;
    }
    return self;
}

- (void)dealloc {
    [_header release];
    [_methods release];
    [_owner release];
    [_path release];
    [_symbolAddresses release];
    [super dealloc];
}

- (VMUMachOHeader *)header {
    if (_header == nil) {
        // Get Mach-O header for the image
        VMUMachOHeader *header = nil;
        BOOL hasHeaderFromSharedCacheWithPath = [VMUMemory_File respondsToSelector:@selector(headerFromSharedCacheWithPath:)];
        if (hasHeaderFromSharedCacheWithPath) {
            header = [VMUMemory_File headerFromSharedCacheWithPath:_path];
            if (header != nil) {
                _fromSharedCache = YES;
            }
        }
        if (header == nil) {
            header = [VMUMemory_File headerWithPath:_path];
        }
        if (![header isKindOfClass:[VMUMachOHeader class]]) {
            header = [[VMUHeader extractMachOHeadersFromHeader:header matchingArchitecture:[VMUArchitecture currentArchitecture] considerArchives:NO] lastObject];
        }
        if (header != nil) {
            uint64_t textStart = [[header segmentNamed:@"__TEXT"] vmaddr];
            _slide = textStart - _address;
            _owner = [[VMUSymbolExtractor extractSymbolOwnerFromHeader:header] retain];
            _encrypted = isEncrypted(header);
            _executable = ([header fileType] == MH_EXECUTE);

            _header = [header retain];
        }
    }
    return _header;
}

- (NSArray *)methods {
    if (_methods == nil) {
        _methods = [methodsForImageWithHeader([self header]) retain];
    }
    return _methods;
}

- (NSArray *)symbolAddresses {
    if (_symbolAddresses == nil) {
        _symbolAddresses = [symbolAddressesForImageWithHeader([self header]) retain];
    }
    return _symbolAddresses;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
