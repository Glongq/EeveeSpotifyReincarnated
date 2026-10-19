#include "Diagnostics.h"
#include "AudioProbe.h"
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static OSStatus source(void *refcon, AudioUnitRenderActionFlags *flags, const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    for (UInt32 b = 0; b < data->mNumberBuffers; ++b) {
        float *samples = data->mBuffers[b].mData;
        for (UInt32 i = 0; i < data->mBuffers[b].mDataByteSize / sizeof(float); ++i) samples[i] = 0.375f;
    }
    return noErr;
}
int main(void) {
    void (*enableDiagnostics)(bool)=dlsym(RTLD_DEFAULT,"SAPDiagnosticsSetEnabled");
    if(enableDiagnostics)enableDiagnostics(true);

    AudioComponentDescription description = {kAudioUnitType_Output, kAudioUnitSubType_GenericOutput, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    assert(component);
    AudioUnit unit; assert(AudioComponentInstanceNew(component, &unit) == noErr);
    AudioStreamBasicDescription format = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &format, sizeof(format)) == noErr);
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 0, &format, sizeof(format)) == noErr);
    AURenderCallbackStruct callback = {source, NULL};
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)) == noErr);
    assert(AudioUnitInitialize(unit) == noErr);
    AudioStreamBasicDescription queried; UInt32 size = sizeof(queried);
    assert(AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &queried, &size) == noErr);
    assert(queried.mSampleRate == 48000 && queried.mChannelsPerFrame == 2);
    float samples[256] = {0};
    AudioBufferList data = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(samples), samples}}};
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp time = {.mSampleTime = 0, .mFlags = kAudioTimeStampSampleTimeValid};
    assert(AudioUnitRender(unit, &flags, &time, 0, 128, &data) == noErr);
    for (unsigned i = 0; i < 256; ++i) assert(samples[i] == 0.375f);
    void (*snapshotFn)(SAPSnapshot *) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeReadSnapshot");
    bool (*muteFn)(double) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeMuteForSeconds");
    assert(snapshotFn && muteFn);
    SAPSnapshot snapshot; snapshotFn(&snapshot);
    assert(snapshot.callbacks == 1 && snapshot.frames == 128 && snapshot.pcmConfirmed);
    assert(muteFn(2));
    time.mSampleTime = 128; flags = 0;
    assert(AudioUnitRender(unit, &flags, &time, 0, 128, &data) == noErr);
    for (unsigned i = 0; i < 256; ++i) assert(samples[i] == 0);
    snapshotFn(&snapshot);
    assert(snapshot.mutedCallbacks == 1);
    if (getenv("SAP_TEST_START_HARDWARE")) { AudioOutputUnitStart(unit); AudioOutputUnitStop(unit); }
    AudioUnitUninitialize(unit);
    assert(AudioComponentInstanceDispose(unit) == noErr);
    printf("PASS: real Apple GenericOutput AU, statically redirected imports, decoded PCM, passthrough and mute; callbacks=%llu frames=%llu source=%s\n", (unsigned long long)snapshot.callbacks, (unsigned long long)snapshot.frames, snapshot.callbackImage);
}
