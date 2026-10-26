#include "JailbreakPatches.h"
#include "NativeRestrictionsPatch.h"
#include "NativeKeyModePatch.h"
#include "NativeKeyPatch.h"
#include "NativeTracePatch.h"
#include <mach-o/loader.h>
#include <mach/machine.h>
#include <string.h>

static bool fail(const char **reason,const char *message) {if(reason)*reason=message;return false;}
static bool zeroes(const uint8_t *bytes,size_t count) {for(size_t i=0;i<count;i++)if(bytes[i])return false;return true;}
bool SAPJBApplyPatches(uint8_t *image,size_t textSize,SAPJBWrite writer,void *context,const char **reason) {
    if(reason)*reason="unsupported_image";
    if(!image||textSize<sizeof(struct mach_header_64))return false;
    const struct mach_header_64 *header=(const void *)image;
    if(header->magic!=MH_MAGIC_64||header->cputype!=CPU_TYPE_ARM64||header->filetype!=MH_EXECUTE||
       header->ncmds>1024||header->sizeofcmds>1048576||sizeof(*header)+header->sizeofcmds>textSize)return false;
    size_t cursor=sizeof(*header),end=cursor+header->sizeofcmds,firstSection=textSize;
    bool uuidOK=false,textOK=false;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(cursor>end||end-cursor<sizeof(struct load_command))return false;
        const struct load_command *cmd=(const void *)(image+cursor);
        if(cmd->cmdsize<sizeof(*cmd)||cmd->cmdsize>end-cursor)return false;
        if(cmd->cmd==LC_UUID) {
            if(cmd->cmdsize<sizeof(struct uuid_command))return false;
            uuidOK=!memcmp(((const struct uuid_command *)cmd)->uuid,SAPJBSupportedUUID,16);
        }
        if(cmd->cmd==LC_SEGMENT_64) {
            if(cmd->cmdsize<sizeof(struct segment_command_64))return false;
            const struct segment_command_64 *seg=(const void *)cmd;
            if(!strncmp(seg->segname,"__TEXT",16)) {
                if(seg->nsects>(cmd->cmdsize-sizeof(*seg))/sizeof(struct section_64))return false;
                textOK=seg->vmaddr==UINT64_C(0x100000000)&&seg->fileoff==0&&seg->filesize==textSize&&(seg->initprot&5)==5;
                const struct section_64 *section=(const void *)(seg+1);
                for(uint32_t s=0;s<seg->nsects;s++)if(section[s].offset&&section[s].offset<firstSection)firstSection=section[s].offset;
            }
        }
        cursor+=cmd->cmdsize;
    }
    if(cursor!=end||!uuidOK||!textOK)return false;
    const struct {size_t offset,length;} spans[]={
        {SAPJBSetterOffset,sizeof(SAPJBSetterOriginal)},
        {SAPJBKeyWindowOffset,sizeof(SAPJBKeyOriginal)},
        {SAPJBProviderOffset,sizeof(SAPJBProviderOriginal)},
        {SAPJBMappingOffset,sizeof(SAPJBMappingOriginal)},
        {SAPJBDLSymStubOffset,sizeof(SAPJBDLSymStubOriginal)},
        {SAPKeyModeCaveOffset,sizeof(SAPKeyModeTrampoline)},
        {SAPRestrictionCaveOffset,sizeof(SAPRestrictionTrampoline)},
        {SAPTraceRequestCaveOffset,sizeof(SAPTraceRequestCode)},
        {SAPTraceSuccessOffset,sizeof(SAPJBSuccessOriginal)},
        {SAPTraceSuccessCaveOffset,sizeof(SAPTraceSuccessCode)},
        {SAPTraceFailureOffset,sizeof(SAPJBFailureOriginal)},
        {SAPTraceFailureCaveOffset,sizeof(SAPTraceFailureCode)}};
    for(size_t i=0;i<sizeof(spans)/sizeof(*spans);i++)
        if(spans[i].offset>textSize||spans[i].length>textSize-spans[i].offset)return false;
    const struct {size_t offset,length;} caves[]={
        {SAPTraceRequestCaveOffset,sizeof(SAPTraceRequestCode)},
        {SAPTraceSuccessCaveOffset,sizeof(SAPTraceSuccessCode)},
        {SAPTraceFailureCaveOffset,sizeof(SAPTraceFailureCode)},
        {SAPKeyModeCaveOffset,sizeof(SAPKeyModeTrampoline)},
        {SAPRestrictionCaveOffset,sizeof(SAPRestrictionTrampoline)}};
    for(size_t i=0;i<sizeof(caves)/sizeof(*caves);i++) {
        if(caves[i].offset<end||caves[i].offset+caves[i].length>firstSection)return false;
        if(i&&caves[i-1].offset+caves[i-1].length>caves[i].offset)return false;
    }
    uint8_t *setter=image+SAPJBSetterOffset,*cave=image+SAPRestrictionCaveOffset,*key=image+SAPJBKeyWindowOffset;
    bool guarded=!memcmp(setter,SAPGuardedSetterHead,4)&&
        !memcmp(setter+4,SAPJBSetterOriginal+4,sizeof(SAPJBSetterOriginal)-4)&&
        !memcmp(cave,SAPRestrictionTrampoline,sizeof(SAPRestrictionTrampoline));
    if(!guarded&&(memcmp(setter,SAPJBSetterOriginal,sizeof(SAPJBSetterOriginal))||!zeroes(cave,sizeof(SAPRestrictionTrampoline))))
        return fail(reason,"restriction_guard_mismatch");
    size_t callDelta=SAPJBKeyCallOffset-SAPJBKeyWindowOffset;
    bool keyRuntime=!memcmp(key,SAPJBKeyPatched,sizeof(SAPJBKeyPatched));
    bool keyTraced=!memcmp(key,SAPJBKeyOriginal,callDelta)&&
        !memcmp(image+SAPJBKeyCallOffset,SAPTraceRequestHead,4)&&
        !memcmp(key+callDelta+4,SAPJBKeyOriginal+callDelta+4,sizeof(SAPJBKeyOriginal)-callDelta-4);
    bool keyStaticZero=!memcmp(key,SAPJBKeyStaticZero,sizeof(SAPJBKeyStaticZero));
    uint8_t *oldModeCave=image+SAPKeyModeCaveOffset;
    if((!keyRuntime&&!keyTraced&&!keyStaticZero&&memcmp(key,SAPJBKeyOriginal,sizeof(SAPJBKeyOriginal)))||
       memcmp(image+SAPJBProviderOffset,SAPJBProviderOriginal,sizeof(SAPJBProviderOriginal))||
       memcmp(image+SAPJBMappingOffset,SAPJBMappingOriginal,sizeof(SAPJBMappingOriginal))||
       memcmp(image+SAPJBDLSymStubOffset,SAPJBDLSymStubOriginal,sizeof(SAPJBDLSymStubOriginal))||
       (keyRuntime?memcmp(oldModeCave,SAPKeyModeTrampoline,sizeof(SAPKeyModeTrampoline)):
        (!zeroes(oldModeCave,sizeof(SAPKeyModeTrampoline))&&memcmp(oldModeCave,SAPKeyModeTrampoline,sizeof(SAPKeyModeTrampoline)))))
        return fail(reason,"key_requester_mismatch");
    if(keyTraced?memcmp(image+SAPTraceRequestCaveOffset,SAPTraceRequestCode,sizeof(SAPTraceRequestCode)):
                 !zeroes(image+SAPTraceRequestCaveOffset,sizeof(SAPTraceRequestCode)))
        return fail(reason,"request_observer_mismatch");
    const struct {size_t entry,cave,length;const uint8_t *original,*head,*code;} callbacks[]={
        {SAPTraceSuccessOffset,SAPTraceSuccessCaveOffset,sizeof(SAPTraceSuccessCode),SAPJBSuccessOriginal,SAPTraceSuccessHead,SAPTraceSuccessCode},
        {SAPTraceFailureOffset,SAPTraceFailureCaveOffset,sizeof(SAPTraceFailureCode),SAPJBFailureOriginal,SAPTraceFailureHead,SAPTraceFailureCode}};
    for(size_t i=0;i<2;i++) {
        const uint8_t *entry=image+callbacks[i].entry,*body=image+callbacks[i].cave;
        bool installed=!memcmp(entry,callbacks[i].head,4)&&!memcmp(entry+4,callbacks[i].original+4,12)&&!memcmp(body,callbacks[i].code,callbacks[i].length);
        if(!installed&&(memcmp(entry,callbacks[i].original,16)||!zeroes(body,callbacks[i].length)))return fail(reason,"callback_observer_mismatch");
    }
    // Publish complete trampoline bodies before redirecting any native entry.
    struct Change {size_t offset,length;const uint8_t *bytes;uint8_t old[512];} changes[]={
        {SAPRestrictionCaveOffset,sizeof(SAPRestrictionTrampoline),SAPRestrictionTrampoline,{0}},
        {SAPTraceRequestCaveOffset,sizeof(SAPTraceRequestCode),SAPTraceRequestCode,{0}},
        {SAPTraceSuccessCaveOffset,sizeof(SAPTraceSuccessCode),SAPTraceSuccessCode,{0}},
        {SAPTraceFailureCaveOffset,sizeof(SAPTraceFailureCode),SAPTraceFailureCode,{0}},
        {SAPJBSetterOffset,4,SAPGuardedSetterHead,{0}},
        {SAPJBKeyCallOffset,4,SAPTraceRequestHead,{0}},
        {SAPTraceSuccessOffset,4,SAPTraceSuccessHead,{0}},
        {SAPTraceFailureOffset,4,SAPTraceFailureHead,{0}}};
    unsigned touched[8],count=0;
    for(unsigned i=0;i<8;i++) {
        if(!memcmp(image+changes[i].offset,changes[i].bytes,changes[i].length))continue;
        if(!writer)return fail(reason,"no_memory_writer");
        memcpy(changes[i].old,image+changes[i].offset,changes[i].length);touched[count++]=i;
        writer(image+changes[i].offset,changes[i].bytes,changes[i].length,context);
        if(memcmp(image+changes[i].offset,changes[i].bytes,changes[i].length))goto rollback;
    }
    if(reason)*reason=count?"applied":"already_applied";
    return true;
rollback:
    for(unsigned n=count;n>0;n--) {
        unsigned i=touched[n-1];writer(image+changes[i].offset,changes[i].old,changes[i].length,context);
    }
    for(unsigned n=0;n<count;n++) {
        unsigned i=touched[n];if(memcmp(image+changes[i].offset,changes[i].old,changes[i].length))return fail(reason,"memory_write_failed_rollback_incomplete");
    }
    return fail(reason,"memory_write_failed");
}
