#import "CRException.h"

@implementation CRException

@synthesize type = type_;

- (void)dealloc {
    [type_ release];
    [super dealloc];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
