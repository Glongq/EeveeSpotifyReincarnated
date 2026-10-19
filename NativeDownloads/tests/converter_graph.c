#include "Diagnostics.h"
#include "AudioProbe.h"
#include <assert.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static int16_t inputPCM[16384];
static OSStatus source(void *refcon, AudioUnitRenderActionFlags *flags,
                       const AudioTimeStamp *time, UInt32 bus, UInt32 frames, AudioBufferList *data) {
    assert(refcon == (void *)(uintptr_t)91 && bus == 0 && frames <= 8192);
    assert(data && data->mNumberBuffers == 1);
    for (UInt32 i = 0; i < frames * 2; ++i) inputPCM[i] = 8192;
    data->mBuffers[0] = (AudioBuffer){2, frames * 4, inputPCM};
    return noErr;
}
static AudioUnit create(OSType type, OSType subtype) {
    AudioComponentDescription description = {type, subtype, kAudioUnitManufacturer_Apple, 0, 0};
    AudioComponent component = AudioComponentFindNext(NULL, &description);
    AudioUnit unit = NULL;
    assert(component && AudioComponentInstanceNew(component, &unit) == noErr);
    return unit;
}
static void format(AudioUnit unit, AudioUnitScope scope, AudioStreamBasicDescription *asbd) {
    assert(AudioUnitSetProperty(unit, kAudioUnitProperty_StreamFormat, scope, 0, asbd, sizeof(*asbd)) == noErr);
}
int main(void) {
    void (*enableDiagnostics)(bool)=dlsym(RTLD_DEFAULT,"SAPDiagnosticsSetEnabled");
    if(enableDiagnostics)enableDiagnostics(true);

    AudioUnit converter = create(kAudioUnitType_FormatConverter, kAudioUnitSubType_AUConverter);
    AudioUnit output = create(kAudioUnitType_Output, kAudioUnitSubType_GenericOutput);
    AudioStreamBasicDescription in = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked, 4, 1, 4, 2, 16, 0};
    AudioStreamBasicDescription out = {48000, kAudioFormatLinearPCM, kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked, 8, 1, 8, 2, 32, 0};
    // Match the report: the callback belongs to 'aufc', not to the output unit.
    AURenderCallbackStruct callback = {source, (void *)(uintptr_t)91};
    assert(AudioUnitSetProperty(converter, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &callback, sizeof(callback)) == noErr);
    format(converter, kAudioUnitScope_Input, &in);
    format(converter, kAudioUnitScope_Output, &out);
    format(output, kAudioUnitScope_Input, &out);
    format(output, kAudioUnitScope_Output, &out);
    AudioUnitConnection connection = {converter, 0, 0};
    assert(AudioUnitSetProperty(output, kAudioUnitProperty_MakeConnection, kAudioUnitScope_Input, 0, &connection, sizeof(connection)) == noErr);
    assert(AudioUnitInitialize(converter) == noErr && AudioUnitInitialize(output) == noErr);
    void (*snapshotFn)(SAPSnapshot *) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeReadSnapshot");
    bool (*muteFn)(double) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeMuteForSeconds");
    bool (*captureFn)(SAPCaptureFormat *) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeBeginCapture");
    void (*endFn)(void) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeEndCapture");
    size_t (*readFn)(void *, size_t) = dlsym(RTLD_DEFAULT, "SpotifyAudioProbeReadCapture");
    assert(snapshotFn && muteFn && captureFn && endFn && readFn);
    // Keep all five redirected symbols in this executable.
    AudioStreamBasicDescription query; UInt32 size = sizeof(query);
    assert(AudioUnitGetProperty(converter, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &query, &size) == noErr);
    if (getenv("SAP_TEST_START_HARDWARE")) { AudioOutputUnitStart(output); AudioOutputUnitStop(output); }
    float samples[256];
    AudioBufferList data = {.mNumberBuffers = 1, .mBuffers = {{2, sizeof(samples), samples}}};
    AudioUnitRenderActionFlags flags = 0;
    AudioTimeStamp time = {.mSampleTime = 0, .mFlags = kAudioTimeStampSampleTimeValid};
    assert(AudioUnitRender(output, &flags, &time, 0, 128, &data) == noErr);
    for (unsigned i = 0; i < 256; ++i) assert(samples[i] == 0.25f);
    SAPSnapshot s; snapshotFn(&s);
    fprintf(stderr, "Converter graph: attempts=%u type=0x%x registrations=%u callbacks=%llu bytes=%llu\n", s.callbackAttempts, s.lastComponentType, s.registrations, s.callbacks, s.pcmBytes);
    assert(s.registrations == 1 && s.pcmConfirmed && s.callbacks > 0 && s.pcmBytes > 0);
    assert(s.lastComponentType == kAudioUnitType_FormatConverter && s.bitsPerChannel == 16 && s.sampleRate == 48000);
    assert(muteFn(2));
    time.mSampleTime += 128; flags = 0;
    assert(AudioUnitRender(output, &flags, &time, 0, 128, &data) == noErr);
    for (unsigned i = 0; i < 256; ++i) assert(samples[i] == 0);
    assert(muteFn(0));
    SAPCaptureFormat capture; assert(captureFn(&capture));
    time.mSampleTime += 128; flags = 0;
    assert(AudioUnitRender(output, &flags, &time, 0, 128, &data) == noErr);
    endFn();
    float recorded[256]; assert(readFn(recorded, sizeof(recorded)) == sizeof(recorded));
    for (unsigned i = 0; i < 256; ++i) assert(recorded[i] == 0.25f && samples[i] == 0.25f);
    AudioUnitUninitialize(output); AudioUnitUninitialize(converter);
    assert(AudioComponentInstanceDispose(output) == noErr && AudioComponentInstanceDispose(converter) == noErr);
    puts("PASS: real AUConverter -> GenericOutput graph, input int16 -> output float32; original audio, converter callback interception, mute at output and capture samples verified");
}
