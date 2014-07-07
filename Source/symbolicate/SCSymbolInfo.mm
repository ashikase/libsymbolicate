#import "SCSymbolInfo.h"

@implementation SCSymbolInfo

@synthesize name = name_;
@synthesize sourcePath = sourcePath_;

- (void)dealloc {
    [name_ release];
    [sourcePath_ release];
    [super dealloc];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
