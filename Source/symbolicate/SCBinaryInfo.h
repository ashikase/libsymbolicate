/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#import <Foundation/Foundation.h>

#include "Headers.h"

@interface SCBinaryInfo : NSObject
@property(nonatomic, readonly) uint64_t address;
@property(nonatomic, readonly, getter = isEncrypted) BOOL encrypted;
@property(nonatomic, readonly, getter = isExecutable) BOOL executable;
@property(nonatomic, readonly, getter = isFromSharedCache) BOOL fromSharedCache;
@property(nonatomic, readonly) VMUMachOHeader *header;
@property(nonatomic, readonly) NSArray *methods;
@property(nonatomic, readonly) VMUSymbolOwner *owner;
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) int64_t slide;
@property(nonatomic, readonly) NSArray *symbolAddresses;
- (id)initWithPath:(NSString *)path address:(uint64_t)address;
@end

CFComparisonResult reversedCompareNSNumber(NSNumber *a, NSNumber *b);

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
