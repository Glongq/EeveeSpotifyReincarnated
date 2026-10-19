#include <time.h>
#include <stdlib.h>
#include "AudioProbeBackend.h"
#include "CaptureRing.h"
#include "Diagnostics.h"

#include <assert.h>
#include <stdio.h>
#include <string.h>

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
int main(int argc,char **argv){
 SAPTestUseBackend((SAPBackend){set,get,unitOp,unitOp,unitOp,describe});
 AudioUnit unit=(AudioUnit)(uintptr_t)1;AURenderCallbackStruct callback={render,NULL};
 assert(!AudioUnitSetProperty(unit,kAudioUnitProperty_SetRenderCallback,kAudioUnitScope_Input,0,&callback,sizeof(callback)));
 assert(!AudioOutputUnitStart(unit));
 float samples[256];AudioBufferList data={.mNumberBuffers=1,.mBuffers={{2,sizeof(samples),samples}}};AudioUnitRenderActionFlags flags=0;AudioTimeStamp time={0};
 int enabled=argc>1?atoi(argv[1]):0;SAPDiagnosticsSetEnabled(enabled);
 for(unsigned i=0;i<10000;i++)installed.inputProc(installed.inputProcRefCon,&flags,&time,0,128,&data);
 struct timespec cpu0,cpu1,wall0,wall1;clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu0);clock_gettime(CLOCK_MONOTONIC,&wall0);
 const unsigned count=2000000;
 for(unsigned i=0;i<count;i++)installed.inputProc(installed.inputProcRefCon,&flags,&time,0,128,&data);
 clock_gettime(CLOCK_PROCESS_CPUTIME_ID,&cpu1);clock_gettime(CLOCK_MONOTONIC,&wall1);
 printf("{\"cpu_ns_per_buffer\":%.3f,\"wall_ns_per_buffer\":%.3f,\"frames_per_buffer\":128,\"buffers\":%u,\"diagnostics\":%d}\n",((cpu1.tv_sec-cpu0.tv_sec)*1e9+cpu1.tv_nsec-cpu0.tv_nsec)/count,((wall1.tv_sec-wall0.tv_sec)*1e9+wall1.tv_nsec-wall0.tv_nsec)/count,count,enabled);
}
