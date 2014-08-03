/**
 * Name: libsymbolicate
 * Type: iOS/OS X shared library
 * Desc: Library for parsing and symbolicating iOS crash log files.
 *
 * Author: Lance Fetters (aka. ashikase)
 * License: GPL v3 (See LICENSE file for details)
 */

@class NSString, NSDictionary;

extern NSString * const kCrashReportBlame;
extern NSString * const kCrashReportDescription;
extern NSString * const kCrashReportSymbolicated;

typedef enum {
    CRCrashReportFilterTypeNone,
    CRCrashReportFilterTypeFile,
    CRCrashReportFilterTypePackage
} CRCrashReportFilterType;

@class CRException;

@interface CRCrashReport : NSObject
@property(nonatomic, readonly) NSDictionary *properties;
@property(nonatomic, readonly) NSDictionary *processInfo;
@property(nonatomic, readonly) CRException *exception;
@property(nonatomic, readonly) NSArray *threads;
@property(nonatomic, readonly) NSArray *registerState;
@property(nonatomic, readonly) NSDictionary *binaryImages;
@property(nonatomic, readonly) BOOL isPropertyList;
@property(nonatomic, readonly) BOOL isSymbolicated;
+ (CRCrashReport *)crashReportWithData:(NSData *)data;
+ (CRCrashReport *)crashReportWithData:(NSData *)data filterType:(CRCrashReportFilterType)filterType;
+ (CRCrashReport *)crashReportWithFile:(NSString *)filepath;
+ (CRCrashReport *)crashReportWithFile:(NSString *)filepath filterType:(CRCrashReportFilterType)filterType;
- (id)initWithData:(NSData *)data;
- (id)initWithData:(NSData *)data filterType:(CRCrashReportFilterType)filterType;
- (id)initWithFile:(NSString *)filepath;
- (id)initWithFile:(NSString *)filepath filterType:(CRCrashReportFilterType)filterType;
- (BOOL)blame;
- (BOOL)blameUsingFilters:(NSDictionary *)filters;
- (NSString *)stringRepresentation;
- (NSString *)stringRepresentation:(BOOL)asPropertyList;
- (BOOL)symbolicate;
- (BOOL)symbolicateUsingSystemRoot:(NSString *)systemRoot symbolMaps:(NSDictionary *)symbolMaps;
@end

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */
