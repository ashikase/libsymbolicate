#import "CRThread.h"

@implementation CRThread

@synthesize name = name_;

- (void)dealloc {
    [name_ release];
    [super dealloc];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
