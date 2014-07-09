/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

#import "CRBinaryImage.h"

#import "SCBinaryInfo.h"

@implementation CRBinaryImage

@synthesize architecture = architecture_;
@synthesize uuid = uuid_;
@synthesize path = path_;
@synthesize binaryInfo = binaryInfo_;
@synthesize blamable = blamable_;

- (id)init {
    self = [super init];
    if (self != nil) {
        blamable_ = YES;
    }
    return self;
}

- (void)dealloc {
    [architecture_ release];
    [uuid_ release];
    [path_ release];
    [binaryInfo_ release];
    [super dealloc];
}

- (SCBinaryInfo *)binaryInfo {
    if (binaryInfo_ == nil) {
        binaryInfo_ = [[SCBinaryInfo alloc] initWithPath:[self path] address:[self address]];
    }
    return binaryInfo_;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
