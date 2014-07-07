#import "CRBacktrace.h"

@interface CRThread : CRBacktrace
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) BOOL crashed;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
