#import "OfflineConfig.h"
#import "OfflineLimits.h"
#import "WireProto.h"
#import <objc/runtime.h>
#import <objc/message.h>
#include <stdatomic.h>

static atomic_uint_fast64_t requests, patched, unchanged, oversized, failedTasks, emptyTasks;
static atomic_uint_fast64_t cachedBodies, cachedChanges, responses304;
static NSArray *installed;
static char bufferKey, bypassKey;
static char taskKindKey;
@interface SAPHTTPTaskKind : NSObject
@property(nonatomic,strong) NSURL *url;
@property(nonatomic) int kind;
@end
@implementation SAPHTTPTaskKind @end
static const NSUInteger maximumBody = 4 * 1024 * 1024;
static NSString *const cacheKey = @"eeveeCachedCustomizeData";

static NSDictionary *flags(void) {
    return @{@"offline": @1, @"can-use-offline": @1,
             @"max-offline-downloads-per-device": @(SAPMinimumTrackLimit), @"max-offline-tracks": @(SAPMinimumTrackLimit)};
}
static NSData *rewriteAttributes(NSData *data) {
    NSArray *fields = SAPProtoFields(data); if (!fields) return nil;
    NSMutableData *result = [NSMutableData data];
    NSMutableSet *seen = [NSMutableSet set];
    NSDictionary *forced = flags();
    for (NSDictionary *field in fields) {
        if ([field[@"number"] unsignedIntValue] != 1 || [field[@"wire"] unsignedIntValue] != 2) {
            [result appendData:field[@"raw"]]; continue;
        }
        NSArray *entry = SAPProtoFields(field[@"value"]); if (!entry) return nil;
        NSString *key = SAPProtoString(entry, 1);
        NSNumber *value = key ? forced[key] : nil;
        if (!value) { [result appendData:field[@"raw"]]; continue; }
        [seen addObject:key];
        NSData *old = SAPProtoData(entry, 2);
        NSArray *attribute = old ? SAPProtoFields(old) : @[]; if (!attribute) return nil;
        unsigned type = value.unsignedIntValue == 1 ? 2 : 3;
        for (NSDictionary *part in attribute) {
            unsigned number = [part[@"number"] unsignedIntValue];
            if (number >= 2 && number <= 4) type = number;
        }
        NSMutableData *replacement = [NSMutableData data];
        for (NSDictionary *part in attribute) {
            unsigned number = [part[@"number"] unsignedIntValue];
            if (number < 2 || number > 4) [replacement appendData:part[@"raw"]];
        }
        [replacement appendData:type == 4 ? SAPProtoBytes(4, [value.stringValue dataUsingEncoding:NSUTF8StringEncoding]) : SAPProtoInteger(type, value.unsignedLongLongValue)];
        NSMutableData *newEntry = [NSMutableData data];
        for (NSDictionary *part in entry) if ([part[@"number"] unsignedIntValue] != 2) [newEntry appendData:part[@"raw"]];
        [newEntry appendData:SAPProtoBytes(2, replacement)];
        [result appendData:SAPProtoBytes(1, newEntry)];
    }
    for (NSString *key in [[forced allKeys] sortedArrayUsingSelector:@selector(compare:)]) {
        if ([seen containsObject:key]) continue;
        NSNumber *value = forced[key];
        NSMutableData *entry = [SAPProtoBytes(1, [key dataUsingEncoding:NSUTF8StringEncoding]) mutableCopy];
        [entry appendData:SAPProtoBytes(2, SAPProtoInteger(value.unsignedIntValue == 1 ? 2 : 3, value.unsignedLongLongValue))];
        [result appendData:SAPProtoBytes(1, entry)];
    }
    return result;
}
static NSData *rewritePath(NSData *data, const unsigned *path, unsigned count, BOOL *found) {
    if (!count) { *found = YES; return rewriteAttributes(data); }
    NSArray *fields = SAPProtoFields(data); if (!fields) return nil;
    NSMutableData *result = [NSMutableData data];
    for (NSDictionary *field in fields) {
        if ([field[@"number"] unsignedIntValue] == path[0] && [field[@"wire"] unsignedIntValue] == 2) {
            NSData *nested = rewritePath(field[@"value"], path + 1, count - 1, found);
            if (!nested) return nil;
            [result appendData:SAPProtoBytes(path[0], nested)];
        } else [result appendData:field[@"raw"]];
    }
    return result;
}
NSData *SAPRewriteOfflineConfig(NSData *data, BOOL bootstrap) {
    // Account.pb.swift: Bootstrap[2][1][1].Customize[1].Ucs[3].Attributes(map[1]).
    const unsigned bootstrapPath[] = {2, 1, 1, 1, 3}, customizePath[] = {1, 3};
    BOOL found = NO;
    NSData *result = rewritePath(data, bootstrap ? bootstrapPath : customizePath, bootstrap ? 5 : 2, &found);
    return found && result ? result : data;
}
BOOL SAPPrepareCachedOfflineConfig(NSUserDefaults *defaults) {
    // This is the exact cache key used by Eevee's 304 replay. No preference-wide
    // getter hook, cache deletion, account field change or periodic refresh.
    NSData *data = [defaults dataForKey:cacheKey];
    if (!data || data.length > maximumBody) return NO;
    atomic_fetch_add(&cachedBodies, 1);
    NSData *rewritten = SAPRewriteOfflineConfig(data, NO);
    if ([rewritten isEqual:data]) return NO;
    if (![defaults dataForKey:@"SAPOriginalCustomizeBeforeOfflineFlags"])
        [defaults setObject:data forKey:@"SAPOriginalCustomizeBeforeOfflineFlags"];
    [defaults setObject:rewritten forKey:cacheKey];
    atomic_fetch_add(&cachedChanges, 1);
    return YES;
}
static int taskKind(NSURLSessionTask *task) {
    NSURL *url = task.currentRequest.URL ?: task.originalRequest.URL;
    SAPHTTPTaskKind *cached=objc_getAssociatedObject(task,&taskKindKey);
    if(cached && [cached.url isEqual:url])return cached.kind;
    NSString *host = url.host.lowercaseString;
    int kind=0;
    if([host isEqual:@"spotify.com"] || [host hasSuffix:@".spotify.com"]) {
        if([url.path containsString:@"/v1/bootstrap"])kind=1;
        else if([url.path containsString:@"/v1/customize"])kind=2;
    }
    SAPHTTPTaskKind *value=[SAPHTTPTaskKind new];value.url=url;value.kind=kind;
    objc_setAssociatedObject(task,&taskKindKey,value,OBJC_ASSOCIATION_RETAIN);
    return kind;
}
static BOOL signature(Class cls, SEL sel, unsigned arguments, Method *method) {
    *method = class_getInstanceMethod(cls, sel); if (!*method || method_getNumberOfArguments(*method) != arguments) return NO;
    char type[16]; method_getReturnType(*method, type, sizeof(type)); return type[0] == 'v';
}
void SAPInstallOfflineConfig(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        SAPPrepareCachedOfflineConfig(NSUserDefaults.standardUserDefaults);
        NSMutableArray *names = [NSMutableArray array];
        for (NSString *name in @[@"SPTDataLoaderService", @"Connectivity_HttpClientKit.HttpClientURLSession", @"SPTCoreURLSessionDataDelegate"]) {
            Class cls = NSClassFromString(name); Method dataMethod, completeMethod;
            SEL dataSel = NSSelectorFromString(@"URLSession:dataTask:didReceiveData:"), completeSel = NSSelectorFromString(@"URLSession:task:didCompleteWithError:");
            if (!signature(cls, dataSel, 5, &dataMethod) || !signature(cls, completeSel, 5, &completeMethod)) continue;
            IMP originalData = method_getImplementation(dataMethod), originalComplete = method_getImplementation(completeMethod);
            // Per-task storage has no timer and is released on completion or task destruction.
            IMP dataHook = imp_implementationWithBlock(^(id self, id session, NSURLSessionTask *task, NSData *data) {
                if (!taskKind(task) || ![data isKindOfClass:NSData.class]) {
                    ((void (*)(id, SEL, id, id, id))originalData)(self, dataSel, session, task, data); return;
                }
                @synchronized(task) {
                    if (objc_getAssociatedObject(task, &bypassKey)) {
                        ((void (*)(id, SEL, id, id, id))originalData)(self, dataSel, session, task, data); return;
                    }
                    NSMutableData *body = objc_getAssociatedObject(task, &bufferKey);
                    if (!body) { body = [NSMutableData data]; objc_setAssociatedObject(task, &bufferKey, body, OBJC_ASSOCIATION_RETAIN_NONATOMIC); atomic_fetch_add(&requests, 1); }
                    if (data.length > maximumBody - body.length) {
                        atomic_fetch_add(&oversized, 1);
                        objc_setAssociatedObject(task, &bypassKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        objc_setAssociatedObject(task, &bufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        if (body.length) ((void (*)(id, SEL, id, id, id))originalData)(self, dataSel, session, task, body);
                        ((void (*)(id, SEL, id, id, id))originalData)(self, dataSel, session, task, data);
                    } else [body appendData:data];
                }
            });
            IMP completeHook = imp_implementationWithBlock(^(id self, id session, NSURLSessionTask *task, NSError *error) {
                int kind = taskKind(task);
                if (kind) @synchronized(task) {
                    NSData *body = objc_getAssociatedObject(task, &bufferKey);
                    if (body) {
                        NSData *replacement = body;
                        if (!error && [task.response isKindOfClass:NSHTTPURLResponse.class] && [(NSHTTPURLResponse *)task.response statusCode] == 200) {
                            replacement = SAPRewriteOfflineConfig(body, kind == 1);
                            atomic_fetch_add([replacement isEqual:body] ? &unchanged : &patched, 1);
                        } else atomic_fetch_add(&failedTasks, 1);
                        objc_setAssociatedObject(task, &bufferKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                        ((void (*)(id, SEL, id, id, id))originalData)(self, dataSel, session, task, replacement);
                    } else if (!objc_getAssociatedObject(task, &bypassKey)) atomic_fetch_add(&emptyTasks, 1);
                    objc_setAssociatedObject(task, &bypassKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
                }
                ((void (*)(id, SEL, id, id, id))originalComplete)(self, completeSel, session, task, error);
            });
            class_replaceMethod(cls, dataSel, dataHook, method_getTypeEncoding(dataMethod));
            class_replaceMethod(cls, completeSel, completeHook, method_getTypeEncoding(completeMethod));
            SEL responseSel = NSSelectorFromString(@"URLSession:dataTask:didReceiveResponse:completionHandler:");
            Method responseMethod;
            if (signature(cls, responseSel, 6, &responseMethod)) {
                IMP originalResponse = method_getImplementation(responseMethod);
                IMP responseHook = imp_implementationWithBlock(^(id self, id session, NSURLSessionTask *task, NSURLResponse *response, id handler) {
                    if (taskKind(task) == 2 && [response isKindOfClass:NSHTTPURLResponse.class]
                        && [(NSHTTPURLResponse *)response statusCode] == 304) {
                        atomic_fetch_add(&responses304, 1); SAPPrepareCachedOfflineConfig(NSUserDefaults.standardUserDefaults);
                    }
                    ((void (*)(id, SEL, id, id, id, id))originalResponse)(self, responseSel, session, task, response, handler);
                });
                class_replaceMethod(cls, responseSel, responseHook, method_getTypeEncoding(responseMethod));
            }
            [names addObject:name];
        }
        installed = [names copy];
    });
}
NSDictionary *SAPOfflineConfigReport(void) {
    return @{@"delegates": installed ?: @[], @"requests": @(atomic_load(&requests)), @"patched": @(atomic_load(&patched)),
        @"unchanged_or_unrecognized": @(atomic_load(&unchanged)), @"oversized_passthrough": @(atomic_load(&oversized)),
        @"error_passthrough": @(atomic_load(&failedTasks)), @"no_body": @(atomic_load(&emptyTasks)),
        @"cached_bodies_seen": @(atomic_load(&cachedBodies)), @"cached_bodies_changed": @(atomic_load(&cachedChanges)),
        @"responses_304": @(atomic_load(&responses304))};
}
