#import "SCMethodInfo.h"

@implementation SCMethodInfo @end

CFComparisonResult reversedCompareMethodInfos(SCMethodInfo *a, SCMethodInfo *b) {
    uint64_t aAddr = [a address];
    uint64_t bAddr = [b address];
    return (aAddr > bAddr) ? kCFCompareLessThan : (aAddr < bAddr) ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
