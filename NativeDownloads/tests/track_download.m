#include "Diagnostics.h"
#import <Foundation/Foundation.h>
#import "TrackDownload.h"
#import "WireProto.h"
#import "NativeOffline.h"
#import "TrackJournal.h"
#include <assert.h>
static BOOL prepareReady=YES,prepareDeferred;
static void (^pendingPreparation)(BOOL,NSString *);
static BOOL (^pendingRequested)(void);
void SAPPrepareNativeOffline(BOOL (^requested)(void),void (^completion)(BOOL,NSString *)) {
    dispatch_async(dispatch_get_main_queue(),^{
        if(prepareDeferred) {pendingPreparation=completion;pendingRequested=requested;}
        else completion(prepareReady,@"test native preparation");
    });
}
void SAPReadNativeTrackState(NSString *uri) {}
void SAPRequestNativeAlbumDownload(NSString *uri, void (^completion)(BOOL, NSString *)) {
    if (completion) completion(YES, @"test album request");
}
NSUInteger SAPObservedAudioKeyCount(void) { return 0; }
void SAPJournalVerifyTrack(NSString *uri,void (^completion)(NSDictionary *)) {if(completion)completion(nil);}
NSDictionary *SAPNativeOfflineReport(void) { return @{@"test_stub":@YES}; }
// Журнал здесь подменён: проверяем, что транспортный хук отдаёт ему каждый вызов
// сервиса Offline, а TrackDownload отдаёт рабочий канал к ядру.
static NSMutableArray *journalObserved;
static SAPJournalCaller journalCaller;
static unsigned journalRefreshes;
void SAPJournalNoteAction(NSString *name,NSDictionary *facts) {}
void SAPJournalObserveCall(NSString *method, NSData *request, NSData *response, NSString *source) {
    if (!journalObserved) journalObserved = [NSMutableArray array];
    [journalObserved addObject:@{@"method": method ?: @"", @"request": @(request.length),
        @"response": @(response.length), @"source": source ?: @""}];
}
void SAPJournalSetCaller(SAPJournalCaller caller) { journalCaller = [caller copy]; }
BOOL SAPJournalOnOwnQueue(void) { return NO; }
static NSDictionary *nativeFailureForTesting;
NSDictionary *SAPJournalNativeErrorForURI(NSString *uri) {return [nativeFailureForTesting[@"uri"] isEqual:uri]?nativeFailureForTesting:nil;}
void SAPJournalRefresh(NSString *reason) { journalRefreshes++; }
void SAPJournalNoteCallIssue(NSString *method,NSString *uri,NSString *channel,NSString *issue) {}
NSString *SAPJournalSummaryText(void) { return @"test journal"; }
NSString *SAPJournalSummaryForReport(NSDictionary *report) {return @"test journal";}
static unsigned journalSaw(NSString *method) {
    unsigned count = 0;
    for (NSDictionary *entry in journalObserved) if ([entry[@"method"] isEqual:method]) count++;
    return count;
}

@interface FakeTrack : NSObject
@property(nonatomic, strong) NSURL *URI;
@property(nonatomic, copy) NSString *trackTitle;
@end
@implementation FakeTrack @end
@interface FakeState : NSObject
@property(nonatomic, strong) FakeTrack *track;
@end
@implementation FakeState @end
@interface SPTEsperantoPlayer : NSObject
@property(nonatomic, strong) FakeState *state;
- (void)addPlayerObserver:(id)observer;
- (void)fetchState:(id)callback on:(id)queue;
- (void)globalPlayerSubscription:(id)subscription gotStateUpdate:(id)state;
@end
@implementation SPTEsperantoPlayer
- (void)addPlayerObserver:(id)observer { assert([observer isEqual:@"test"]); }
- (void)fetchState:(id)callback on:(id)queue {}
- (void)globalPlayerSubscription:(id)subscription gotStateUpdate:(id)state {}
@end
@interface FakeLifetime : NSObject
@property(nonatomic) BOOL cancelled, acquired;
- (void)cancel;
- (void)acquire;
@end
@implementation FakeLifetime
- (void)cancel { assert(self.acquired); self.cancelled = YES; }
- (void)acquire { self.acquired = YES; }
@end
@interface SPTEsperantoTransportBridgeImpl : NSObject
@property(nonatomic) unsigned scenario, queries, requests, removes;
@property(nonatomic) unsigned commandBehavior, commandCount;
@property(nonatomic,copy) void (^commandLateCallback)(NSData *);
@property(nonatomic, copy) NSString *requested;
@property(nonatomic, copy) void (^lateCallback)(NSData *);
@property(nonatomic, copy) BOOL (^errorCallback)(NSData *);
@property(nonatomic, strong) FakeLifetime *streamLifetime;
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback;
- (id)callStream:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(BOOL (^)(NSData *))callback;
@end
static NSString *const trackURI = @"spotify:track:1234567890123456789012";
static NSData *join(NSData *a, NSData *b) { NSMutableData *d = [a mutableCopy]; [d appendData:b]; return d; }
@implementation SPTEsperantoTransportBridgeImpl
- (id)callStream:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(BOOL (^)(NSData *))callback {
    assert([service isEqual:@"spotify.offline_esperanto.proto.Offline"] && [method isEqual:@"SubscribeError"] && payload.length == 0);
    self.errorCallback = callback; self.streamLifetime = [FakeLifetime new]; return self.streamLifetime;
}
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback {
    if ([method isEqual:@"warmup"]) return nil;
    if (self.scenario == 12) return nil; // Wrong/stale native channel: never answers.
    assert([service isEqual:@"spotify.offline_esperanto.proto.Offline"]);
    if([method isEqual:@"SetOfflinePlaybackAllowed"]) {
        self.commandCount++;assert([payload isEqual:SAPProtoInteger(1,1)]);
        if(self.commandBehavior==1)self.commandLateCallback=callback;
        else if(self.commandBehavior==2)callback(nil);
        else callback(SAPProtoInteger(1,1));
        return [FakeLifetime new];
    }
    if ([method isEqual:@"GetOfflinePlaybackStatus"]) {
        callback([NSData dataWithBytes:(uint8_t[]){0x08,0x01} length:2]);
    } else if ([method isEqual:@"AddDownload"] || [method isEqual:@"RemoveDownload"]) {
        // DownloadRequest.uri is field 2; device omitted means local device.
        // Header 0x12 0x24 and these exact 36 UTF-8 bytes are independent of decoder.
        assert(payload.length == 38 && ((uint8_t *)payload.bytes)[0] == 0x12 && ((uint8_t *)payload.bytes)[1] == 0x24);
        assert(memcmp((uint8_t *)payload.bytes + 2, trackURI.UTF8String, 36) == 0);
        if ([method isEqual:@"RemoveDownload"]) { self.removes++; callback(NSData.data); }
        else {
            self.requests++; self.requested = trackURI;
            if (self.scenario == 1) callback([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]); // NOT_ALLOWED=23
            else if (self.scenario == 6) self.lateCallback = callback;
            else if (self.scenario == 10) callback([NSData dataWithBytes:(uint8_t[]){0xff} length:1]);
            else if (self.scenario == 11) callback(nil);
            else callback(NSData.data); // Valid protobuf default error=0.
        }
    } else if ([method isEqual:@"GetItems"]) {
        assert(payload.length == 38 && ((uint8_t *)payload.bytes)[0] == 0x0a && ((uint8_t *)payload.bytes)[1] == 0x24);
        assert(memcmp((uint8_t *)payload.bytes + 2, trackURI.UTF8String, 36) == 0);
        unsigned status = self.scenario == 3 ? 3 : self.scenario >= 14 ? 1 : 0;
        if (self.requested) {
            self.queries++;
            if(self.scenario==14 || self.scenario==16) {
                status=self.queries<=4?1:self.queries==5?5:3;
                if(self.scenario==16 && self.queries==1)
                    nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970)};
            }
            else if(self.scenario==15 || self.scenario==17) {
                status=1;
                if(self.scenario==17 && self.queries==1)
                    nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970)};
            }
            else if (self.scenario == 2 || self.scenario == 8) status = 0;
            else if (self.scenario == 4) status = 6;
            else if (self.scenario == 5) { unsigned values[] = {3,5,3,3}; status = values[MIN(self.queries - 1, 3)]; }
            else if (self.scenario == 9) { self.errorCallback([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]); status = 1; }
            else status = self.queries == 1 ? 6 : self.queries < 4 ? 5 : 3;
        }
        NSString *uri = self.scenario == 8 ? @"spotify:track:2222222222222222222222" : trackURI;
        NSData *item = join(SAPProtoBytes(1, [uri dataUsingEncoding:NSUTF8StringEncoding]), SAPProtoInteger(2, status));
        item = join(item, SAPProtoInteger(4, status == 3 ? 100 : 20));
        callback(SAPProtoBytes(1, item));
    } else assert(!"unexpected RPC");
    return [FakeLifetime new];
}
@end
@interface SPTEsperantoCosmosTransport : SPTEsperantoTransportBridgeImpl @end
@implementation SPTEsperantoCosmosTransport
- (id)callSingle:(NSString *)service method:(NSString *)method payload:(NSData *)payload onResponse:(void (^)(NSData *))callback {
    // Initial GetItems answers; subsequent reads silently disappear after AddDownload.
    if(self.scenario==13 && self.requests>0 && [method isEqual:@"GetItems"])return [FakeLifetime new];
    return [super callSingle:service method:method payload:payload onResponse:callback];
}
@end
static void waitFor(BOOL (^condition)(void)) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
    while (!condition() && deadline.timeIntervalSinceNow > 0)
        [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.003]];
    if (!condition()) NSLog(@"Timeout: %@", SAPTrackDownloadReport());
    assert(condition());
}
static void reset(SPTEsperantoTransportBridgeImpl *t, unsigned scenario) {
    t.scenario = scenario; t.queries = 0; t.requested = nil; t.errorCallback = nil;
}
int main(void) { @autoreleasepool {
    SAPDiagnosticsSetEnabled(true);

    SAPInstallTrackDownloader(); SAPInstallTrackDownloader();
    assert([SAPTrackDownloadReport()[@"installed_hooks"] count] == 7);
    SPTEsperantoPlayer *player = [SPTEsperantoPlayer new];
    FakeTrack *track = [FakeTrack new]; track.URI = [NSURL URLWithString:trackURI]; track.trackTitle = @"Original track";
    FakeState *state = [FakeState new]; state.track = track; player.state = state;
    [player addPlayerObserver:@"test"];
    __block NSString *last;
    void (^callback)(NSString *) = ^(NSString *message) { last = message; };
    SAPDownloadCurrentTrack(callback); assert(last.length && !SAPTrackDownloadActive());
    SPTEsperantoTransportBridgeImpl *bad = [SPTEsperantoTransportBridgeImpl new]; bad.scenario = 12;
    [bad callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil];
    SPTEsperantoTransportBridgeImpl *t = [SPTEsperantoTransportBridgeImpl new];
    [t callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil];
    SAPDownloadCurrentTrack(callback);
    waitFor(^BOOL{ return t.requests == 1; });
    assert(![SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    FakeTrack *next = [FakeTrack new]; next.URI = [NSURL URLWithString:@"spotify:track:2222222222222222222222"]; next.trackTitle = @"Next";
    state.track = next;
    waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"] && t.queries == 5);
    assert([SAPTrackDownloadReport()[@"transport_candidate"] unsignedIntValue] == 2 && bad.requests == 0);
    assert([SAPTrackDownloadReport()[@"track_uri"] isEqual:trackURI] && t.streamLifetime.cancelled);
    unsigned queries = t.queries;
    NSDate *until = [NSDate dateWithTimeIntervalSinceNow:0.04];
    while (until.timeIntervalSinceNow > 0) [NSRunLoop.currentRunLoop runMode:NSDefaultRunLoopMode beforeDate:until];
    assert(t.queries == queries); // No polling after completion.
    state.track = track;
    [bad callSingle:@"" method:@"warmup" payload:NSData.data onResponse:nil]; // Unrelated calls must not replace proven channel.
    for (unsigned scenario = 1; scenario <= 11; scenario++) {
        if (scenario == 7) continue;
        reset(t, scenario); unsigned requests = t.requests;
        SAPDownloadCurrentTrack(callback);
        if (scenario == 4) {
            waitFor(^BOOL{ return t.requests > requests && t.queries > 0; });
            SAPCancelTrackDownload(); waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
            assert(t.removes == 1 && [SAPTrackDownloadReport()[@"phase"] isEqual:@"cancelled"]); continue;
        }
        waitFor(^BOOL{ return [SAPTrackDownloadReport()[@"active"] boolValue] || t.requests > requests || scenario == 3; });
        if (scenario == 3) waitFor(^BOOL{ return [SAPTrackDownloadReport()[@"monitoring_existing"] boolValue]; });
        waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
        NSDictionary *report = SAPTrackDownloadReport();
        if (scenario == 1) assert([report[@"phase"] isEqual:@"rejected"] && [report[@"response_error"] intValue] == 23);
        if (scenario == 2 || scenario == 8) assert([report[@"phase"] isEqual:@"unconfirmed"] && ![report[@"detail"] containsString:@"не принял"]);
        if (scenario == 3) assert([report[@"phase"] isEqual:@"completed"] && t.requests == requests);
        if (scenario == 5) assert([report[@"phase"] isEqual:@"completed"] && t.queries == 4);
        if (scenario == 6) assert([report[@"phase"] isEqual:@"unconfirmed"] && report[@"response_error"] == NSNull.null);
        if (scenario == 9) assert([report[@"phase"] isEqual:@"failed"] && [report[@"offline_stream_error"] intValue] == 23);
        if (scenario == 10 || scenario == 11) assert([report[@"phase"] isEqual:@"invalid_response"]);
    }
    // A delayed completion from an older request must not corrupt a new job.
    void (^old)(NSData *) = t.lateCallback;
    reset(t, 0); unsigned requests = t.requests;
    SAPDownloadCurrentTrack(callback); waitFor(^BOOL{ return t.requests > requests; });
    old([NSData dataWithBytes:(uint8_t[]){0x08,0x17} length:2]);
    waitFor(^BOOL{ return !SAPTrackDownloadActive(); });
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    assert([SAPTrackDownloadReport()[@"history"] count] == 8);
    track.URI = [NSURL URLWithString:@"spotify:album:1234567890123456789012"];
    requests = t.requests; SAPDownloadCurrentTrack(callback); assert(t.requests == requests);
    track.URI = [NSURL URLWithString:trackURI];
    prepareReady=NO;
    SAPDownloadCurrentTrack(callback);
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"phase"] isEqual:@"native_preparation_failed"];});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"native_preparation_failed"]&&t.requests==requests);
    prepareReady=YES;prepareDeferred=YES;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return pendingPreparation!=nil;});
    SAPCancelTrackDownload();waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert(!pendingRequested());pendingPreparation(YES,@"late preparation");
    prepareDeferred=NO;reset(t,0);
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>requests;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    // Хук транспорта обязан показать журналу и команду, и опросы состояния, не меняя их.
    assert(journalRefreshes > 0 && journalCaller != nil);
    assert(journalSaw(@"AddDownload") > 0 && journalSaw(@"GetItems") > 0);
    assert(journalSaw(@"GetOfflinePlaybackStatus") > 0 && journalSaw(@"SubscribeError") > 0);
    for (NSDictionary *entry in journalObserved) assert([entry[@"source"] hasPrefix:@"app:"] || [entry[@"source"] hasPrefix:@"menu:"]);
    unsigned beforeQueries = t.queries, seen = journalSaw(@"GetItems");
    id lifetime = journalCaller(@"GetItems", SAPProtoBytes(1, [trackURI dataUsingEncoding:NSUTF8StringEncoding]), NO, 0, ^(NSData *data){});
    assert(lifetime != nil && t.queries == beforeQueries + 1 && journalSaw(@"GetItems") == seen + 1);
    // A proven Cosmos route may stop answering later. Replay only its read on
    // the native bridge, while keeping the acknowledged AddDownload single-shot.
    SPTEsperantoCosmosTransport *cosmos=[SPTEsperantoCosmosTransport new];cosmos.scenario=13;
    unsigned observedBefore=journalSaw(@"GetItems");
    [cosmos callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
        payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){}];
    assert(journalSaw(@"GetItems")==observedBefore+1); // Cosmos -> bridge counted once
    unsigned bridgeAdds=t.requests;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return cosmos.requests==1;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"]);
    assert([SAPTrackDownloadReport()[@"transport_class"] isEqual:@"SPTEsperantoTransportBridgeImpl"]);
    assert(cosmos.requests==1 && t.requests==bridgeAdds);
    // Even a burst of native calls creates at most 64 one-shot watchdogs.
    // Timers drain after their deadline and do not form an idle polling loop.
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0;});
    NSUInteger droppedBefore=[SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue];
    for(unsigned i=0;i<100;i++) {
        [t callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
            payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){}];
        assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0);
    }
    assert([SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue]==droppedBefore);
    puts("PASS: answered native requests release their watchdog immediately without filling the 64-call budget");
    SPTEsperantoTransportBridgeImpl *quiet=[SPTEsperantoTransportBridgeImpl new];quiet.scenario=12;
    for(unsigned i=0;i<74;i++)
        [quiet callSingle:@"spotify.offline_esperanto.proto.Offline" method:@"GetItems"
            payload:SAPProtoBytes(1,[trackURI dataUsingEncoding:NSUTF8StringEncoding]) onResponse:^(NSData *data){assert(!"unexpected reply");}];
    assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]<=64);
    assert([SAPTrackDownloadReport()[@"application_watches_dropped"] unsignedIntegerValue]>=10);
    waitFor(^BOOL{return [SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0;});
    assert(quiet.requests==0);
    // Neither an old ERROR state nor a fresh key_denied is a permanent verdict.
    // Acknowledged AddDownload is sent once, while ERROR -> DOWNLOADING ->
    // DOWNLOADED is observed during the bounded settling period.
    for(unsigned scenario=14;scenario<=16;scenario++) {
        nativeFailureForTesting=@{@"uri":trackURI,@"code":@7004,@"name":@"sync_error_offline_key_failed",@"at":@(NSDate.date.timeIntervalSince1970-60)};
        reset(t,scenario);unsigned addsBefore=t.requests;SAPDownloadCurrentTrack(callback);
        waitFor(^BOOL{return t.requests>addsBefore;});
        waitFor(^BOOL{return [SAPTrackDownloadReport()[@"phase"] isEqual:@"waiting_error_update"];});
        waitFor(^BOOL{return !SAPTrackDownloadActive();});
        NSDictionary *value=SAPTrackDownloadReport();
        assert(t.requests==addsBefore+1);
        if(scenario==15) {
            assert([value[@"phase"] isEqual:@"failed"]);
            assert(![value[@"native_error_during_attempt"] boolValue]);
            assert(![value[@"detail"] containsString:@"key_denied / 7004"]);
        } else assert([value[@"phase"] isEqual:@"completed"] && t.queries==7);
    }
    reset(t,17);unsigned beforeNativeFailure=t.requests;SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>beforeNativeFailure;});waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"failed"]);
    assert([SAPTrackDownloadReport()[@"native_error_during_attempt"] boolValue]);
    assert([SAPTrackDownloadReport()[@"detail"] containsString:@"key_denied / 7004"]);
    assert([SAPTrackDownloadReport()[@"error_wait_seconds"] doubleValue]>=0.12);
    nativeFailureForTesting=nil;
    // Optional diagnostics must not be required for AddDownload, verified
    // completion or read-only fallback. No extra streams or journal work.
    SAPDiagnosticsSetEnabled(false);reset(t,0);t.streamLifetime=nil;t.errorCallback=nil;
    NSUInteger oldJournal=journalObserved.count;unsigned oldRefresh=journalRefreshes;unsigned oldAdds=t.requests;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>oldAdds;});
    waitFor(^BOOL{return !SAPTrackDownloadActive();});
    assert([SAPTrackDownloadReport()[@"phase"] isEqual:@"completed"] && t.requests==oldAdds+1);
    assert(t.streamLifetime==nil && journalObserved.count==oldJournal && journalRefreshes==oldRefresh);
    assert([SAPTrackDownloadReport()[@"application_watches_pending"] unsignedIntegerValue]==0);
    // Switching off in the middle cancels only the diagnostic stream.
    SAPDiagnosticsSetEnabled(true);reset(t,4);oldAdds=t.requests;unsigned oldRemoves=t.removes;
    SAPDownloadCurrentTrack(callback);waitFor(^BOOL{return t.requests>oldAdds && t.streamLifetime!=nil;});
    FakeLifetime *diagnosticStream=t.streamLifetime;SAPDiagnosticsSetEnabled(false);
    waitFor(^BOOL{return diagnosticStream.cancelled;});assert(SAPTrackDownloadActive() && t.removes==oldRemoves);
    SAPCancelTrackDownload();waitFor(^BOOL{return !SAPTrackDownloadActive();});assert(t.removes==oldRemoves+1);
    SAPDiagnosticsSetEnabled(true);
    puts("PASS: diagnostics OFF keeps native download and completion; toggling OFF does not cancel the track");
    // Unlike read-only requests, explicit mutations must never fall back to a
    // second transport, including after a timeout or invalid response.
    reset(t,0);
    __block BOOL answered=NO;
    SAPCallReadOnlyService(@"spotify.offline_esperanto.proto.Offline",@"GetOfflinePlaybackStatus",NSData.data,^(NSData *d,NSString *e){assert(d && !e);answered=YES;});
    waitFor(^BOOL{return answered;});
    for(unsigned behavior=0;behavior<3;behavior++) {
        t.commandBehavior=behavior;unsigned before=t.commandCount;__block unsigned completions=0;
        SAPCallOfflineCommandOnce(@"SetOfflinePlaybackAllowed",SAPProtoInteger(1,1),^(NSData *d,NSString *e){
            assert(behavior==0?(d!=nil && e==nil):(d==nil && e!=nil));completions++;
        });
        waitFor(^BOOL{return completions==1;});assert(t.commandCount==before+1 && cosmos.commandCount==0 && bad.commandCount==0);
        if(behavior==1){t.commandLateCallback(SAPProtoInteger(1,1));
            NSDate *until=[NSDate dateWithTimeIntervalSinceNow:0.08];
            while(until.timeIntervalSinceNow>0)[NSRunLoop.mainRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.002]];
            assert(completions==1 && t.commandCount==before+1);
        }
    }
    unsigned before=t.commandCount;answered=NO;
    SAPCallOfflineCommandOnce(@"UnknownMutation",NSData.data,^(NSData *d,NSString *e){assert(!d && e);answered=YES;});
    waitFor(^BOOL{return answered;});assert(t.commandCount==before);
    puts("PASS: explicit enable uses one proven endpoint once; timeout/invalid/late replies never replay it; unknown mutations are rejected");
    puts("PASS: native preparation failure/cancellation; native transport/descriptor routing; exact one-track wire request; journal observation of every Offline call; actual rejection codes vs no response; independent item-state completion; transient/incorrect/nil responses; cached track; cancellation; stale callback; no idle polling");
} }
