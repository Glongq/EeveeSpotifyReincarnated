// Loaded as Vitrine's dependency, before Vitrine installs its own audio hooks.
// DEB only: the IPA continues to use its existing on-disk patches/imports.
#import <Foundation/Foundation.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <CydiaSubstrate/CydiaSubstrate.h>
#import "JailbreakPatches.h"
#import "JailbreakSupport.h"
#include <string.h>
extern bool SAPInstallJailbreakAudioImports(void);
static NSDictionary *startupReport;
NSDictionary *SAPJailbreakSupportReport(void) {
    return startupReport?:@{@"attempted":@NO,@"native_patches_ready":@NO,@"audio_imports_ready":@NO};
}
static bool publish(bool nativeReady,bool audioReady,const char *reason) {
    startupReport=@{@"attempted":@YES,@"native_patches_ready":@(nativeReady),@"audio_imports_ready":@(audioReady),
        @"reason":@(reason?:"unknown"),@"supported_spotify_version":@"9.1.90",@"detected_spotify_version":[NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"]?:@"unknown",
        @"menu_requires_native_patches":@NO,@"audio_required_for_downloads":@NO};
    return nativeReady;
}
static void writeCode(void *target,const void *bytes,size_t length,void *context) {
    MSHookMemory(target,bytes,length);
}
bool SAPInstallJailbreakSupport(void) {
    const struct mach_header_64 *header=(const void *)_dyld_get_image_header(0);
    if(!header||header->magic!=MH_MAGIC_64||header->sizeofcmds>1048576||header->ncmds>1024)return publish(false,false,"invalid_main_image");
    const uint8_t *cursor=(const void *)(header+1),*end=cursor+header->sizeofcmds;
    size_t textSize=0;
    for(uint32_t i=0;i<header->ncmds;i++) {
        if(cursor>end||(size_t)(end-cursor)<sizeof(struct load_command))return publish(false,false,"invalid_load_commands");
        const struct load_command *command=(const void *)cursor;
        if(command->cmdsize<sizeof(*command)||command->cmdsize>(size_t)(end-cursor))return publish(false,false,"invalid_load_command_size");
        if(command->cmd==LC_SEGMENT_64&&command->cmdsize>=sizeof(struct segment_command_64)) {
            const struct segment_command_64 *segment=(const void *)command;
            if(!strncmp(segment->segname,"__TEXT",16))textSize=segment->filesize;
        }
        cursor+=command->cmdsize;
    }
    const char *reason=NULL;
    if(!SAPJBApplyPatches((void *)header,textSize,writeCode,NULL,&reason)) {
        return publish(false,false,reason?:"native_patches_refused");
    }
    bool audioReady=SAPInstallJailbreakAudioImports();
    return publish(true,audioReady,audioReady?reason:"native_ready_audio_imports_unavailable");
}
