#import "CRStackFrame.h"

@implementation CRStackFrame

@synthesize symbolInfo = symbolInfo_;

- (void)dealloc {
    [symbolInfo_ release];
    [super dealloc];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
