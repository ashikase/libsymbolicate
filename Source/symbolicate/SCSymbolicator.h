@class SCBinaryInfo;
@class SCSymbolInfo;

@interface SCSymbolicator : NSObject
- (SCSymbolInfo *)symbolInfoForAddress:(uint64_t)address inBinary:(SCBinaryInfo *)binaryInfo usingSymbolMap:(NSDictionary *)symbolMap;
@end

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */
