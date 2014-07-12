/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#import "CRBacktrace.h"

#import "CRBinaryImage.h"
#import "CRStackFrame.h"
#import "SCBinaryInfo.h"
#import "SCSymbolInfo.h"

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

- (NSString *)stringRepresentation {
    return [self stringRepresentationUsingBinaryImages:nil];
}

- (NSString *)stringRepresentationUsingBinaryImages:(NSDictionary *)binaryImages {
    NSMutableString *string = [NSMutableString string];

    for (CRStackFrame *stackFrame in [self stackFrames]) {
        uint64_t address = [stackFrame address];
        uint64_t imageAddress = [stackFrame imageAddress];
        NSString *addressString = [[NSString alloc] initWithFormat:@"0x%08llx 0x%08llx + 0x%llx",
                 address, imageAddress, address - imageAddress];

        NSNumber *key = [NSNumber numberWithUnsignedLongLong:imageAddress];
        CRBinaryImage *binaryImage = [binaryImages objectForKey:key];
        NSString *binaryName = (binaryImage == nil) ?
            @"???" :
            [[[binaryImage path] lastPathComponent] stringByAppendingString:([[binaryImage binaryInfo] isExecutable] ? @" (*)" : @"")];

        NSString *comment = nil;
        SCSymbolInfo *symbolInfo = [stackFrame symbolInfo];
        if (symbolInfo != nil) {
            NSString *sourcePath = [symbolInfo sourcePath];
            if (sourcePath != nil) {
                comment = [[NSString alloc] initWithFormat:@"\t// %@:%lu", sourcePath, (unsigned long)[symbolInfo sourceLineNumber]];
            } else {
                NSString *name = [symbolInfo name];
                if (name != nil) {
                    comment = [[NSString alloc] initWithFormat:@"\t// %@ + 0x%llx", name, [symbolInfo offset]];
                }
            }
        }

        NSString *line = [[NSString alloc] initWithFormat:@"%-6lu%s%-30s\t%-32s%@",
                 (unsigned long)[stackFrame depth], [binaryImage isBlamable] ? "+ " : "  ", [binaryName UTF8String],
                 [addressString UTF8String], comment ?: @""];
        [addressString release];
        [comment release];

        [string appendString:line];
        [string appendString:@"\n"];
        [line release];
    }
    [string appendString:@"\n"];

    return string;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
