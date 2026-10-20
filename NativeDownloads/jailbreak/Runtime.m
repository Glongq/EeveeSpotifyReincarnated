// Native downloads adapter: guarded jailbreak writes or a statically prepared IPA.
// Only the exact Spotify build used by v7 is supported; never scan for opcodes.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <objc/runtime.h>
#include <stdatomic.h>
#import <libkern/OSCacheControl.h>
#import "fishhook.h"
#import "Guards.h"
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static atomic_bool ready;
static BOOL lifecycleInstalled;
static void *(*managerInit)(void *,SEL,void *,void *,void *,void *);
static BOOL bytes(const void *a, const void *b, size_t n) { return memcmp(a,b,n)==0; }
#ifdef SAP_JB_TEST
extern const struct mach_header_64 *JBTestHeader;
extern BOOL JBTestWrite(void *,const void *,size_t);
#endif

// A bundled Substrate compatibility symbol is not permission to modify signed
// executable pages on stock iOS. Check capability before taking over downloads.
#ifndef SAP_JB_TEST
static void (*executableWriter(void))(void *,const void *,size_t) {
    void (*writer)(void *,const void *,size_t)=dlsym(RTLD_DEFAULT,"MSHookMemory");
    Dl_info engine={0};
    if(!writer || !dladdr((void *)writer,&engine) || !engine.dli_fname)return NULL;
    NSString *path=[[@(engine.dli_fname) stringByResolvingSymlinksInPath] stringByStandardizingPath];
    NSString *appRoot=[[NSBundle.mainBundle.bundlePath stringByResolvingSymlinksInPath] stringByAppendingString:@"/"];
    // Reject a compatibility writer from any app bundle, including the LC host.
    return ([path hasPrefix:appRoot] || [path rangeOfString:@".app/"].location!=NSNotFound)?NULL:writer;
}
#endif
static BOOL canWriteExecutable(void) {
#ifdef SAP_JB_TEST
    extern BOOL JBTestWriterAvailable;
    return JBTestWriterAvailable;
#else
    return executableWriter()!=NULL;
#endif
}

// The injection engine owns executable-page remapping. No permanent RWX pages.
static BOOL writeCode(void *target, const void *data, size_t size) {
#ifdef SAP_JB_TEST
    return canWriteExecutable() && JBTestWrite(target,data,size);
#else
    void (*writer)(void *,const void *,size_t)=executableWriter();
    if(!writer)return NO;
    writer(target,data,size);
    sys_icache_invalidate(target,size);
    return bytes(target,data,size);
#endif
}

#ifndef SAP_JB_TEST
static void *plainFunction(void *pointer) {
#if __has_feature(ptrauth_calls)
    return ptrauth_strip(pointer,ptrauth_key_function_pointer);
#else
    return pointer;
#endif
}

static void installAudioImports(const struct mach_header_64 *header, intptr_t slide) {
    // Rebind the main executable only. Never inline-hook AudioToolbox itself:
    // AudioProbe resolves its original functions directly from that framework.
    void *originals[5]={0};
    struct rebinding bindings[]={
        {"AudioUnitSetProperty",plainFunction((void *)&AudioUnitSetProperty),&originals[0]},
        {"AudioUnitGetProperty",plainFunction((void *)&AudioUnitGetProperty),&originals[1]},
        {"AudioOutputUnitStart",plainFunction((void *)&AudioOutputUnitStart),&originals[2]},
        {"AudioOutputUnitStop",plainFunction((void *)&AudioOutputUnitStop),&originals[3]},
        {"AudioComponentInstanceDispose",plainFunction((void *)&AudioComponentInstanceDispose),&originals[4]},
    };
    int status=rebind_symbols_image((void *)header,slide,bindings,5);
    unsigned found=0; for(unsigned i=0;i<5;i++) if(originals[i]) found++;
    NSLog(@"[EeveeSpotify][NativeDownloads] Audio import registration: %u/5, status %d (PCM still requires device verification)",found,status);
}
#endif

static BOOL spotifyIdentity(const struct mach_header_64 *h) {
    if(!h || h->magic!=MH_MAGIC_64 || h->cputype!=CPU_TYPE_ARM64 ||
       h->ncmds>4096 || h->sizeofcmds>1024*1024)return NO;
    uintptr_t cursor=sizeof(*h),end=cursor+h->sizeofcmds;
    BOOL matches=NO;
    for(uint32_t j=0;j<h->ncmds;j++) {
        if(cursor+sizeof(struct load_command)>end)return NO;
        const struct load_command *lc=(const void *)((const uint8_t *)h+cursor);
        if(lc->cmdsize<sizeof(*lc) || cursor+lc->cmdsize>end)return NO;
        if(lc->cmd==LC_UUID && lc->cmdsize==sizeof(struct uuid_command))
            matches=bytes(((const struct uuid_command *)lc)->uuid,JB_UUID,sizeof(JB_UUID));
        cursor+=lc->cmdsize;
    }
    return cursor==end && matches;
}
#ifndef SAP_JB_TEST
static const struct mach_header_64 *spotifyImage(void) {
    // LiveContainer can keep its host at dyld index 0. Select Spotify by its
    // exact Mach-O identity, never by offsets into the host or by opcode scans.
    uint32_t count=_dyld_image_count();
    for(uint32_t i=0;i<count;i++) {
        const struct mach_header_64 *h=(const void *)_dyld_get_image_header(i);
        if(spotifyIdentity(h))return h;
    }
    return NULL;
}
#endif

static BOOL prepare(BOOL apply) {
#ifdef SAP_JB_TEST
    const struct mach_header_64 *header=JBTestHeader;
#else
    const struct mach_header_64 *header=spotifyImage();
#endif
    if(!header || header->magic!=MH_MAGIC_64 || header->cputype!=CPU_TYPE_ARM64 ||
       header->sizeofcmds>1024*1024 || header->ncmds>4096) return NO;
    const uint8_t *base=(const void *)header;
    uintptr_t end=sizeof(*header)+header->sizeofcmds, cursor=sizeof(*header);
    BOOL uuidOK=NO; uint64_t textSize=0, firstSection=UINT64_MAX;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(cursor+sizeof(struct load_command)>end) return NO;
        const struct load_command *lc=(const void *)(base+cursor);
        if(lc->cmdsize<sizeof(*lc) || cursor+lc->cmdsize>end) return NO;
        if(lc->cmd==LC_UUID && lc->cmdsize==sizeof(struct uuid_command))
            uuidOK=bytes(((const struct uuid_command *)lc)->uuid,JB_UUID,sizeof(JB_UUID));
        if(lc->cmd==LC_SEGMENT_64 && lc->cmdsize>=sizeof(struct segment_command_64)) {
            const struct segment_command_64 *seg=(const void *)lc;
            if(!strncmp(seg->segname,"__TEXT",16)) {
                if(seg->vmaddr!=0x100000000 || seg->fileoff || (seg->initprot&5)!=5 ||
                   seg->cmdsize<sizeof(*seg)+(uint64_t)seg->nsects*sizeof(struct section_64)) return NO;
                textSize=seg->filesize;
                const struct section_64 *sections=(const void *)(seg+1);
                for(uint32_t j=0;j<seg->nsects;j++)
                    if(sections[j].addr>=seg->vmaddr && sections[j].size)
                        firstSection=MIN(firstSection,sections[j].addr-seg->vmaddr);
            }
        }
        cursor+=lc->cmdsize;
    }
    if(cursor!=end || !uuidOK || textSize<JB_MappingOffset+sizeof(JB_Mapping) ||
       JB_CaveOffset<end || JB_CaveOffset+sizeof(JB_Trampoline)>firstSection) return NO;
    uint8_t *setter=(void *)(base+JB_SetterOffset), *cave=(void *)(base+JB_CaveOffset);
    uint8_t *key=(void *)(base+JB_KeyCallOffset);
    BOOL setterPatched=bytes(setter,JB_SetterPatched,4);
    BOOL keyPatched=bytes(key,JB_KeyPatched,4);
    uint8_t window[sizeof(JB_KeyOriginal)]; memcpy(window,base+JB_KeyWindowOffset,sizeof(window));
    if(keyPatched) memcpy(window+(JB_KeyCallOffset-JB_KeyWindowOffset),JB_KeyOriginal+(JB_KeyCallOffset-JB_KeyWindowOffset),4);
    uint8_t zero[sizeof(JB_Trampoline)]={0};
    if(!bytes(base+JB_ProviderOffset,JB_Provider,sizeof(JB_Provider)) ||
       !bytes(base+JB_MappingOffset,JB_Mapping,sizeof(JB_Mapping)) ||
       !bytes(window,JB_KeyOriginal,sizeof(window)) ||
       !bytes(setter+4,JB_SetterOriginal+4,sizeof(JB_SetterOriginal)-4) ||
       (!setterPatched && !bytes(setter,JB_SetterOriginal,4)) ||
       (setterPatched ? !bytes(cave,JB_Trampoline,sizeof(JB_Trampoline)) :
         !bytes(cave,zero,sizeof(zero)))) return NO;
    if((!setterPatched || !keyPatched) && !canWriteExecutable()) {
        NSLog(@"[EeveeSpotify][NativeDownloads] Required executable patches missing and no jailbreak writer available; use a prepared IPA for sideloading");
        return NO;
    }
    if(!apply) return YES; // Read-only preflight during dylib initialization.
    // Preflight every guard before changing anything. Cave first, branch second.
    if(!setterPatched) {
        if(!writeCode(cave,JB_Trampoline,sizeof(JB_Trampoline))) {
            writeCode(cave,zero,sizeof(zero));
            return NO;
        }
        if(!writeCode(setter,JB_SetterPatched,4)) {
            // Restore the branch before removing its destination.
            if(writeCode(setter,JB_SetterOriginal,4)) writeCode(cave,zero,sizeof(zero));
            return NO;
        }
    }
    if(!keyPatched && !writeCode(key,JB_KeyPatched,4)) {
        writeCode(key,JB_KeyOriginal+(JB_KeyCallOffset-JB_KeyWindowOffset),4);
        if(!setterPatched && writeCode(setter,JB_SetterOriginal,4)) writeCode(cave,zero,sizeof(zero));
        return NO;
    }
#ifndef SAP_JB_TEST
    installAudioImports(header,(intptr_t)((uintptr_t)header-UINT64_C(0x100000000)));
#endif
    return YES;
}

static BOOL install(void) { return prepare(YES); }

static void activateForManager(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        BOOL installed=install();
        atomic_store_explicit(&ready,installed,memory_order_release);
        NSLog(@"[EeveeSpotify][NativeDownloads] v7.3 jailbreak adapter %@ at offline-manager initialization",installed?@"ready":@"inactive");
    });
}

static void *initializeManager(void *object,SEL selector,void *scheduler,void *manager,void *sync,void *metadata) {
    // Preserve init's consumed-self/retained-result ABI exactly, like v7's existing
    // native wrapper hook. Apply before the original constructor can start work.
    activateForManager();
    return managerInit(object,selector,scheduler,manager,sync,metadata);
}

BOOL EeveeNativeDownloadsWillHandleDownloads(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if(!prepare(NO)) return;
        Class cls=NSClassFromString(@"SPTOfflineManagerImplementation");
        SEL selector=NSSelectorFromString(@"initWithScheduler:offlineManager:syncManager:metadataModel:");
        Method method=class_getInstanceMethod(cls,selector);
        if(!method || method_getNumberOfArguments(method)!=6) return;
        char type[16];method_getReturnType(method,type,sizeof(type));
        if(type[0]!='@') return;
        managerInit=(void *)method_getImplementation(method);
        class_replaceMethod(cls,selector,(IMP)initializeManager,method_getTypeEncoding(method));
        lifecycleInstalled=YES;
    });
    return lifecycleInstalled;
}

BOOL EeveeNativeDownloadsIsReady(void) {
    return atomic_load_explicit(&ready,memory_order_acquire);
}

#ifdef SAP_JB_IMPORT_TEST
__attribute__((visibility("default"))) void SAPJBTestInstallImports(void) {
    installAudioImports((const void *)_dyld_get_image_header(0),_dyld_get_image_vmaddr_slide(0));
}
#endif

#if !defined(SAP_JB_TEST) && !defined(SAP_JB_IMPORT_TEST)
__attribute__((constructor(101))) static void loadNativeAdapter(void) {
    @autoreleasepool { EeveeNativeDownloadsWillHandleDownloads(); }
}
#endif
