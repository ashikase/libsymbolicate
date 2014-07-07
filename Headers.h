#ifndef SYMBOLICATE_HEADERS_H_
#define SYMBOLICATE_HEADERS_H_

typedef struct _VMURange {
    uint64_t location;
    uint64_t length;
} VMURange;

@interface VMUSymbolicator : NSObject @end

@interface VMUAddressRange : NSObject <NSCoding> @end
@interface VMUArchitecture : NSObject <NSCoding, NSCopying>
+ (id)architectureWithCpuType:(int)cpuType cpuSubtype:(int)subtype;
+ (id)currentArchitecture;
@end
@interface VMUDyld : NSObject
+ (id)nativeSharedCachePath;
@end
@interface VMUHeader : NSObject
+ (id)extractMachOHeadersFromHeader:(id)header matchingArchitecture:(id)architecture considerArchives:(BOOL)archives;
- (BOOL)isMachO64;
@end
@interface VMULoadCommand : NSObject
- (uint64_t)cmdSize;
@end
@interface VMUMachOHeader : VMUHeader
- (uint64_t)address;
- (uint32_t)fileType;
- (BOOL)isFromSharedCache;
- (id)loadCommands;
- (id)memory;
- (id)path;
- (id)segmentNamed:(id)named;
@end
@protocol VMUMemory <NSObject>
- (VMURange)addressRange;
- (id)view;
@end
@protocol VMUMemoryView <NSObject>
- (void)advanceCursor:(uint64_t)cursor;
- (uint64_t)cursor;
- (void)setCursor:(uint64_t)cursor;
- (id)stringWithEncoding:(unsigned)encoding;
- (uint32_t)uint32;
- (uint64_t)uint64;
- (uint64_t)ULEB128;
@end
@interface VMUMemory_Base : NSObject @end
@interface VMUMemory_File : VMUMemory_Base <VMUMemory>
+ (id)headerFromSharedCacheWithPath:(id)path;
+ (id)headerWithPath:(id)path;
- (void)buildSharedCacheMap;
- (id)initWithPath:(id)path fileRange:(VMURange)range mapToAddress:(uint64_t)address architecture:(id)architecture;
@end
@interface VMUMemory_Handle : VMUMemory_Base <VMUMemory> @end
@interface VMUSourceInfo : VMUAddressRange <NSCopying>
- (unsigned)lineNumber;
- (id)path;
@end
@interface VMUSection : NSObject
- (uint64_t)addr;
- (uint32_t)offset;
- (uint64_t)size;
@end
@interface VMUSegmentLoadCommand : VMULoadCommand
- (uint64_t)fileoff;
- (id)sectionNamed:(id)named;
- (uint64_t)vmaddr;
@end
@interface VMUSymbol : VMUAddressRange <NSCopying>
- (VMURange)addressRange;
- (id)name;
@end
@interface VMUSymbolExtractor : NSObject
+ (id)extractSymbolOwnerFromHeader:(id)header;
@end
@interface VMUSymbolOwner : NSObject <NSCopying>
- (id)sourceInfoForAddress:(uint64_t)address;
- (id)symbolForAddress:(uint64_t)address;
@end

#endif // SYMBOLICATE_HEADERS_H_

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */
