/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#import "CRBacktrace.h"

@interface CRThread : CRBacktrace
@property(nonatomic, copy) NSString *name;
@property(nonatomic, assign) BOOL crashed;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
