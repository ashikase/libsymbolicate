#import "CRCrashReport.h"

#import <RegexKitLite/RegexKitLite.h>
#import "CRException.h"
#import "CRThread.h"
#import "CRStackFrame.h"

#import "SCBinaryInfo.h"
#import "symbolicate.h"
#import "SCSymbolInfo.h"
#include <notify.h>
#include "common.h"

static NSString * const kCrashReportBlame = @"blame";
static NSString * const kCrashReportDescription = @"description";

static uint64_t uint64FromHexString(NSString *string) {
    return (uint64_t)unsignedLongLongFromHexString([string UTF8String], [string length]);
}

@interface CRCrashReport ()
@property(nonatomic, retain) NSDictionary *properties;
@property(nonatomic, retain) NSArray *processInfo;
@property(nonatomic, retain) CRException *exception;
@property(nonatomic, retain) NSArray *threads;
@property(nonatomic, retain) NSArray *registerState;
@property(nonatomic, retain) NSDictionary *binaryImages;
@property(nonatomic, assign) BOOL isPropertyList;
@end

@implementation CRCrashReport

@synthesize properties = properties_;
@synthesize processInfo = processInfo_;
@synthesize exception = exception_;
@synthesize threads = threads_;
@synthesize registerState = registerState_;
@synthesize binaryImages = binaryImages_;

#pragma mark - Public API (Creation)

+ (CRCrashReport *)crashReportWithData:(NSData *)data {
    return [[[self alloc] initWithData:data] autorelease];
}

+ (CRCrashReport *)crashReportWithFile:(NSString *)filepath {
    return [[[self alloc] initWithFile:filepath] autorelease];
}

- (id)initWithData:(NSData *)data {
    self = [super init];
    if (self != nil) {
        // Attempt to load data as a property list.
        id plist = nil;
        if (kCFCoreFoundationVersionNumber < kCFCoreFoundationVersionNumber_iOS_4_0) {
            plist = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:0 format:NULL errorDescription:NULL];
        } else {
            plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
        }

        if (plist != nil) {
            // Confirm that input file is a crash log.
            if ([plist isKindOfClass:[NSDictionary class]] && [plist objectForKey:@"SysInfoCrashReporterKey"] != nil) {
                properties_ = [plist retain];
                [self setIsPropertyList:YES];
            } else {
                fprintf(stderr, "ERROR: Input file is not a valid PLIST crash report.\n");
                [self release];
                return nil;
            }
        } else {
            // Assume file is of IPS format.
            if (NSClassFromString(@"NSJSONSerialization") == nil) {
                fprintf(stderr, "ERROR: This version of iOS does not include NSJSONSerialization, which is required for parsing IPS files.\n");
                [self release];
                return nil;
            }

            NSString *string = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
            NSRange range = [string rangeOfCharacterFromSet:[NSCharacterSet newlineCharacterSet]];
            if ((range.location != NSNotFound) && ((range.location + 1) < [string length])) {
                NSString *header = [string substringToIndex:range.location];
                NSString *description = [string substringFromIndex:(range.location + 1)];
                NSError *error = nil;
                id object = [NSJSONSerialization JSONObjectWithData:[header dataUsingEncoding:NSUTF8StringEncoding] options:0 error:&error];
                if (object != nil) {
                    if ([object isKindOfClass:[NSDictionary class]]) {
                        NSMutableDictionary *dict = [[NSMutableDictionary alloc] initWithDictionary:object];
                        [dict setObject:description forKey:kCrashReportDescription];
                        properties_ = dict;
                    } else {
                        fprintf(stderr, "ERROR: IPS header is not correct format.\n");
                        [self release];
                        return nil;
                    }
                } else {
                    fprintf(stderr, "ERROR: Unable to parse IPS file header: %s.\n", [[error localizedDescription] UTF8String]);
                    [self release];
                    return nil;
                }
            } else {
                fprintf(stderr, "ERROR: Input file is not a valid IPS crash report.\n");
                [self release];
                return nil;
            }
        }

        [self parse];
    }
    return self;
}

- (id)initWithFile:(NSString *)filepath {
    NSError *error = nil;
    NSData *data = [[NSData alloc] initWithContentsOfFile:filepath options:0 error:&error];
    if (data != nil) {
        return [self initWithData:[data autorelease]];
    } else {
        fprintf(stderr, "ERROR: Unable to load data from specified file: \"%s\".\n", [[error localizedDescription] UTF8String]);
        [self release];
        return nil;
    }
}

- (void)dealloc {
    [properties_ release];
    [processInfo_ release];
    [exception_ release];
    [threads_ release];
    [registerState_ release];
    [binaryImages_ release];
    [super dealloc];
}

#pragma mark - Public API (General)

- (BOOL)blame {
    return [self blameUsingFilters:nil];
}

- (BOOL)blameUsingFilters:(NSDictionary *)filters {
    // Load blame filters.
    NSSet *binaryFilters = [[NSSet alloc] initWithArray:[filters objectForKey:@"BinaryFilters"]];
    NSSet *exceptionFilters = [[NSSet alloc] initWithArray:[filters objectForKey:@"ExceptionFilters"]];
    NSSet *functionFilters = [[NSSet alloc] initWithArray:[filters objectForKey:@"FunctionFilters"]];
    NSSet *prefixFilters = [[NSSet alloc] initWithArray:[filters objectForKey:@"PrefixFilters"]];
    NSSet *reverseFilters = [[NSSet alloc] initWithArray:[filters objectForKey:@"ReverseFunctionFilters"]];

    NSDictionary *binaryImages = [self binaryImages];

    // If exception type is not white-listed, process blame.
    CRException *exception = [self exception];
    if (![exceptionFilters containsObject:[exception type]]) {
        // Mark which binary images are unblamable.
        BOOL hasHeaderFromSharedCacheWithPath = [VMUMemory_File respondsToSelector:@selector(headerFromSharedCacheWithPath:)];
        for (NSNumber *key in binaryImages) {
            SCBinaryInfo *bi = [binaryImages objectForKey:key];

            // Determine if binary image should not be blamed.
            BOOL blamable = YES;
            if (hasHeaderFromSharedCacheWithPath && [[bi header] isFromSharedCache]) {
                // Don't blame anything from the shared cache.
                blamable = NO;
            } else {
                // Don't blame white-listed binaries (e.g. libraries).
                NSString *path = [bi path];
                if ([binaryFilters containsObject:path]) {
                    blamable = NO;
                } else {
                    // Don't blame white-listed folders.
                    for (NSString *prefix in prefixFilters) {
                        if ([path hasPrefix:prefix]) {
                            blamable = NO;
                            break;
                        }
                    }
                }
            }
            [bi setBlamable:blamable];
        }

        // Update the description to reflect any changes in blamability.
        [self updateDescription];

        // Retrieve the thread that crashed
        CRThread *crashedThread = nil;
        for (CRThread *thread in [self threads]) {
            if ([thread crashed]) {
                crashedThread = thread;
                break;
            }
        }

        // Determine blame.
        NSMutableArray *blame = [NSMutableArray new];

        // NOTE: We first look at any exception backtrace, and then the
        //       backtrace of the thread that crashed.
        NSMutableArray *backtraces = [NSMutableArray new];
        NSArray *stackFrames = [[self exception] stackFrames];
        if (stackFrames != nil) {
            [backtraces addObject:stackFrames];
        }
        stackFrames = [crashedThread stackFrames];
        if (stackFrames != nil) {
            [backtraces addObject:stackFrames];
        }
        for (NSArray *stackFrames in backtraces) {
            for (CRStackFrame *stackFrame in stackFrames) {
                // Retrieve info for related binary image.
                NSNumber *imageAddress = [NSNumber numberWithUnsignedLongLong:[stackFrame imageAddress]];
                SCBinaryInfo *bi = [binaryImages objectForKey:imageAddress];
                if (bi != nil) {
                    // Check symbol name of system functions against blame filters.
                    BOOL blamable = [bi isBlamable];
                    NSString *path = [bi path];
                    if ([path isEqualToString:@"/usr/lib/libSystem.B.dylib"]) {
                        SCSymbolInfo *symbolInfo = [stackFrame symbolInfo];
                        if (symbolInfo != nil) {
                            NSString *name = [symbolInfo name];
                            if (name != nil) {
                                if (blamable) {
                                    // Check if this function should never cause crash (only hang).
                                    if ([functionFilters containsObject:name]) {
                                        blamable = NO;
                                    }
                                } else {
                                    // Check if this function is actually causing crash.
                                    if ([reverseFilters containsObject:name]) {
                                        blamable = YES;
                                    }
                                }
                            }
                        }
                    }

                    // Determine if binary image should be blamed.
                    if (blamable) {
                        if (![blame containsObject:path]) {
                            [blame addObject:path];
                        }
                    }
                }
            }
        }

        // Update the property dictionary.
        NSMutableDictionary *properties = [[NSMutableDictionary alloc] initWithDictionary:[self properties]];
        [properties setObject:blame forKey:kCrashReportBlame];
        [blame release];
        [self setProperties:properties];
        [properties release];
    }

    [binaryFilters release];
    [exceptionFilters release];
    [functionFilters release];
    [prefixFilters release];
    [reverseFilters release];

    // NOTE: Currently, this always 'succeeds'.
    return YES;
}

- (NSString *)stringRepresentation {
    return [self stringRepresentation:[self isPropertyList]];
}

- (NSString *)stringRepresentation:(BOOL)asPropertyList {
    NSString *result = nil;

    if (asPropertyList) {
        // Generate property list string.
        NSError *error = nil;
        NSData *data = [NSPropertyListSerialization dataWithPropertyList:[self properties] format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
        if (data != nil) {
            result = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        } else {
            fprintf(stderr, "ERROR: Unable to convert report to data: \"%s\".\n", [[error localizedDescription] UTF8String]);
        }
    } else {
        // Generate IPS string.
        NSDictionary *properties = [self properties];
        NSMutableDictionary *header = [[NSMutableDictionary alloc] initWithDictionary:properties];
        [header removeObjectForKey:kCrashReportDescription];
        NSString *description = [properties objectForKey:kCrashReportDescription];

        NSError *error = nil;
        NSData *data = [NSJSONSerialization dataWithJSONObject:header options:0 error:&error];
        if (data != nil) {
            NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            result = [[NSString alloc] initWithFormat:@"%@\n%@", string, description];
            [string release];
        } else {
            fprintf(stderr, "ERROR: Unable to convert report to data: \"%s\".\n", [[error localizedDescription] UTF8String]);
        }
        [header release];
    }

    return [result autorelease];
}

- (BOOL)symbolicate {
    return [self symbolicateUsingSymbolMaps:nil];
}

- (BOOL)symbolicateUsingSymbolMaps:(NSDictionary *)symbolMaps {
    CRException *exception = [self exception];

    // Prepare array of image start addresses for determining symbols of exception.
    NSArray *imageAddresses = nil;
    NSArray *stackFrames = [exception stackFrames];
    if ([stackFrames count] > 0) {
        imageAddresses = [[[self binaryImages] allKeys] sortedArrayUsingSelector:@selector(compare:)];
    }

    // Symbolicate the exception (if backtrace exists).
    for (CRStackFrame *stackFrame in stackFrames) {
        // Determine start address for this frame.
        if ([stackFrame imageAddress] == 0) {
            for (NSNumber *number in [imageAddresses reverseObjectEnumerator]) {
                uint64_t imageAddress = [number unsignedLongLongValue];
                if ([stackFrame address] > imageAddress) {
                    [stackFrame setImageAddress:imageAddress];
                    break;
                }
            }
        }
        [self symbolicateStackFrame:stackFrame usingSymbolMaps:symbolMaps];
    }

    // Symbolicate the threads.
    for (CRThread *thread in [self threads]) {
        for (CRStackFrame *stackFrame in [thread stackFrames]) {
            [self symbolicateStackFrame:stackFrame usingSymbolMaps:symbolMaps];
        }
    }

    // Update the description in order to include symbol info.
    [self updateDescription];

    // NOTE: Currently, this always 'succeeds'.
    return YES;
}

- (BOOL)writeToFile:(NSString *)filepath forcePropertyList:(BOOL)forcePropertyList {
    BOOL succeeded = NO;

    NSString *report = [self stringRepresentation:([self isPropertyList] || forcePropertyList)];
    if (report != nil) {
        if (filepath != nil) {
            // Write to file.
            NSError *error = nil;
            if ([report writeToFile:filepath atomically:YES encoding:NSUTF8StringEncoding error:&error]) {
                fprintf(stderr, "INFO: Result written to %s.\n", [filepath UTF8String]);
                succeeded = YES;
            } else {
                fprintf(stderr, "ERROR: Unable to write to file: %s.\n", [[error localizedDescription] UTF8String]);
            }
        } else {
            // Print to screen.
            printf("%s\n", [report UTF8String]);
            succeeded = YES;
        }
    }

    return succeeded;
}

#pragma mark - Private Methods

- (void)parse {
    NSString *description = [[self properties] objectForKey:kCrashReportDescription];
    if (description != nil) {
        // Create variables to store parsed information.
        NSMutableArray *processInfo = [NSMutableArray new];
        CRException *exception = [CRException new];
        NSMutableArray *threads = [NSMutableArray new];
        NSMutableArray *registerState = [NSMutableArray new];
        NSMutableDictionary *binaryImages = [NSMutableDictionary new];
        CRThread *thread = nil;
        NSString *threadName = nil;

        // NOTE: The description is handled as five separate sections.
        typedef enum {
            ModeProcessInfo,
            ModeException,
            ModeThread,
            ModeRegisterState,
            ModeBinaryImage,
        } SymbolicationMode;

        SymbolicationMode mode = ModeProcessInfo;

        // Process one line at a time.
        NSArray *inputLines = [[description stringByReplacingOccurrencesOfString:@"\r" withString:@""] componentsSeparatedByString:@"\n"];
        for (NSString *line in inputLines) {
            switch (mode) {
                case ModeProcessInfo:
                    if ([line hasPrefix:@"Exception Type:"]) {
                        NSUInteger lastCloseParenthesis = [line rangeOfString:@")" options:NSBackwardsSearch].location;
                        if (lastCloseParenthesis != NSNotFound) {
                            NSRange range = NSMakeRange(0, lastCloseParenthesis);
                            NSUInteger lastOpenParenthesis = [line rangeOfString:@"(" options:NSBackwardsSearch range:range].location;
                            if (lastOpenParenthesis < lastCloseParenthesis) {
                                range = NSMakeRange(lastOpenParenthesis + 1, lastCloseParenthesis - lastOpenParenthesis - 1);
                                [exception setType:[line substringWithRange:range]];
                            }
                        }
                        [processInfo addObject:line];
                        break;
                    } else if ([line hasPrefix:@"Last Exception Backtrace:"]) {
                        mode = ModeException;
                        break;
                    } else if (![line hasPrefix:@"Thread 0"]) {
                        [processInfo addObject:line];
                        break;
                    } else {
                        // Start of thread 0; fall-through to next case.
                        mode = ModeThread;
                    }

                case ModeThread:
                    if ([line rangeOfString:@"Thread State"].location != NSNotFound) {
                        if (thread != nil) {
                            [threads addObject:thread];
                            [thread release];
                        }
                        [registerState addObject:line];
                        mode = ModeRegisterState;
                    } else if ([line length] > 0) {
                        NSRange range = [line rangeOfString:@" name:"];
                        if (range.location != NSNotFound) {
                            threadName = [line substringFromIndex:(range.location + range.length + 2)];
                        } else if ([line hasSuffix:@":"]) {
                            if (thread != nil) {
                                [threads addObject:thread];
                                [thread release];
                            }
                            thread = [CRThread new];
                            if (threadName != nil) {
                                [thread setName:threadName];
                                threadName = nil;
                            }
                            [thread setCrashed:([line rangeOfString:@"Crashed"].location != NSNotFound)];
                        } else {
                            NSArray *array = [line captureComponentsMatchedByRegex:@"^(\\d+)\\s+.*\\S\\s+(?:0x)?([0-9a-f]+) (?:0x)?([0-9a-f]+) \\+ (?:0x)?\\d+"];
                            if ([array count] == 4) {
                                NSString *matches[] = {[array objectAtIndex:1], [array objectAtIndex:2], [array objectAtIndex:3]};
                                CRStackFrame *stackFrame = [CRStackFrame new];
                                stackFrame.depth = [matches[0] intValue];
                                stackFrame.address = uint64FromHexString(matches[1]);
                                stackFrame.imageAddress = uint64FromHexString(matches[2]);
                                [thread addStackFrame:stackFrame];
                                [stackFrame release];
                            }
                        }
                    }
                    break;

                case ModeException: {
                    mode = ModeProcessInfo;

                    NSUInteger lastCloseParenthesis = [line rangeOfString:@")" options:NSBackwardsSearch].location;
                    if (lastCloseParenthesis != NSNotFound) {
                        NSRange range = NSMakeRange(0, lastCloseParenthesis);
                        NSUInteger firstOpenParenthesis = [line rangeOfString:@"(" options:0 range:range].location;
                        if (firstOpenParenthesis < lastCloseParenthesis) {
                            NSUInteger depth = 0;
                            range = NSMakeRange(firstOpenParenthesis + 1, lastCloseParenthesis - firstOpenParenthesis - 1);
                            NSArray *array = [[line substringWithRange:range] componentsSeparatedByString:@" "];
                            for (NSString *address in array) {
                                CRStackFrame *stackFrame = [CRStackFrame new];
                                stackFrame.depth = depth;
                                stackFrame.address = uint64FromHexString(address);
                                //stackFrame.imageAddress = 0;
                                [exception addStackFrame:stackFrame];
                                [stackFrame release];
                                ++depth;
                            }
                            continue;
                        }
                    }
                    break;
                }

                case ModeRegisterState:
                    if ([line isEqualToString:@"Binary Images:"]) {
                        mode = ModeBinaryImage;
                    } else if ([line length] > 0) {
                        [registerState addObject:line];
                    }
                    break;

                case ModeBinaryImage: {
                    NSArray *array = [line captureComponentsMatchedByRegex:@"^ *0x([0-9a-f]+) - *0x([0-9a-f]+) [ +]?(?:.+?) (arm\\w*)  (<[0-9a-f]{32}> )?(.+)$"];
                    NSUInteger count = [array count];
                    if ((count == 5) || (count == 6)) {
                        uint64_t imageAddress = uint64FromHexString([array objectAtIndex:1]);
                        uint64_t size = imageAddress - uint64FromHexString([array objectAtIndex:2]);
                        SCBinaryInfo *bi = [[SCBinaryInfo alloc] initWithPath:[array objectAtIndex:(count - 1)] address:imageAddress];
                        [bi setArchitecture:[array objectAtIndex:3]];
                        [bi setSize:size];
                        if (count == 6) {
                            [bi setUuid:[array objectAtIndex:(count - 2)]];
                        }
                        [bi setBlamable:YES];
                        [binaryImages setObject:bi forKey:[NSNumber numberWithUnsignedLongLong:imageAddress]];
                        [bi release];
                    }
                    break;
                }
            }
        }

        [self setProcessInfo:processInfo];
        [self setException:exception];
        [self setThreads:threads];
        [self setRegisterState:registerState];
        [self setBinaryImages:binaryImages];
        [processInfo release];
        [exception release];
        [threads release];
        [registerState release];
        [binaryImages release];
    }
}

- (void)symbolicateStackFrame:(CRStackFrame *)stackFrame usingSymbolMaps:(NSDictionary *)symbolMaps {
    // Retrieve symbol info from related binary image.
    NSNumber *imageAddress = [NSNumber numberWithUnsignedLongLong:[stackFrame imageAddress]];
    SCBinaryInfo *bi = [[self binaryImages] objectForKey:imageAddress];
    if (bi != nil) {
        NSDictionary *symbolMap = [symbolMaps objectForKey:[bi path]];
        SCSymbolInfo *symbolInfo = fetchSymbolInfo(bi, [stackFrame address], symbolMap);
        [stackFrame setSymbolInfo:symbolInfo];
    }
}

- (void)updateDescription {
    NSMutableString *description = [NSMutableString new];

    [description appendString:[[self processInfo] componentsJoinedByString:@"\n"]];
    [description appendString:@"\n"];

    NSDictionary *binaryImages = [self binaryImages];
    NSArray *threads = [self threads];
    NSUInteger count = [threads count];
    for (NSUInteger i = 0; i < count; ++i) {
        CRThread *thread = [threads objectAtIndex:i];

        // Add thread title.
        NSString *name = [thread name];
        if (name != nil) {
            NSString *string = [[NSString alloc] initWithFormat:@"Thread %d name:  %@", i, name];
            [description appendString:string];
            [description appendString:@"\n"];
            [string release];
        }
        NSMutableString *string = [[NSMutableString alloc] initWithFormat:@"Thread %d", i];
        if ([thread crashed]) {
            [string appendString:@" Crashed"];
        }
        [string appendString:@":"];
        [description appendString:string];
        [description appendString:@"\n"];
        [string release];

        // Add stack frames of backtrace.
        for (CRStackFrame *stackFrame in [thread stackFrames]) {
            uint64_t address = [stackFrame address];
            uint64_t imageAddress = [stackFrame imageAddress];
            NSString *addressString = [[NSString alloc] initWithFormat:@"0x%08llx 0x%08llx + 0x%llx",
                        address, imageAddress, address - imageAddress];

            NSNumber *key = [NSNumber numberWithUnsignedLongLong:imageAddress];
            SCBinaryInfo *bi = [binaryImages objectForKey:key];
            NSString *binaryName = (bi == nil) ?
                @"???" :
                [[[bi path] lastPathComponent] stringByAppendingString:([bi isExecutable] ? @" (*)" : @"")];

            NSString *comment = nil;
            SCSymbolInfo *symbolInfo = [stackFrame symbolInfo];
            if (symbolInfo != nil) {
                NSString *sourcePath = [symbolInfo sourcePath];
                if (sourcePath != nil) {
                    comment = [[NSString alloc] initWithFormat:@"\t// %@:%u", sourcePath, [symbolInfo sourceLineNumber]];
                } else {
                    NSString *name = [symbolInfo name];
                    if (name != nil) {
                        comment = [[NSString alloc] initWithFormat:@"\t// %@ + 0x%llx", name, [symbolInfo offset]];
                    }
                }
            }

            NSString *string = [[NSString alloc] initWithFormat:@"%-6u%s%-30s\t%-32s%@",
                        [stackFrame depth], [bi isBlamable] ? "+ " : "  ", [binaryName UTF8String],
                        [addressString UTF8String], comment ?: @""];
            [addressString release];
            [comment release];

            [description appendString:string];
            [description appendString:@"\n"];
            [string release];
        }
        [description appendString:@"\n"];
    }

    // Add register state.
    [description appendString:[[self registerState] componentsJoinedByString:@"\n"]];
    [description appendString:@"\n"];
    [description appendString:@"\n"];

    // Add binary images.
    [description appendString:@"Binary Images:\n"];
    NSArray *imageAddresses = [[binaryImages allKeys] sortedArrayUsingSelector:@selector(compare:)];
    for (NSString *key in imageAddresses) {
        SCBinaryInfo *bi = [binaryImages objectForKey:key];
        uint64_t imageAddress = [bi address];
        NSString *path = [bi path];
        NSString *string = [[NSString alloc] initWithFormat:@"0x%08llx - 0x%08llx %@ %@  %@ %@",
            imageAddress, imageAddress + [bi size], [path lastPathComponent], [bi architecture], [bi uuid], path];
        [description appendString:string];
        [description appendString:@"\n"];
        [string release];
    }

    // Update the property dictionary.
    NSMutableDictionary *properties = [[NSMutableDictionary alloc] initWithDictionary:[self properties]];
    [properties setObject:description forKey:kCrashReportDescription];
    [description release];
    [self setProperties:properties];
    [properties release];
}

@end

/* vim: set ft=objcpp ff=unix sw=4 ts=4 tw=80 expandtab: */
