#import <Foundation/Foundation.h>
#import "OfflineDevices.h"
#import "WireProto.h"
#include <assert.h>

// An in-memory Spotify registry. NSURLProtocol intercepts every HTTP request;
// these tests never authenticate to Spotify or change a real registration.
static NSMutableArray<NSMutableDictionary *> *devices;
static NSMutableArray *events,*requests;
static NSInteger maximum=5,freeSlots,failHTTP;
static BOOL nativeMismatch,ignoreDisable,malformedDevices,allowEnable=YES,enabledPlayback;
static NSUInteger commands,postCount;
static NSInteger failAfterPost=-1;
static NSDictionary *nativeState(void) {
    NSMutableArray *copy=[NSMutableArray array];
    for(NSDictionary *d in devices)[copy addObject:[d copy]];
    return @{@"status":@"complete",@"sources":@{
        @"licenses":@{@"max_licenses":@(maximum),@"free_licenses":@(freeSlots+(nativeMismatch?1:0))},
        @"devices":@{@"read_status":@"received",@"devices":copy},
        @"local_device":@{@"read_status":@"received",@"device":[devices.lastObject copy]},
        @"playback":@{@"read_status":@"received",@"allowed":@(enabledPlayback)}}};
}
void SAPRefreshDownloadCompatibility(void (^reply)(NSDictionary *)) {reply(nativeState());}
void SAPJournalNoteAction(NSString *name,NSDictionary *facts) {[events addObject:@{@"name":name,@"facts":facts}];}
void SAPCallOfflineCommandOnce(NSString *method,NSData *payload,void (^reply)(NSData *,NSString *)) {
    assert([method isEqual:@"SetOfflinePlaybackAllowed"]);
    assert([payload isEqual:SAPProtoInteger(1,1)]);commands++;
    if(allowEnable){devices.lastObject[@"offline_enabled"]=@YES;enabledPlayback=YES;freeSlots--;}
    reply(SAPProtoInteger(1,1),nil);
}
static NSData *join(NSData *a,NSData *b) {NSMutableData *out=[a mutableCopy];[out appendData:b];return out;}
static NSData *string(unsigned field,NSString *value) {return SAPProtoBytes(field,[value dataUsingEncoding:NSUTF8StringEncoding]);}
static NSData *deviceResponse(void) {
    if(malformedDevices)return [NSData dataWithBytes:(uint8_t[]){0xff} length:1];
    NSMutableData *out=[NSMutableData data];
    for(NSDictionary *d in devices){
        NSData *body=join(string(1,d[@"device_id"]),string(2,d[@"cache_id"]));
        body=join(body,string(3,d[@"name"]));
        // Direct HTTPS schema differs from Esperanto: offline_enabled=6,
        // last_seen_at=10 (a nested Timestamp, not a bool).
        body=join(body,SAPProtoInteger(6,[d[@"offline_enabled"]boolValue]));
        body=join(body,SAPProtoBytes(10,SAPProtoInteger(1,1792520000)));
        [out appendData:SAPProtoBytes(1,body)];
    }
    return out;
}
@interface RegistryProtocol : NSURLProtocol @end
@implementation RegistryProtocol
+ (BOOL)canInitWithRequest:(NSURLRequest *)request {return YES;}
+ (NSURLRequest *)canonicalRequestForRequest:(NSURLRequest *)request {return request;}
- (void)startLoading {
    NSURLRequest *r=self.request;NSString *path=r.URL.path;
    assert([r.URL.host isEqual:@"spclient.wg.spotify.com"]);
    assert([[r valueForHTTPHeaderField:@"Authorization"]isEqual:@"Bearer TEST_ONLY_NOT_REAL"]);
    assert(![r valueForHTTPHeaderField:@"X-Private-Noise"]);
    [requests addObject:@{@"path":path,@"method":r.HTTPMethod}];
    NSInteger status=failHTTP?:200;NSData *data=NSData.data;
    if([r.HTTPMethod isEqual:@"POST"]){
        postCount++;assert([path hasSuffix:@"/disable"]);
        assert(r.HTTPBody.length==0);
        assert([r valueForHTTPHeaderField:@"Content-Type"]);
        NSArray *parts=path.pathComponents;
        assert(parts.count==8);
        if(!ignoreDisable && !failHTTP){
            BOOL found=NO;
            for(NSMutableDictionary *d in devices)if([d[@"device_id"]isEqual:parts[4]] && [d[@"cache_id"]isEqual:parts[6]]){
                assert([d[@"offline_enabled"]boolValue]);d[@"offline_enabled"]=@NO;freeSlots++;found=YES;
            }
            assert(found);
        }
        if(failAfterPost==(NSInteger)postCount)failHTTP=503;
        data=SAPProtoInteger(1,1);
    }else {
        assert([r.HTTPMethod isEqual:@"GET"]);
        if([path isEqual:@"/offline/v1/licenseStatus"])data=join(SAPProtoInteger(1,maximum),SAPProtoInteger(2,freeSlots));
        else {assert([path isEqual:@"/offline/v1/devices"]);data=deviceResponse();}
    }
    NSHTTPURLResponse *response=[[NSHTTPURLResponse alloc]initWithURL:r.URL statusCode:status HTTPVersion:@"HTTP/1.1" headerFields:@{@"Content-Type":@"application/x-protobuf"}];
    [self.client URLProtocol:self didReceiveResponse:response cacheStoragePolicy:NSURLCacheStorageNotAllowed];
    [self.client URLProtocol:self didLoadData:data];[self.client URLProtocolDidFinishLoading:self];
}
- (void)stopLoading {}
@end
static void reset(NSUInteger active) {
    devices=[NSMutableArray array];events=[NSMutableArray array];requests=[NSMutableArray array];
    maximum=5;freeSlots=5-active;commands=postCount=0;failHTTP=0;failAfterPost=-1;
    nativeMismatch=ignoreDisable=malformedDevices=enabledPlayback=NO;allowEnable=YES;
    for(NSUInteger i=0;i<active;i++)[devices addObject:[@{@"device_id":[NSString stringWithFormat:@"old-device-%lu",i],@"cache_id":[NSString stringWithFormat:@"old-cache-%lu",i],@"name":@"iPhone",@"offline_enabled":@YES}mutableCopy]];
    [devices addObject:[@{@"device_id":@"current-device",@"cache_id":@"current-cache",@"name":@"Current iPhone",@"offline_enabled":@NO}mutableCopy]];
    SAPOfflineDevicesTestEnvironment(RegistryProtocol.class,^(void (^reply)(NSDictionary *)){
        reply(@{@"Authorization":@"Bearer TEST_ONLY_NOT_REAL",@"X-Private-Noise":@"do not forward"});
    });
}
static void waitFor(BOOL (^condition)(void)) {
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(!condition() && deadline.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
    assert(condition());
}
static NSDictionary *preview(BOOL success) {
    __block BOOL done=NO;__block NSDictionary *plan;__block NSString *error;
    SAPPreviewOfflineDeviceSlots(^(NSDictionary *p,NSString *e){plan=p;error=e;done=YES;});waitFor(^BOOL{return done;});
    assert(success?(plan!=nil && error==nil):(error!=nil));assert(postCount==0);return plan;
}
static NSDictionary *release(NSDictionary *plan,NSArray *ids,BOOL success) {
    __block BOOL done=NO;__block NSDictionary *result;__block NSString *error;
    SAPReleaseOfflineDeviceSlots(plan[@"id"],ids,^(NSDictionary *r,NSString *e){result=r;error=e;done=YES;});waitFor(^BOOL{return done;});
    if(success)assert(result!=nil && error==nil);else assert(error!=nil);
    return result;
}
static void enable(BOOL success) {
    __block BOOL done=NO;__block NSString *error;
    SAPEnableOfflineOnCurrentDevice(^(NSDictionary *r,NSString *e){error=e;done=YES;});waitFor(^BOOL{return done;});
    assert(success?error==nil:error!=nil);
}
int main(void) {@autoreleasepool {
    reset(5);NSDictionary *plan=preview(YES);assert([plan[@"active_devices"]count]==5);
    assert([plan[@"active_devices"][0][@"last_seen_at"]longLongValue]==1792520000);
    assert(requests.count==2);
    NSDictionary *result=release(plan,@[@"old-cache-0"],YES);
    assert(postCount==1 && freeSlots==1 && [result[@"free_licenses"]integerValue]==1);
    release(plan,@[@"old-cache-0"],NO);assert(postCount==1); // Consumed once.
    enable(YES);assert(commands==1 && freeSlots==0);enable(YES);assert(commands==1);
    puts("PASS: preview is read-only; release requires fresh state and verified readback; enabling consumes one slot, with no duplicate command");

    reset(5);plan=preview(YES);
    NSMutableArray *ids=[NSMutableArray array];for(NSDictionary *d in plan[@"active_devices"])[ids addObject:d[@"cache_id"]];
    result=release(plan,ids,YES);assert(postCount==5 && freeSlots==5 && [result[@"released_cache_ids"]count]==5);
    NSData *audit=[NSJSONSerialization dataWithJSONObject:events options:0 error:nil];
    NSString *text=[[NSString alloc]initWithData:audit encoding:NSUTF8StringEncoding];
    assert(![text containsString:@"TEST_ONLY_NOT_REAL"] && ![text containsString:@"Authorization"]);
    puts("PASS: five real registry changes produce five verified free slots; credentials are absent from audit facts");

    reset(5);plan=preview(YES);ignoreDisable=YES;
    result=release(plan,@[@"old-cache-0"],NO);assert(postCount==1 && freeSlots==0 && [result[@"status"]isEqual:@"unconfirmed"]);
    reset(5);plan=preview(YES);failAfterPost=1;
    release(plan,@[@"old-cache-0",@"old-cache-1"],NO);assert(postCount==1 && freeSlots==1);
    puts("PASS: HTTP acknowledgement without state change and failure after POST never become success or trigger another POST");

    reset(5);plan=preview(YES);devices[0][@"offline_enabled"]=@NO;freeSlots++;
    release(plan,@[@"old-cache-1"],NO);assert(postCount==0);
    reset(5);plan=preview(YES);release(plan,@[@"unreviewed"],NO);assert(postCount==0);
    reset(5);plan=preview(YES);release(plan,@[@"old-cache-0",@"old-cache-0"],NO);assert(postCount==0);
    reset(5);nativeMismatch=YES;preview(NO);assert(postCount==0);
    reset(5);failHTTP=403;preview(NO);assert(postCount==0);
    reset(5);malformedDevices=YES;preview(NO);assert(postCount==0);
    reset(5);SAPOfflineDevicesTestEnvironment(RegistryProtocol.class,^(void (^reply)(NSDictionary *)){reply(@{});});preview(NO);assert(requests.count==0);
    puts("PASS: stale selection, unknown/duplicate IDs, native/direct mismatch, denied authentication and malformed replies block mutation");

    reset(5);enable(NO);assert(commands==0);
    reset(4);allowEnable=NO;enable(NO);assert(commands==1 && !enabledPlayback);
    puts("PASS: zero slots block enable; an acknowledged enable still needs confirmed registration and offline playback status");
}return 0;}
