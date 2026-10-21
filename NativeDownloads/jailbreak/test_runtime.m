// Execute the production adapter against a synthetic mapped ARM64 image.
#define SAP_JB_TEST 1
#import "Runtime.m"
#import "../src/NativeReadiness.h"
#import <sys/mman.h>
#import <assert.h>
const struct mach_header_64 *JBTestHeader;
static unsigned writes, failWrite;
BOOL JBTestWriterAvailable=YES;
BOOL JBTestWrite(void *p,const void *data,size_t size) {
    writes++;
    if(writes==failWrite) { // Simulate a partially completed engine write.
        memcpy(p,data,size/2); return NO;
    }
    memcpy(p,data,size); return YES;
}
static uint8_t *fixture(void) {
    size_t n=JB_DlsymOffset+4096;
    uint8_t *p=mmap(NULL,n,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(p!=MAP_FAILED);
    struct mach_header_64 *h=(void *)p;
    h->magic=MH_MAGIC_64;h->cputype=CPU_TYPE_ARM64;h->ncmds=2;
    h->sizeofcmds=sizeof(struct uuid_command)+sizeof(struct segment_command_64)+sizeof(struct section_64);
    struct uuid_command *u=(void *)(h+1);u->cmd=LC_UUID;u->cmdsize=sizeof(*u);memcpy(u->uuid,JB_UUID,16);
    struct segment_command_64 *s=(void *)(u+1);s->cmd=LC_SEGMENT_64;s->cmdsize=sizeof(*s)+sizeof(struct section_64);
    strcpy(s->segname,"__TEXT");s->vmaddr=0x100000000;s->filesize=n;s->vmsize=n;s->initprot=5;s->nsects=1;
    struct section_64 *section=(void *)(s+1);section->addr=s->vmaddr+0x24000;section->size=n-0x24000;
    memcpy(p+JB_SetterOffset,JB_SetterOriginal,sizeof(JB_SetterOriginal));
    memcpy(p+JB_KeyWindowOffset,JB_KeyOriginal,sizeof(JB_KeyOriginal));
    memcpy(p+JB_ProviderOffset,JB_Provider,sizeof(JB_Provider));
    memcpy(p+JB_MappingOffset,JB_Mapping,sizeof(JB_Mapping));
    memcpy(p+JB_DlsymOffset,JB_Dlsym,sizeof(JB_Dlsym));
    memcpy(p+SAPTraceSuccessOffset,SAPTraceSuccessOriginal,sizeof(SAPTraceSuccessOriginal));
    memcpy(p+SAPTraceFailureOffset,SAPTraceFailureOriginal,sizeof(SAPTraceFailureOriginal));
    JBTestHeader=(void *)p; writes=0;failWrite=0;JBTestWriterAvailable=YES;return p;
}
static void releaseImage(uint8_t *p) {munmap(p,JB_DlsymOffset+4096);}
static unsigned initialized;
static void *originalManagerInit(void *object,SEL selector,void *scheduler,void *manager,void *sync,void *metadata) {
    assert(writes==8 && EeveeNativeDownloadsIsReady());
    assert(scheduler==(void *)1 && manager==(void *)2 && sync==(void *)3 && metadata==(void *)4);
    initialized++;return object;
}
int main(void) {
    // Reproduce the peer report: raised quotas with untouched code is NOT ready.
    NSMutableDictionary *state=[@{@"music_limit":@1000000,@"music_duration_seconds":@2147483647,
        @"restriction_guard_active":@NO,@"offline_key_request_mode":@1} mutableCopy];
    assert(!SAPNativeReadiness(state,YES));
    assert([state[@"quota_ready"] boolValue] && ![state[@"executable_patches_ready"] boolValue]);
    state[@"restriction_guard_active"]=@YES;
    assert(!SAPNativeReadiness(state,YES));
    [state removeObjectForKey:@"offline_key_request_mode"];
    assert(!SAPNativeReadiness(state,YES)); // nil must not be interpreted as mode 0.
    state[@"offline_key_request_mode"]=@0;
    assert(SAPNativeReadiness(state,YES));
    assert(!SAPNativeReadiness(state,NO));
    state[@"music_limit"]=@1;
    assert(!SAPNativeReadiness(state,YES) && [state[@"executable_patches_ready"] boolValue]);
    puts("PASS: real readiness policy rejects missing patches, unknown key mode, invalid manager and insufficient quotas");
    uint8_t *p=fixture();
    assert(spotifyIdentity((const void *)p));
    p[sizeof(struct mach_header_64)+8]^=0x80;
    assert(!spotifyIdentity((const void *)p)); // A host/different UUID is skipped.
    p[sizeof(struct mach_header_64)+8]^=0x80;
    assert(install());assert(writes==8);
    assert(!memcmp(p+JB_KeyCallOffset,SAPTraceRequestHead,4));
    assert(!memcmp(p+JB_CaveOffset,JB_Trampoline,sizeof(JB_Trampoline)));
    assert(install());assert(writes==8);releaseImage(p);
    p=fixture();JBTestWriterAvailable=NO;
    assert(!prepare(NO) && !install() && writes==0);releaseImage(p);
    p=fixture();assert(install());writes=0;JBTestWriterAvailable=NO;
    assert(prepare(NO) && install() && writes==0);releaseImage(p);
    const size_t corrupt[]={sizeof(struct mach_header_64)+8,JB_SetterOffset,JB_CaveOffset,JB_KeyWindowOffset,JB_ProviderOffset,JB_MappingOffset,JB_DlsymOffset,SAPTraceSuccessOffset,SAPTraceFailureOffset};
    for(unsigned i=0;i<sizeof(corrupt)/sizeof(*corrupt);i++) {
        p=fixture();p[corrupt[i]]^=0x80;assert(!install());assert(writes==0);releaseImage(p);
    }
    for(unsigned failure=1;failure<=8;failure++) {
        p=fixture();failWrite=failure;assert(!install());
        assert(!memcmp(p+JB_SetterOffset,JB_SetterOriginal,sizeof(JB_SetterOriginal)));
        assert(!memcmp(p+JB_KeyWindowOffset,JB_KeyOriginal,sizeof(JB_KeyOriginal)));
        uint8_t zero[sizeof(JB_Trampoline)]={0};assert(!memcmp(p+JB_CaveOffset,zero,sizeof(zero)));
        assert(!memcmp(p+SAPTraceSuccessOffset,SAPTraceSuccessOriginal,sizeof(SAPTraceSuccessOriginal)));
        assert(!memcmp(p+SAPTraceFailureOffset,SAPTraceFailureOriginal,sizeof(SAPTraceFailureOriginal)));
        assert(prepare(NO)); // Every partial write restored all guards and padding.
        releaseImage(p);
    }
    p=fixture();
    Class cls=objc_allocateClassPair(NSObject.class,"SPTOfflineManagerImplementation",0);
    SEL selector=NSSelectorFromString(@"initWithScheduler:offlineManager:syncManager:metadataModel:");
    assert(class_addMethod(cls,selector,(IMP)originalManagerInit,"@48@0:8^v16^v24^v32^v40"));objc_registerClassPair(cls);
    assert(EeveeNativeDownloadsWillHandleDownloads());
    assert(EeveeNativeDownloadsWillHandleDownloads());
    assert(writes==0 && !EeveeNativeDownloadsIsReady());
    id instance=[cls alloc];
    void *(*init)(void *,SEL,void *,void *,void *,void *)=(void *)class_getMethodImplementation(cls,selector);
    assert(init((__bridge void *)instance,selector,(void *)1,(void *)2,(void *)3,(void *)4)==(__bridge void *)instance);
    assert(writes==8 && initialized==1 && EeveeNativeDownloadsIsReady());
    assert(init((__bridge void *)instance,selector,(void *)1,(void *)2,(void *)3,(void *)4)==(__bridge void *)instance);
    assert(writes==8 && initialized==2);releaseImage(p);
    puts("PASS: v7 guards, idempotency, incompatible images, and partial-write rollback");
    puts("PASS: zero executable writes during startup/preflight; manager event applies once before original init; arguments and result preserved");
}
