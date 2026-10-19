#import "NativeErrorLog.h"
#import "TrackJournal.h"
#import "Diagnostics.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>
#include <string.h>
static atomic_bool wanted,installed;
static id nativeLog,observer;
static void parseLine(NSString *line) {
    // The Swift logger's NSData includes the trailing C terminator on device.
    while(line.length && [line characterAtIndex:line.length-1]==0)line=[line substringToIndex:line.length-1];
    static NSRegularExpression *error,*key,*success;
    static dispatch_once_t once;
    dispatch_once(&once,^{
        error=[NSRegularExpression regularExpressionWithPattern:@"^Offline track error: ([a-zA-Z0-9_]+) \\(([0-9]+)\\) \\((spotify:track:[a-zA-Z0-9]{22})\\)" options:0 error:NULL];
        key=[NSRegularExpression regularExpressionWithPattern:@"^Track (spotify:track:[a-zA-Z0-9]{22}): Key failed: ([a-zA-Z0-9_]+)" options:0 error:NULL];
        success=[NSRegularExpression regularExpressionWithPattern:@"^Track (spotify:track:[a-zA-Z0-9]{22})(: Got key| downloaded)$" options:0 error:NULL];
    });
    NSTextCheckingResult *match=[error firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
    if(match) {
        SAPJournalNoteNativeError([line substringWithRange:[match rangeAtIndex:3]],
            @([[line substringWithRange:[match rangeAtIndex:2]] longLongValue]),[line substringWithRange:[match rangeAtIndex:1]]);return;
    }
    match=[key firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
    if(match) {SAPJournalNoteNativeError([line substringWithRange:[match rangeAtIndex:1]],nil,[line substringWithRange:[match rangeAtIndex:2]]);return;}
    match=[success firstMatchInString:line options:0 range:NSMakeRange(0,line.length)];
    if(match)SAPJournalNoteNativeSuccess([line substringWithRange:[match rangeAtIndex:1]],
        [[line substringWithRange:[match rangeAtIndex:2]] isEqual:@": Got key"]?@"key_received":@"downloaded");
}
@interface SAPNativeOfflineErrorObserver : NSObject @end
@implementation SAPNativeOfflineErrorObserver
- (void)log:(id)log wroteLine:(const char *)line fromModule:(const char *)module file:(const char *)file line:(NSInteger)number threadId:(NSUInteger)thread at:(id)date logLevel:(int)level isBreadcrumb:(BOOL)crumb {
    if(!SAPDiagnosticsEnabled()||!atomic_load(&wanted)||!line)return;
    // Fast prefix filter before any allocation. No URLs, keys or general log lines are kept.
    if(strncmp(line,"Offline track error: ",21) && strncmp(line,"Track spotify:track:",20))return;
    size_t length=strnlen(line,1025);if(length>1024)return;
    NSString *value=[[NSString alloc]initWithBytes:line length:length encoding:NSUTF8StringEncoding];
    if(value)parseLine(value);
}
- (void)logSwift:(id)log line:(NSData *)data module:(NSString *)module file:(NSString *)file line:(NSInteger)number threadId:(NSUInteger)thread at:(id)date logLevel:(int)level isBreadcrumb:(BOOL)crumb {
    if(!SAPDiagnosticsEnabled()||!atomic_load(&wanted)||![data isKindOfClass:NSData.class]||data.length>1024||data.length<20)return;
    const char *bytes=data.bytes;
    if(memcmp(bytes,"Track spotify:track:",20) && (data.length<21||memcmp(bytes,"Offline track error: ",21)))return;
    NSString *value=[[NSString alloc]initWithData:data encoding:NSUTF8StringEncoding];if(value)parseLine(value);
}
@end
void SAPNativeErrorLogSetActive(BOOL active) {
    active=active && SAPDiagnosticsEnabled();
    atomic_store(&wanted,active);
    dispatch_async(dispatch_get_main_queue(),^{
        if(!atomic_load(&wanted)) {
            if(nativeLog) {
                ((void(*)(id,SEL,id))objc_msgSend)(nativeLog,NSSelectorFromString(@"removeObserver:"),observer);
                ((void(*)(id,SEL))objc_msgSend)(nativeLog,NSSelectorFromString(@"uninstall"));
            }
            nativeLog=nil;observer=nil;atomic_store(&installed,false);return;
        }
        if(nativeLog)return;
        Class cls=NSClassFromString(@"SPTLog");SEL create=NSSelectorFromString(@"createAndInstallLogWithObserver:identificator:");
        if(![cls respondsToSelector:create])return;
        Protocol *protocol=objc_getProtocol("SPTLogObserver");if(protocol)class_addProtocol(SAPNativeOfflineErrorObserver.class,protocol);
        observer=[SAPNativeOfflineErrorObserver new];
        nativeLog=((id(*)(id,SEL,id,id))objc_msgSend)(cls,create,observer,@"SAPNativeOfflineErrors");
        atomic_store(&installed,nativeLog!=nil);
    });
}
NSDictionary *SAPNativeErrorLogReport(void) {return @{@"requested":@(atomic_load(&wanted)),@"installed":@(atomic_load(&installed))};}
#ifdef SAP_TESTING
void SAPNativeErrorLogParseForTesting(NSString *line) {if(line.length<=1024)parseLine(line);}
#endif
