@interface SCMethodInfo : NSObject {
    @package
        uint64_t address;
        NSString *name;
}
@end

CFComparisonResult reversedCompareMethodInfos(SCMethodInfo *a, SCMethodInfo *b);

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
