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
#import "dpkg_util.h"

static NSString * const kDebianPackageInfoPath = @"/var/lib/dpkg/info";

static NSSet *filesFromDebianPackages$ = nil;

static NSSet *setOfFilesFromDebianPackages() {
    NSMutableString *filelist = [NSMutableString new];

    // Retrieve a list of all files that come from Debian packages.
    // NOTE: List will contain files of all types, not just binaries with
    //       executable code.
    NSFileManager *fileMan = [NSFileManager defaultManager];
    NSError *error = nil;
    NSArray *contents = [fileMan contentsOfDirectoryAtPath:kDebianPackageInfoPath error:&error];
    if (contents != nil) {
        for (NSString *file in contents) {
            if ([file hasSuffix:@".list"]) {
                NSString *filepath = [kDebianPackageInfoPath stringByAppendingPathComponent:file];
                NSString *string = [[NSString alloc] initWithContentsOfFile:filepath encoding:NSUTF8StringEncoding error:&error];
                if (string != nil) {
                    [filelist appendString:string];
                } else {
                    fprintf(stderr, "ERROR: Failed to read contents of file \"%s\": %s.\n",
                            [filepath UTF8String], [[error localizedDescription] UTF8String]);
                }
                [string release];
            }
        }
    } else {
        fprintf(stderr, "ERROR: Failed to get contents of dpkg info directory: %s.\n", [[error localizedDescription] UTF8String]);
    }

    // Convert list into a unique set.
    NSSet *set = [[NSSet alloc] initWithArray:[filelist componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]]];

    // Clean-up.
    [filelist release];

    return [set autorelease];
}

@implementation CRBinaryImage

@synthesize address = address_;
@synthesize path = path_;
@synthesize architecture = architecture_;
@synthesize uuid = uuid_;
@synthesize binaryInfo = binaryInfo_;
@synthesize blamable = blamable_;
@synthesize packageDetails = packageDetails_;

@dynamic isFromDebianPackage;

+ (void)initialize {
    if (self == [CRBinaryImage class]) {
        filesFromDebianPackages$ = [setOfFilesFromDebianPackages() retain];
    }
}

- (id)initWithPath:(NSString *)path address:(uint64_t)address architecture:(NSString *)architecture uuid:(NSString *)uuid {
    self = [super init];
    if (self != nil) {
        path_ = [path copy];
        address_ = address;
        architecture_ = [architecture copy];
        uuid_ = [uuid copy];
        blamable_ = YES;
    }
    return self;
}

- (void)dealloc {
    [architecture_ release];
    [uuid_ release];
    [path_ release];
    [binaryInfo_ release];
    [packageDetails_ release];
    [super dealloc];
}

- (SCBinaryInfo *)binaryInfo {
    if (binaryInfo_ == nil) {
        NSString *path = [self path];
        uint64_t address = [self address];
        NSString *architecture = [self architecture];
        NSString *uuid = [self uuid];
        NSCAssert((path != nil) && (address != 0) && (architecture != nil) && (uuid != nil),
            @"ERROR: Must first set path, address, architecture and uuid of binary image before retrieving binary info.");
        binaryInfo_ = [[SCBinaryInfo alloc] initWithPath:path address:address architecture:architecture uuid:uuid];
    }
    return binaryInfo_;
}

- (BOOL)isFromDebianPackage {
    return [filesFromDebianPackages$ containsObject:[self path]];
}

- (NSDictionary *)packageDetails {
    if (packageDetails_ == nil) {
        // Device has same binary image as the report; retrieve package details.
        // NOTE: It is possible that multiple versions of a package could
        //       contain the same binary image... other contained files,
        //       such as a configuration or data file that the binary uses,
        //       may have changed.
        //       Due to this, the package details retrieved from the
        //       symbolicating device may not be the correct details for the
        //       package on the crashing device. This can be true even if
        //       the symbolicating and crashing devices are the same... if
        //       the package is up/downgraded between the time of the crash
        //       and the time of the symbolication.
        NSString *identifier = identifierForDebianPackageContainingFile([self path]);
        packageDetails_ = [detailsForDebianPackageWithIdentifier(identifier) retain];
    }
    return packageDetails_;
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
