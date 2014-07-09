@class SCBinaryInfo;
@class SCSymbolInfo;
@class VMUMemory_File;

@interface SCSymbolicator : NSObject
@property(nonatomic, copy) NSString *architecture;
@property(nonatomic, copy) NSString *systemRoot;
@property(nonatomic, readonly) NSString *sharedCachePath;
@property(nonatomic, readonly) VMUMemory_File *mappedCache;
+ (SCSymbolicator *)sharedInstance;
- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address inBinary:(SCBinaryInfo *)binaryInfo usingSymbolMap:(NSDictionary *)symbolMap;
@end

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */
