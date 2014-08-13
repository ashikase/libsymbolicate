/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for symbolicating memory addresses.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: LGPL v3 (See LICENSE file for details)
 */

#import "SCMethodInfo.h"

@implementation SCMethodInfo @end

CFComparisonResult reversedCompareMethodInfos(SCMethodInfo *a, SCMethodInfo *b) {
    uint64_t aAddr = [a address];
    uint64_t bAddr = [b address];
    return (aAddr > bAddr) ? kCFCompareLessThan : (aAddr < bAddr) ? kCFCompareGreaterThan : kCFCompareEqualTo;
}

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
