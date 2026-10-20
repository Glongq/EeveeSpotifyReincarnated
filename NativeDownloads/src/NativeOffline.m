#import "Localization.h"
#import "NativeOffline.h"
#import "NativeRestrictionsPatch.h"
#import "OfflineLimits.h"
#import "NativeReadiness.h"
#import "TrackJournal.h"
#import "Diagnostics.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach/mach.h>
#import <mach-o/loader.h>
#import <dlfcn.h>
#import <os/lock.h>
#include <stdatomic.h>
#include <stdint.h>
#include <string.h>

static __weak id nativeWrapper;
static BOOL hookInstalled, queueHookInstalled, entityHookInstalled, iconHookInstalled;
static void (*originalMakeEntity)(id,SEL,id,id);
static void (*originalMakeEntityOnly)(id,SEL,id);
static void (*originalResetEntity)(id,SEL,id);
static NSInteger (*originalSyncStatus)(id,SEL,id);
static void *(*originalInit)(void *,SEL,void *,void *,void *,void *);
static unsigned long long (*originalStateForTrack)(id,SEL,id);
static os_unfair_lock stateLock=OS_UNFAIR_LOCK_INIT;
static NSDictionary *snapshot;
static const uint8_t supportedUUID[]={0xf5,0x1d,0xbd,0x93,0x3b,0x8f,0x3a,0x12,0x94,0x31,0x96,0xc6,0x06,0xe3,0xaf,0xc2};
static const uint8_t setterCode[]={0xe6,0x03,0x1e,0xaa,0x37,0xf1,0xf5,0x95,0xfe,0x03,0x06,0xaa,0xfd,0x7b,0x11,0xa9};

@interface SAPNativePreparation : NSObject {
    atomic_bool _finished;
}
@property(nonatomic,copy) void (^completion)(BOOL,NSString *);
- (BOOL)finished;
- (void)finish:(BOOL)ready reason:(NSString *)reason report:(NSDictionary *)report;
@end
@implementation SAPNativePreparation
- (instancetype)init { if((self=[super init]))atomic_init(&_finished,false);return self; }
- (BOOL)finished { return atomic_load(&_finished); }
- (void)finish:(BOOL)ready reason:(NSString *)reason report:(NSDictionary *)report {
    bool wasFinished=false;
    if(!atomic_compare_exchange_strong(&_finished,&wasFinished,true))return;
    NSMutableDictionary *value=[report mutableCopy]?:[NSMutableDictionary dictionary];
    value[@"ready"]=@(ready);value[@"reason"]=reason?:@"";
    NSMutableDictionary *quota=[(value[@"after"]?:value[@"before"]) mutableCopy]?:[NSMutableDictionary dictionary];
    quota[@"ready"]=@(ready);quota[@"reason"]=reason?:@"";quota[@"changed"]=value[@"changed"]?:@NO;
    SAPJournalNoteQuota(quota);
    os_unfair_lock_lock(&stateLock);snapshot=[value copy];os_unfair_lock_unlock(&stateLock);
    dispatch_async(dispatch_get_main_queue(),^{
        void (^callback)(BOOL,NSString *)=self.completion;self.completion=nil;
        if(callback)callback(ready,reason);
    });
}
@end

static BOOL readMemory(uintptr_t address,void *out,size_t size) {
    vm_size_t copied=0;
    return address && vm_read_overwrite(mach_task_self(),address,size,(vm_address_t)out,&copied)==KERN_SUCCESS && copied==size;
}
static BOOL supportedImage(uintptr_t image) {
    struct mach_header_64 header;
    if(!readMemory(image,&header,sizeof(header))||header.magic!=MH_MAGIC_64||header.ncmds>1024||header.sizeofcmds>1048576)return NO;
    uintptr_t cursor=image+sizeof(header),end=cursor+header.sizeofcmds;
    for(unsigned i=0;i<header.ncmds;i++) {
        struct load_command command;
        if(cursor>end||end-cursor<sizeof(command)||!readMemory(cursor,&command,sizeof(command))||command.cmdsize<sizeof(command)||command.cmdsize>end-cursor)return NO;
        if(command.cmd==LC_UUID) {
            struct uuid_command uuid;
            return command.cmdsize>=sizeof(uuid)&&readMemory(cursor,&uuid,sizeof(uuid))&&!memcmp(uuid.uuid,supportedUUID,sizeof(supportedUUID));
        }
        cursor+=command.cmdsize;
    }
    return NO;
}
static NSString *urlText(id value) {
    if([value respondsToSelector:@selector(absoluteString)])return [value absoluteString];
    return [value isKindOfClass:NSString.class]?value:nil;
}
static BOOL nativeState(id wrapper,void **manager,uintptr_t *image,NSMutableDictionary *out) {
    uintptr_t pointer=0,table=0;
    if(!readMemory((uintptr_t)(__bridge void *)wrapper+8,&pointer,8)||!pointer||!readMemory(pointer,&table,8))return NO;
    Dl_info info={0};
    if(!dladdr((void *)table,&info)||!info.dli_fbase)return NO;
    *image=(uintptr_t)info.dli_fbase;
    if(table-*image+UINT64_C(0x100000000)!=UINT64_C(0x10d06cd48)||!supportedImage(*image))return NO;
    uint8_t code[sizeof(setterCode)];
    if(!readMemory(*image+0x1f94658,code,sizeof(code)))return NO;
    BOOL guarded=!memcmp(code,SAPGuardedSetterHead,sizeof(SAPGuardedSetterHead));
    if(guarded) {
        uint8_t stub[sizeof(SAPRestrictionTrampoline)];
        if(memcmp(code+4,setterCode+4,sizeof(code)-4) ||
            !readMemory(*image+SAPRestrictionCaveOffset,stub,sizeof(stub)) ||
            memcmp(stub,SAPRestrictionTrampoline,sizeof(stub)))return NO;
    } else if(memcmp(code,setterCode,sizeof(code)))return NO;
    out[@"restriction_guard_active"]=@(guarded);
    uint32_t keyModeInstruction=0;
    if(readMemory(*image+0x3a6565c,&keyModeInstruction,sizeof(keyModeInstruction))) {
        if(keyModeInstruction==UINT32_C(0x52800022))out[@"offline_key_request_mode"]=@1;
        else if(keyModeInstruction==UINT32_C(0x52800002))out[@"offline_key_request_mode"]=@0;
    }
    // Widened to also cover +0x2b0/+0x2b4: the live reservation counters the slot-reserving
    // function (analysis/queue_track_limit.txt @0x10533b28c) compares against these same
    // limits before it returns TOO_MANY_TRACKS(19). Cross-checked against analysis/queue_restriction_refs.txt.
    uint8_t data[0x30];
    if(!readMemory(pointer+0x2b0,data,sizeof(data)))return NO;
    int32_t currentTracks,currentEpisodes,tracks,episodes;int64_t duration,episodeDuration,abpDuration;
    memcpy(&currentTracks,data,4);memcpy(&currentEpisodes,data+4,4);memcpy(&tracks,data+8,4);
    memcpy(&duration,data+0x10,8);memcpy(&episodes,data+0x18,4);
    memcpy(&episodeDuration,data+0x20,8);memcpy(&abpDuration,data+0x28,8);
    if(currentTracks<0||currentEpisodes<0||tracks<0||episodes<0||duration<0||duration>INT32_MAX||episodeDuration<0||episodeDuration>INT32_MAX||abpDuration<0||abpDuration>INT32_MAX)return NO;
    out[@"current_tracks"]=@(currentTracks);out[@"current_episodes"]=@(currentEpisodes);
    out[@"music_limit"]=@(tracks);out[@"music_duration_seconds"]=@(duration);
    out[@"episode_limit"]=@(episodes);out[@"episode_duration_seconds"]=@(episodeDuration);out[@"abp_duration_seconds"]=@(abpDuration);
    out[@"supported_build"]=@YES;*manager=(void *)pointer;
    // Флаги самой очереди офлайна. Смещения сняты отладчиком на этой же сборке
    // (build/device-v14/queue_breakpoint.py): manager+0x220, вот что отвечает на
    // вопрос «почему трек стоит в waiting» — сеть, политика соединения, лицензия.
    out[@"queue_flags_valid"]=@NO;
    uint8_t flags[0x30];
    if(readMemory(pointer+0x220,flags,sizeof(flags))) {
        uint32_t syncLevel;memcpy(&syncLevel,flags+0x18,4);
        if(flags[1]<=1&&flags[2]<=1&&flags[4]<=1&&flags[0x1c]<=1&&syncLevel<=64) {
            out[@"queue_flags_valid"]=@YES;
            out[@"online"]=@(flags[1]);out[@"connection_allows_offlining"]=@(flags[2]);
            out[@"track_license_expired"]=@(flags[4]);out[@"sync_level"]=@(syncLevel);
            out[@"allow_spotify_tracks"]=@(flags[0x1c]);out[@"token_flag"]=@(flags[0x28]);
            if(flags[5]<=1)out[@"episode_license_expired"]=@(flags[5]);
            if(flags[9]<=1)out[@"disk_full"]=@(flags[9]);
        }
    }
    return YES;
}
static void requestQuotaRaise(NSString *trigger) {
    SAPPrepareNativeOffline(^BOOL{return YES;}, ^(BOOL ready, NSString *reason){
        if(SAPDiagnosticsEnabled())NSLog(@"[SpotifyAudioProbe] offline-quota check (%@): ready=%d reason=%@", trigger, ready, reason);
    });
}
static void *captureInit(void *self,SEL sel,void *scheduler,void *manager,void *sync,void *metadata) {
    // Raw pointers preserve the init method's retained-result/consumed-self ABI.
    void *result=originalInit(self,sel,scheduler,manager,sync,metadata);
    if(result) {
        nativeWrapper=(__bridge id)result;
        // Previously the track/duration quota was only raised on demand, from the
        // single-track probe button. Spotify's own playlist download UI never went
        // through that path, so it kept whatever small limit the account synced.
        // Apply the raise as soon as the native manager exists, before any download starts.
        requestQuotaRaise(@"native manager ready");
    }
    return result;
}
static BOOL methodSignature(Class cls,SEL sel,unsigned arguments,char returns,Method *out) {
    *out=class_getInstanceMethod(cls,sel);
    if(!*out||method_getNumberOfArguments(*out)!=arguments)return NO;
    char type[16];method_getReturnType(*out,type,sizeof(type));return type[0]==returns;
}
void SAPInstallNativeOffline(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{
        Class cls=NSClassFromString(@"SPTOfflineManagerImplementation");
        if(!cls)return;
        SEL selector=NSSelectorFromString(@"initWithScheduler:offlineManager:syncManager:metadataModel:");
        Method method=class_getInstanceMethod(cls,selector);char type[16];
        if(method&&method_getNumberOfArguments(method)==6) {
            method_getReturnType(method,type,sizeof(type));
            if(type[0]=='@') {
                originalInit=(void *)method_getImplementation(method);
                class_replaceMethod(cls,selector,(IMP)captureInit,method_getTypeEncoding(method));hookInstalled=YES;
            }
        }
        // Observes the exact call Spotify's playlist rows use to pick a download icon
        // (native-download-api.md: stateForTrackWithURL:, Q24@0:8@16). Read-only: the
        // original return value is always passed through unchanged.
        SEL stateSelector=NSSelectorFromString(@"stateForTrackWithURL:");Method stateMethod;
        if(methodSignature(cls,stateSelector,3,'Q',&stateMethod)) {
            originalStateForTrack=(void *)method_getImplementation(stateMethod);
            IMP replacement=imp_implementationWithBlock(^unsigned long long(id receiver,id url){
                unsigned long long result=originalStateForTrack(receiver,stateSelector,url);
                if(SAPDiagnosticsEnabled())SAPJournalNoteRowState(urlText(url),(NSUInteger)result);
                return result;
            });
            if(!class_addMethod(cls,stateSelector,replacement,method_getTypeEncoding(stateMethod)))
                class_replaceMethod(cls,stateSelector,replacement,method_getTypeEncoding(stateMethod));
            queueHookInstalled=YES;
        }
        // Кнопка «Скачать» на плейлисте/альбоме: полный список треков, которые Spotify
        // действительно отправил в офлайн (analysis/native-download-api.md).
        SEL entitySelector=NSSelectorFromString(@"makeEntityAvailableOfflineWithURL:trackURLs:");Method entityMethod;
        if(methodSignature(cls,entitySelector,4,'v',&entityMethod)) {
            originalMakeEntity=(void *)method_getImplementation(entityMethod);
            IMP replacement=imp_implementationWithBlock(^(id receiver,id url,id trackURLs){
                if(SAPDiagnosticsEnabled())SAPJournalNoteEntityRequest(urlText(url),trackURLs);
                originalMakeEntity(receiver,entitySelector,url,trackURLs);
            });
            class_replaceMethod(cls,entitySelector,replacement,method_getTypeEncoding(entityMethod));entityHookInstalled=YES;
        }
        SEL entityOnly=NSSelectorFromString(@"makeEntityAvailableOfflineWithURL:");Method entityOnlyMethod;
        if(methodSignature(cls,entityOnly,3,'v',&entityOnlyMethod)) {
            originalMakeEntityOnly=(void *)method_getImplementation(entityOnlyMethod);
            IMP replacement=imp_implementationWithBlock(^(id receiver,id url){
                if(SAPDiagnosticsEnabled())SAPJournalNoteEntityRequest(urlText(url),nil);
                originalMakeEntityOnly(receiver,entityOnly,url);
            });
            class_replaceMethod(cls,entityOnly,replacement,method_getTypeEncoding(entityOnlyMethod));
        }
        SEL resetSelector=NSSelectorFromString(@"resetEntityOfflineAvailabilityWithURL:");Method resetMethod;
        if(methodSignature(cls,resetSelector,3,'v',&resetMethod)) {
            originalResetEntity=(void *)method_getImplementation(resetMethod);
            IMP replacement=imp_implementationWithBlock(^(id receiver,id url){
                if(SAPDiagnosticsEnabled())SAPJournalNoteEntityReset(urlText(url));
                originalResetEntity(receiver,resetSelector,url);
            });
            class_replaceMethod(cls,resetSelector,replacement,method_getTypeEncoding(resetMethod));
        }
        // Значок, который получает строка списка: 0 нет, 1 ожидание, 2 идёт, 3 скачан, 4 ошибка.
        Class iconClass=NSClassFromString(@"SPTFreeTierOfflineStatusUpdatingContentOperation");
        SEL iconSelector=NSSelectorFromString(@"offlineSyncStatusForURL:");Method iconMethod;
        if(iconClass&&methodSignature(iconClass,iconSelector,3,'q',&iconMethod)) {
            originalSyncStatus=(NSInteger (*)(id,SEL,id))method_getImplementation(iconMethod);
            IMP replacement=imp_implementationWithBlock(^NSInteger(id receiver,id url){
                NSInteger status=originalSyncStatus(receiver,iconSelector,url);
                if(SAPDiagnosticsEnabled())SAPJournalNoteUIStatus(urlText(url),status);
                return status;
            });
            if(!class_addMethod(iconClass,iconSelector,replacement,method_getTypeEncoding(iconMethod)))
                class_replaceMethod(iconClass,iconSelector,replacement,method_getTypeEncoding(iconMethod));
            iconHookInstalled=YES;
        }
        // Spotify can resync the real server-granted quota later (e.g. after a restrictions
        // refresh) and lower it again; these two cheap, bounded re-checks catch that instead
        // of leaving the raise as a one-shot applied only at launch.
        dispatch_async(dispatch_get_main_queue(),^{
            [NSNotificationCenter.defaultCenter addObserverForName:UIApplicationDidBecomeActiveNotification object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note) {
                requestQuotaRaise(@"foreground");
            }];
        });
        // Sampling is read-only, every 30 seconds while a journal session is active.
        // No permanent quota timer and no periodic setter invocation.
        SAPJournalSetQuotaSampler(^{SAPSampleNativeOffline();});
    });
}
void SAPPrepareNativeOffline(BOOL (^stillRequested)(void),void (^completion)(BOOL,NSString *)) {
    SAPInstallNativeOffline();
    SAPNativePreparation *operation=[SAPNativePreparation new];operation.completion=completion;
    id wrapper=nativeWrapper;
    if(!wrapper) { [operation finish:NO reason:SAPL(@"Нативный менеджер загрузки ещё не получен. Начни воспроизведение и повтори.",@"The native download manager is not available yet. Start playback and try again.") report:nil];return; }
    SEL schedulerSelector=NSSelectorFromString(@"scheduler"),post=NSSelectorFromString(@"postBlock:");
    id scheduler=((id(*)(id,SEL))objc_msgSend)(wrapper,schedulerSelector);
    if(!scheduler||![scheduler respondsToSelector:post]) { [operation finish:NO reason:SAPL(@"Очередь нативного менеджера загрузки недоступна.",@"The native download manager queue is unavailable.") report:nil];return; }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC),dispatch_get_main_queue(),^{
        [operation finish:NO reason:SAPL(@"Менеджер загрузки не ответил за 5 секунд. Запрос скачивания не отправлен.",@"The download manager did not reply within 5 seconds. No download request was sent.") report:nil];
    });
    ((void(*)(id,SEL,id))objc_msgSend)(scheduler,post,^{
        if(operation.finished)return;
        if(stillRequested&&!stillRequested()) { [operation finish:NO reason:SAPL(@"Подготовка отменена.",@"Preparation cancelled.") report:nil];return; }
        void *manager=NULL;uintptr_t image=0;NSMutableDictionary *before=[NSMutableDictionary dictionary];
        // The app's invalidate method clears wrapper+8. Read it only on its queue.
        if(!nativeState(wrapper,&manager,&image,before)) { [operation finish:NO reason:SAPL(@"Нативный менеджер завершён или сборка Spotify не совпадает с проверенной 9.1.88.",@"The native manager has shut down, or this Spotify build does not match the verified 9.1.88.") report:nil];return; }
        SAPNativeReadiness(before,YES);
        if(![before[@"executable_patches_ready"] boolValue]) {
            [operation finish:NO reason:SAPL(@"В этой сборке Spotify отсутствуют необходимые патчи загрузки. Для sideload установи подготовленную IPA; на jailbreak проверь совместимость сборки и загрузку твика.",@"This Spotify build is missing the required download patches. For sideloading, install the prepared IPA; on jailbreak, check the supported build and tweak loading.") report:@{@"before":before,@"changed":@NO,@"failure":@"native_patches_missing",@"native_queue":@YES}];
            return;
        }
        // v16: previously only raised the quota when it was exactly (0,0) — the
        // "never synced" sentinel. A real account can sync a small nonzero limit
        // (this is what capped the user's playlist download after a handful of
        // tracks: current_tracks reached music_limit and new reservations started
        // returning TOO_MANY_TRACKS=19). Now raise whenever it's below the target,
        // and never lower an existing higher value.
        const int32_t desiredDurationSeconds=SAPMinimumMusicDurationSeconds, desiredTrackLimit=SAPMinimumTrackLimit;
        BOOL changed=[before[@"music_limit"] intValue]<desiredTrackLimit || [before[@"music_duration_seconds"] longLongValue]<desiredDurationSeconds;
        if(changed) {
            int32_t newDuration=(int32_t)MAX([before[@"music_duration_seconds"] longLongValue],(long long)desiredDurationSeconds);
            int32_t newTrackLimit=(int32_t)MAX([before[@"music_limit"] intValue],desiredTrackLimit);
            ((void(*)(void *,int32_t,int32_t,int32_t,int32_t,int32_t))(image+0x1f94658))(manager,newDuration,newTrackLimit,[before[@"episode_duration_seconds"] intValue],[before[@"episode_limit"] intValue],[before[@"abp_duration_seconds"] intValue]);
        }
        NSMutableDictionary *after=[NSMutableDictionary dictionary];
        BOOL valid=nativeState(wrapper,&manager,&image,after);
        BOOL ready=SAPNativeReadiness(after,valid);
        [operation finish:ready reason:ready?SAPL(@"Нативный менеджер подготовлен",@"Native download manager ready"):SAPL(@"Нативный менеджер не подтвердил разрешение музыкальной загрузки.",@"The native manager did not confirm permission to download music.") report:@{@"before":before,@"after":after,@"changed":@(changed),@"native_queue":@YES}];
    });
}
void SAPReadNativeTrackState(NSString *uri) {
    id wrapper=nativeWrapper;
    if(!wrapper || !originalStateForTrack || ![uri hasPrefix:@"spotify:track:"])return;
    // This public wrapper uses scheduler.runBlock: internally. Call it as the UI
    // does, outside that scheduler; never nest a synchronous runBlock inside postBlock.
    void (^read)(void)=^{
        if(wrapper!=nativeWrapper)return;
        NSUInteger legacy=originalStateForTrack(wrapper,NSSelectorFromString(@"stateForTrackWithURL:"),[NSURL URLWithString:uri]);
        SAPJournalNoteRowState(uri,legacy);
    };
    if(NSThread.isMainThread)read();else dispatch_async(dispatch_get_main_queue(),read);
}
void SAPSampleNativeOffline(void) {
    id wrapper=nativeWrapper;
    if(!wrapper) {SAPJournalNoteQuota(@{@"ready":@NO,@"reason":@"read-only: manager unavailable"});return;}
    SEL getScheduler=NSSelectorFromString(@"scheduler"),post=NSSelectorFromString(@"postBlock:");
    if(![wrapper respondsToSelector:getScheduler])return;
    id scheduler=((id(*)(id,SEL))objc_msgSend)(wrapper,getScheduler);
    if(![scheduler respondsToSelector:post])return;
    ((void(*)(id,SEL,id))objc_msgSend)(scheduler,post,^{
        void *manager=NULL;uintptr_t image=0;NSMutableDictionary *value=[NSMutableDictionary dictionary];
        BOOL valid=nativeState(wrapper,&manager,&image,value);
        SAPNativeReadiness(value,valid);
        value[@"reason"]=@"read-only sample on native queue";
        SAPJournalNoteQuota(value);
    });
}
NSDictionary *SAPNativeOfflineReport(void) {
    os_unfair_lock_lock(&stateLock);NSDictionary *state=snapshot;os_unfair_lock_unlock(&stateLock);
    NSMutableDictionary *out=[state mutableCopy]?:[NSMutableDictionary dictionary];
    out[@"hook_installed"]=@(hookInstalled);out[@"wrapper_available"]=@(nativeWrapper!=nil);
    out[@"queue_hook_installed"]=@(queueHookInstalled);out[@"entity_hook_installed"]=@(entityHookInstalled);
    out[@"icon_hook_installed"]=@(iconHookInstalled);
    return out;
}
#ifdef SAP_RUNTIME_TESTING
id SAPNativeOfflineWrapperForTesting(void) { return nativeWrapper; }
void SAPNativeOfflineSnapshotForTesting(void (^completion)(NSDictionary *)) {
    id wrapper=nativeWrapper;
    id scheduler=((id(*)(id,SEL))objc_msgSend)(wrapper,NSSelectorFromString(@"scheduler"));
    ((void(*)(id,SEL,id))objc_msgSend)(scheduler,NSSelectorFromString(@"postBlock:"),^{
        NSMutableDictionary *state=[NSMutableDictionary dictionary];void *manager=NULL;uintptr_t image=0;
        state[@"valid"]=@(nativeState(wrapper,&manager,&image,state));
        // Test-only identity lookup: inspect executable pointers, never key data.
        uintptr_t provider=0,table=0,request=0;
        if(manager && readMemory((uintptr_t)manager+0x290,&provider,sizeof(provider)) &&
            readMemory(provider,&table,sizeof(table)) && readMemory(table+0x10,&request,sizeof(request))) {
            Dl_info tableInfo={0},requestInfo={0};
            if(dladdr((void *)table,&tableInfo) && (uintptr_t)tableInfo.dli_fbase==image)
                state[@"key_provider_vtable_va"]=[NSString stringWithFormat:@"0x%llx",(unsigned long long)(table-image+UINT64_C(0x100000000))];
            if(dladdr((void *)request,&requestInfo) && (uintptr_t)requestInfo.dli_fbase==image)
                state[@"key_provider_request_va"]=[NSString stringWithFormat:@"0x%llx",(unsigned long long)(request-image+UINT64_C(0x100000000))];
        }
        dispatch_async(dispatch_get_main_queue(),^{completion(state);});
    });
}
void SAPNativeOfflineZeroUpdateForTesting(void (^completion)(NSDictionary *)) {
    id wrapper=nativeWrapper;if(!wrapper){completion(@{@"error":@"no wrapper"});return;}
    id scheduler=((id(*)(id,SEL))objc_msgSend)(wrapper,NSSelectorFromString(@"scheduler"));
    ((void(*)(id,SEL,id))objc_msgSend)(scheduler,NSSelectorFromString(@"postBlock:"),^{
        NSMutableDictionary *before=[NSMutableDictionary dictionary];void *manager=NULL;uintptr_t image=0;
        BOOL guarded=nativeState(wrapper,&manager,&image,before)&&[before[@"restriction_guard_active"] boolValue];
        if(guarded)((void(*)(void *,int32_t,int32_t,int32_t,int32_t,int32_t))(image+0x1f94658))
            (manager,0,0,[before[@"episode_duration_seconds"] intValue],[before[@"episode_limit"] intValue],[before[@"abp_duration_seconds"] intValue]);
        NSMutableDictionary *after=[NSMutableDictionary dictionary];BOOL valid=nativeState(wrapper,&manager,&image,after);
        NSDictionary *result=@{@"guarded":@(guarded),@"zero_update_tested":@(guarded),@"before":before,@"after":after,@"valid":@(valid)};
        dispatch_async(dispatch_get_main_queue(),^{completion(result);});
    });
}
#endif
