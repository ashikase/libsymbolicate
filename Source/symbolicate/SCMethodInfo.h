@interface SCMethodInfo : NSObject
@property(nonatomic, assign) uint64_t address;
@property(nonatomic, copy) NSString *name;
@end

CFComparisonResult reversedCompareMethodInfos(SCMethodInfo *a, SCMethodInfo *b);

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
