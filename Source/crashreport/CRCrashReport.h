@class NSString, NSDictionary;

#ifdef __cplusplus
extern "C" {
#endif

@class CRException;

@interface CRCrashReport : NSObject
@property(nonatomic, readonly) NSDictionary *properties;
@property(nonatomic, readonly) NSArray *processInfo;
@property(nonatomic, readonly) CRException *exception;
@property(nonatomic, readonly) NSArray *threads;
@property(nonatomic, readonly) NSArray *registerState;
@property(nonatomic, readonly) NSDictionary *binaryImages;
@property(nonatomic, readonly) BOOL isPropertyList;
+ (CRCrashReport *)crashReportWithData:(NSData *)data;
+ (CRCrashReport *)crashReportWithFile:(NSString *)filepath;
- (id)initWithData:(NSData *)data;
- (id)initWithFile:(NSString *)filepath;
- (void)blame;
- (void)blameUsingFilters:(NSDictionary *)filters;
- (NSString *)stringRepresentation;
- (NSString *)stringRepresentation:(BOOL)asPropertyList;
- (void)symbolicate;
- (void)symbolicateUsingSymbolMaps:(NSDictionary *)symbolMaps;
- (BOOL)writeToFile:(NSString *)filepath forcePropertyList:(BOOL)forcePropertyList;
@end

NSString *symbolicate(NSString *content, NSDictionary *symbolMaps, unsigned progressStepping, NSArray **blameInfo);
NSArray *blame(NSString *exceptionType, NSDictionary *binaryImages, NSArray *backtraceLines);

#ifdef __cplusplus
}
#endif

/* vim: set ft=objc ff=unix sw=4 ts=4 tw=80 expandtab: */
