@class SCBinaryInfo;

@interface CRBinaryImage : NSObject
@property(nonatomic, assign) uint64_t address;
@property(nonatomic, assign) uint64_t size;
@property(nonatomic, copy) NSString *architecture;
@property(nonatomic, copy) NSString *uuid;
@property(nonatomic, copy) NSString *path;
@property(nonatomic, getter = isBlamable) BOOL blamable;
@property(nonatomic, readonly) SCBinaryInfo *binaryInfo;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
