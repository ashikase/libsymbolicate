#import "CRBacktrace.h"

@interface CRException : CRBacktrace
@property(nonatomic, copy) NSString *type;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
