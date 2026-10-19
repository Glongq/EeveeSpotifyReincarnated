#include "AudioProbeBackend.h"
#include "CaptureRing.h"
#include "Diagnostics.h"
#include "Features.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
_Static_assert(!SAP_ENABLE_WAV_CAPTURE,"release-only test");
static AURenderCallbackStruct installed;
static AudioStreamBasicDescription format={48000,kAudioFormatLinearPCM,kAudioFormatFlagIsFloat|kAudioFormatFlagIsPacked,8,1,8,2,32,0};
static OSStatus set(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,const void *v,UInt32 n) {
 if(p==kAudioUnitProperty_SetRenderCallback)installed=*(const AURenderCallbackStruct *)v;return noErr;
}
static OSStatus get(AudioUnit u,AudioUnitPropertyID p,AudioUnitScope s,AudioUnitElement e,void *v,UInt32 *n) {
 if(p==kAudioUnitProperty_StreamFormat){memcpy(v,&format,sizeof(format));*n=sizeof(format);return noErr;}return kAudioUnitErr_InvalidProperty;
}
static OSStatus unitOp(AudioUnit u){return noErr;}
static OSStatus describe(AudioUnit u,AudioComponentDescription *d){d->componentType=kAudioUnitType_Output;return noErr;}
static OSStatus render(void *ctx,AudioUnitRenderActionFlags *flags,const AudioTimeStamp *t,UInt32 bus,UInt32 frames,AudioBufferList *data){
 float *samples=data->mBuffers[0].mData;for(unsigned i=0;i<2*frames;i++)samples[i]=0.5f;return noErr;
}
static unsigned observed;
static void observer(const AudioStreamBasicDescription *f,AudioBufferList *data,UInt32 frames){observed++;((float *)data->mBuffers[0].mData)[0]=0.25f;}
static void rejectedCapture(void){
 SAPCaptureFormat result;memset(&result,0xff,sizeof(result));
 assert(!SpotifyAudioProbeBeginCapture(&result));assert(!result.sampleRate&&!result.channels);
 assert(!SpotifyAudioProbeBeginCapture(NULL));assert(!SAPCaptureStart((void *)1,&format));
 char bytes[32];memset(bytes,0x55,sizeof(bytes));
 assert(!SpotifyAudioProbeReadCapture(bytes,sizeof(bytes)));for(unsigned i=0;i<sizeof(bytes);i++)assert(bytes[i]==0x55);
 SAPCapturePush((void *)1,&format,NULL,UINT32_MAX);SpotifyAudioProbeEndCapture();
 assert(!SAPCaptureActive()&&!SpotifyAudioProbeDroppedCaptureFrames()&&!SpotifyAudioProbeCaptureFormatChanged());
}
int main(void){
 SAPTestUseBackend((SAPBackend){set,get,unitOp,unitOp,unitOp,describe});
 AudioUnit unit=(AudioUnit)(uintptr_t)1;AURenderCallbackStruct callback={render,NULL};
 assert(!AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof(callback)));
 assert(!AudioOutputUnitStart(unit));
 float samples[256];AudioBufferList data={.mNumberBuffers=1,.mBuffers={{2,sizeof(samples),samples}}};AudioUnitRenderActionFlags flags=0;AudioTimeStamp time={0};
 for(unsigned enabled=0;enabled<2;enabled++){
  SAPDiagnosticsSetEnabled(enabled);SAPSnapshot before,after;SpotifyAudioProbeReadSnapshot(&before);
  rejectedCapture();assert(!installed.inputProc(installed.inputProcRefCon,&flags,&time,0,128,&data));
  for(unsigned i=0;i<256;i++)assert(samples[i]==0.5f);
  SpotifyAudioProbeReadSnapshot(&after);assert(after.callbacks==before.callbacks+enabled);
  assert(SpotifyAudioProbeMuteForSeconds(2));installed.inputProc(installed.inputProcRefCon,&flags,&time,0,128,&data);
  for(unsigned i=0;i<256;i++)assert(samples[i]==0);assert(SpotifyAudioProbeMuteForSeconds(0));
  SpotifyAudioProbeSetObserver(observer);installed.inputProc(installed.inputProcRefCon,&flags,&time,0,128,&data);
  assert(samples[0]==0.25f&&observed==enabled+1);SpotifyAudioProbeSetObserver(NULL);rejectedCapture();
 }
 puts("PASS: release WAV APIs reject capture and leave buffers untouched; playback, diagnostics OFF/ON, observer and manual mute remain functional");
}
