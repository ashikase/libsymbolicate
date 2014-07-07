#import "CRBacktrace.h"

@implementation CRBacktrace {
    NSMutableArray *stackFrames_;
}

@dynamic stackFrames;

- (id)init {
    self = [super init];
    if (self != nil) {
        stackFrames_ = [NSMutableArray new];
    }
    return self;
}

- (void)dealloc {
    [stackFrames_ release];
    [super dealloc];
}

- (NSArray *)stackFrames {
    return [NSArray arrayWithArray:stackFrames_];
}

- (void)addStackFrame:(CRStackFrame *)stackFrame {
    NSParameterAssert(stackFrame);
    [stackFrames_ addObject:stackFrame];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
