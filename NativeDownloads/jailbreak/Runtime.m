// Jailbreak adapter for v7. The native downloader sources are unchanged.
// Only the exact Spotify build used by v7 is supported; never scan for opcodes.
#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach/mach.h>
#import <dlfcn.h>
#import <libkern/OSCacheControl.h>
#import "fishhook.h"
#import "Guards.h"
#if __has_feature(ptrauth_calls)
#import <ptrauth.h>
#endif

static BOOL ready;
static BOOL bytes(const void *a, const void *b, size_t n) { return memcmp(a,b,n)==0; }
#ifdef SAP_JB_TEST
extern const struct mach_header_64 *JBTestHeader;
extern BOOL JBTestWrite(void *,const void *,size_t);
#endif

// The injection engine owns executable-page remapping. No permanent RWX pages.
static BOOL writeCode(void *target, const void *data, size_t size) {
#ifdef SAP_JB_TEST
    return JBTestWrite(target,data,size);
#else
    void (*hookMemory)(void *,const void *,size_t)=dlsym(RTLD_DEFAULT,"MSHookMemory");
    if (!hookMemory) {
        NSLog(@"[EeveeSpotify][NativeDownloads] MSHookMemory unavailable; leaving Spotify unchanged");
        return NO;
    }
    hookMemory(target,data,size);
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

static BOOL install(void) {
#ifdef SAP_JB_TEST
    const struct mach_header_64 *header=JBTestHeader;
#else
    const struct mach_header_64 *header=(const void *)_dyld_get_image_header(0);
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
    installAudioImports(header,_dyld_get_image_vmaddr_slide(0));
#endif
    return YES;
}

BOOL EeveeNativeDownloadsIsReady(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        ready=install();
        NSLog(@"[EeveeSpotify][NativeDownloads] v7 jailbreak adapter %@",ready?@"ready":@"inactive (unsupported binary or patch engine)");
    });
    return ready;
}

#ifdef SAP_JB_IMPORT_TEST
__attribute__((visibility("default"))) void SAPJBTestInstallImports(void) {
    installAudioImports((const void *)_dyld_get_image_header(0),_dyld_get_image_vmaddr_slide(0));
}
#endif

#if !defined(SAP_JB_TEST) && !defined(SAP_JB_IMPORT_TEST)
__attribute__((constructor(101))) static void loadNativeAdapter(void) {
    @autoreleasepool { EeveeNativeDownloadsIsReady(); }
}
#endif
