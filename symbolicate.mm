/*

symbolicate.m ... Symbolicate a crash log.
Copyright (C) 2009  KennyTM~ <kennytm@gmail.com>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

*/

#import "symbolicate.h"

#import "BinaryInfo.h"
#import "MethodInfo.h"
#import "SymbolInfo.h"

#include "demangle.h"
#include "localSymbols.h"

SymbolInfo *fetchSymbolInfo(BinaryInfo *bi, uint64_t address, NSDictionary *symbolMap) {
    SymbolInfo *symbolInfo = nil;

    VMUMachOHeader *header = [bi header];
    if (header != nil) {
        address += [bi slide];
        VMUSymbolOwner *owner = [bi owner];
        VMUSourceInfo *srcInfo = [owner sourceInfoForAddress:address];
        if (srcInfo != nil) {
            // Store source file name and line number.
            symbolInfo = [SymbolInfo new];
            [symbolInfo setSourcePath:[srcInfo path]];
            [symbolInfo setSourceLineNumber:[srcInfo lineNumber]];
        } else {
            // Determine symbol address.
            // NOTE: Only possible if LC_FUNCTION_STARTS exists in the binary.
            uint64_t symbolAddress = 0;
            NSArray *symbolAddresses = [bi symbolAddresses];
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
                    // FIXME: Why is this check here?
                    BOOL hasHeaderFromSharedCacheWithPath = [VMUMemory_File respondsToSelector:@selector(headerFromSharedCacheWithPath:)];
                    if (hasHeaderFromSharedCacheWithPath) {
                        NSString *localName = nameForLocalSymbol([header address], [symbol addressRange].location);
                        if (localName != nil) {
                            name = localName;
                        } else {
                            fprintf(stderr, "Unable to determine name for: %s, 0x%08llx\n", [[bi path] UTF8String], [symbol addressRange].location);
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
            } else if (![bi isEncrypted]) {
                // Determine methods, attempt to match with symbol address.
                if (symbolAddress != 0) {
                    MethodInfo *method = nil;
                    NSArray *methods = [bi methods];
                    count = [methods count];
                    if (count != 0) {
                        MethodInfo *targetMethod = [[MethodInfo alloc] init];
                        targetMethod->address = address;
                        CFIndex matchIndex = CFArrayBSearchValues((CFArrayRef)methods, CFRangeMake(0, count), targetMethod, (CFComparatorFunction)reversedCompareMethodInfos, NULL);
                        [targetMethod release];

                        if (matchIndex < (CFIndex)count) {
                            method = [methods objectAtIndex:matchIndex];
                        }
                    }

                    if (method != nil && method->address >= symbolAddress) {
                        name = method->name;
                        offset = address - method->address;
                    } else {
                        uint64_t textStart = [[header segmentNamed:@"__TEXT"] vmaddr];
                        name = [NSString stringWithFormat:@"0x%08llx", (symbolAddress - textStart)];
                        offset = address - symbolAddress;
                    }
                }
            }

            if (name != nil) {
                symbolInfo = [SymbolInfo new];
                [symbolInfo setName:name];
                [symbolInfo setOffset:offset];
            }
        }
    }

    return symbolInfo;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
