@class SCSymbolInfo;

@interface CRStackFrame : NSObject
@property(nonatomic, assign) NSUInteger depth;
@property(nonatomic, assign) uint64_t imageAddress;
@property(nonatomic, assign) uint64_t address;
@property(nonatomic, retain) SCSymbolInfo *symbolInfo;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
