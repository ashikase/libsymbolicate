@interface MethodInfo : NSObject {
    @package
        uint64_t address;
        NSString *name;
}
@end

CFComparisonResult reversedCompareMethodInfos(MethodInfo *a, MethodInfo *b);

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
