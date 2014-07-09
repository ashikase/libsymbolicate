#import "SCSymbolicator.h"

#import "SCBinaryInfo.h"
#import "SCMethodInfo.h"
#import "SCSymbolInfo.h"

#include "demangle.h"
#include "localSymbols.h"

@implementation SCSymbolicator

@synthesize mappedCache = mappedCache_;
@synthesize sharedCachePath = sharedCachePath_;

+ (instancetype)sharedInstance {
    static dispatch_once_t once;
    static id instance;
    dispatch_once(&once, ^{
        instance = [self new];
    });
    return instance;
}

- (void)dealloc {
    [mappedCache_ release];
    [sharedCachePath_ release];
    [super dealloc];
}

- (void)setSharedCachePath:(NSString *)sharedCachePath {
    if (![sharedCachePath_ isEqualToString:sharedCachePath]) {
        [sharedCachePath_ release];
        if (sharedCachePath != nil) {
            sharedCachePath_ = [sharedCachePath copy];
        } else if ([VMUDyld respondsToSelector:@selector(nativeSharedCachePath)]) {
            sharedCachePath_ = [[VMUDyld nativeSharedCachePath] copy];
        }

        [mappedCache_ release];
        if (sharedCachePath_ != nil) {
            // FIXME: Must architecture be specified? If so, make customizable.
            VMURange range = (VMURange){0, 0};
            mappedCache_ = [[VMUMemory_File alloc] initWithPath:sharedCachePath_ fileRange:range mapToAddress:0 architecture:[VMUArchitecture currentArchitecture]];
            if (mappedCache_ != nil) {
                [mappedCache_ buildSharedCacheMap];
            } else {
                fprintf(stderr, "ERROR: Unable to map shared cache file '%s'.\n", [sharedCachePath_ UTF8String]);
            }
        } else {
            mappedCache_ = nil;
        }
    }
}

- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address inBinary:(SCBinaryInfo *)binaryInfo usingSymbolMap:(NSDictionary *)symbolMap {
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
                CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)symbolAddresses, CFRangeMake(0, count), targetAddress, (CFComparatorFunction)reversedCompareNSNumber, NULL);
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
            } else if (symbolMap != nil) {
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

            if (name != nil) {
                symbolInfo = [SCSymbolInfo new];
                [symbolInfo setName:name];
                [symbolInfo setOffset:offset];
            }
        }
    }

    return symbolInfo;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
