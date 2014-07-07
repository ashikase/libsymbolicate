@class CRStackFrame;

@interface CRBacktrace : NSObject
@property(nonatomic, readonly) NSArray *stackFrames;
- (void)addStackFrame:(CRStackFrame *)stackFrame;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
