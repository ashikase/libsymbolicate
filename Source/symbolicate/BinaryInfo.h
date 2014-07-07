#import <Foundation/Foundation.h>

#include "Headers.h"

@interface BinaryInfo : NSObject
@property(nonatomic, readonly) uint64_t address;
@property(nonatomic, readonly, getter = isEncrypted) BOOL encrypted;
@property(nonatomic, readonly, getter = isExecutable) BOOL executable;
@property(nonatomic, readonly) VMUMachOHeader *header;
@property(nonatomic, readonly) NSArray *methods;
@property(nonatomic, readonly) VMUSymbolOwner *owner;
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) int64_t slide;
@property(nonatomic, readonly) NSArray *symbolAddresses;

@property(nonatomic, getter = isBlamable) BOOL blamable;
@property(nonatomic) NSUInteger line;

@property(nonatomic, assign) uint64_t size;
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *architecture;

- (id)initWithPath:(NSString *)path address:(uint64_t)address;
@end

CFComparisonResult reversedCompareNSNumber(NSNumber *a, NSNumber *b);

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
