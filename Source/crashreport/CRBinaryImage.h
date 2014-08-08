/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

@class SCBinaryInfo;

@interface CRBinaryImage : NSObject
@property(nonatomic, readonly) NSString *path;
@property(nonatomic, readonly) uint64_t address;
@property(nonatomic, readonly) NSString *architecture;
@property(nonatomic, readonly) NSString *uuid;
@property(nonatomic, readonly) SCBinaryInfo *binaryInfo;
@property(nonatomic, assign) uint64_t size;
@property(nonatomic, getter = isBlamable) BOOL blamable;
@property(nonatomic, getter = isCrashedProcess) BOOL crashedProcess;
@property(nonatomic, readonly) BOOL isFromDebianPackage;
@property(nonatomic, readonly) NSDictionary *packageDetails;
@property(nonatomic, readonly) NSDate *packageInstallDate;
+ (id)new __attribute__((unavailable("Must use custom init method.")));
- (id)init __attribute__((unavailable("Must use custom init method.")));
- (id)initWithPath:(NSString *)path address:(uint64_t)address architecture:(NSString *)architecture uuid:(NSString *)uuid;
@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
