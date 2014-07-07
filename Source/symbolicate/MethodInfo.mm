#import "MethodInfo.h"

@implementation MethodInfo @end

CFComparisonResult reversedCompareMethodInfos(MethodInfo *a, MethodInfo *b) {
    return (a->address > b->address) ? kCFCompareLessThan : (a->address < b->address) ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
