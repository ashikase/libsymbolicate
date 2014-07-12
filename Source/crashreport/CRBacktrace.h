/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

@class CRStackFrame;

@interface CRBacktrace : NSObject
@property(nonatomic, readonly) NSArray *stackFrames;
- (void)addStackFrame:(CRStackFrame *)stackFrame;
- (NSString *)stringRepresentation;
- (NSString *)stringRepresentationUsingBinaryImages:(NSDictionary *)binaryImages;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
