#include "CaptureRing.h"
#include "Features.h"
#include <sched.h>
#include <stdatomic.h>
#include <string.h>

#if SAP_ENABLE_WAV_CAPTURE
// 1 MiB, allocated statically; about 2.7 seconds of stereo Float32 at 48 kHz.
#define SAMPLE_CAPACITY (262144u)
static float samples[SAMPLE_CAPACITY];
static atomic_uint_fast64_t writeIndex, readIndex, dropped;
static atomic_uint producerCount;
static atomic_bool capturing, changed;
static atomic_flag producerBusy = ATOMIC_FLAG_INIT;
static _Atomic(const void *) selectedToken;
static AudioStreamBasicDescription captureFormat;
#endif

bool SAPFormatSupported(const AudioStreamBasicDescription *format) {
    if (!format || format->mFormatID != kAudioFormatLinearPCM || !format->mBytesPerFrame
        || !format->mChannelsPerFrame || format->mChannelsPerFrame > 32 || format->mSampleRate <= 0
        || (format->mFormatFlags & kAudioFormatFlagIsBigEndian)
        || !(format->mFormatFlags & kAudioFormatFlagIsPacked)) return false;
    bool floating = format->mFormatFlags & kAudioFormatFlagIsFloat;
    bool integer = format->mFormatFlags & kAudioFormatFlagIsSignedInteger;
    unsigned bits = format->mBitsPerChannel;
    if (!((floating && bits == 32) || (integer && (bits == 16 || bits == 32)))) return false;
    unsigned channels = (format->mFormatFlags & kAudioFormatFlagIsNonInterleaved) ? 1 : format->mChannelsPerFrame;
    return (uint64_t)channels * (bits / 8) == format->mBytesPerFrame;
}

#if SAP_ENABLE_WAV_CAPTURE
SAP_EXPORT void SpotifyAudioProbeEndCapture(void) {
    atomic_store_explicit(&capturing, false, memory_order_seq_cst);
    // This is a control/writer-thread API; never call it from the PCM observer.
    while (atomic_load_explicit(&producerCount, memory_order_seq_cst)) sched_yield();
}

bool SAPCaptureStart(const void *token, const AudioStreamBasicDescription *format) {
    if (!token || !SAPFormatSupported(format)) return false;
    SpotifyAudioProbeEndCapture();
    captureFormat = *format;
    atomic_store(&writeIndex, 0); atomic_store(&readIndex, 0);
    atomic_store(&dropped, 0); atomic_store(&changed, false);
    atomic_store(&selectedToken, token);
    atomic_store_explicit(&capturing, true, memory_order_seq_cst);
    return true;
}

static float sample(const void *data, uint64_t index, const AudioStreamBasicDescription *format) {
    if (format->mFormatFlags & kAudioFormatFlagIsFloat) {
        float value; memcpy(&value, (const char *)data + index * 4, 4); return value;
    }
    if (format->mBitsPerChannel == 16) {
        int16_t value; memcpy(&value, (const char *)data + index * 2, 2); return (float)value / 32768.0f;
    }
    int32_t value; memcpy(&value, (const char *)data + index * 4, 4); return (float)((double)value / 2147483648.0);
}

void SAPCapturePush(const void *token, const AudioStreamBasicDescription *format,
                    const AudioBufferList *data, UInt32 frames) {
    if (!atomic_load_explicit(&capturing, memory_order_seq_cst)) return;
    atomic_fetch_add_explicit(&producerCount, 1, memory_order_seq_cst);
    if (!atomic_load_explicit(&capturing, memory_order_seq_cst)) goto done;
    if (atomic_load(&selectedToken) != token) goto done;
    if (memcmp(format, &captureFormat, sizeof(*format)) != 0) {
        atomic_store(&changed, true);
        atomic_fetch_add(&dropped, frames);
        goto done;
    }
    // Never wait on an audio producer. Report a whole dropped block instead.
    if (atomic_flag_test_and_set_explicit(&producerBusy, memory_order_acquire)) {
        atomic_fetch_add(&dropped, frames); goto done;
    }
    unsigned channels = format->mChannelsPerFrame;
    bool planar = format->mFormatFlags & kAudioFormatFlagIsNonInterleaved;
    unsigned buffers = planar ? channels : 1;
    if (data->mNumberBuffers < buffers) { atomic_fetch_add(&dropped, frames); goto unlock; }
    for (unsigned b = 0; b < buffers; ++b) {
        if (!data->mBuffers[b].mData || data->mBuffers[b].mDataByteSize < (uint64_t)frames * format->mBytesPerFrame) {
            atomic_fetch_add(&dropped, frames); goto unlock;
        }
    }
    uint64_t count = (uint64_t)frames * channels;
    uint64_t write = atomic_load_explicit(&writeIndex, memory_order_relaxed);
    uint64_t read = atomic_load_explicit(&readIndex, memory_order_acquire);
    if (count > SAMPLE_CAPACITY - (write - read)) { atomic_fetch_add(&dropped, frames); goto unlock; }
    for (UInt32 frame = 0; frame < frames; ++frame) {
        for (unsigned channel = 0; channel < channels; ++channel) {
            const void *source = data->mBuffers[planar ? channel : 0].mData;
            uint64_t offset = planar ? frame : (uint64_t)frame * channels + channel;
            samples[(write + (uint64_t)frame * channels + channel) % SAMPLE_CAPACITY] = sample(source, offset, format);
        }
    }
    atomic_store_explicit(&writeIndex, write + count, memory_order_release);
unlock:
    atomic_flag_clear_explicit(&producerBusy, memory_order_release);
done:
    atomic_fetch_sub_explicit(&producerCount, 1, memory_order_seq_cst);
}

SAP_EXPORT size_t SpotifyAudioProbeReadCapture(void *destination, size_t capacity) {
    if (!destination) return 0;
    uint64_t read = atomic_load_explicit(&readIndex, memory_order_relaxed);
    uint64_t write = atomic_load_explicit(&writeIndex, memory_order_acquire);
    size_t count = (size_t)(write - read);
    if (count > capacity / sizeof(float)) count = capacity / sizeof(float);
    size_t offset = (size_t)(read % SAMPLE_CAPACITY);
    size_t first = count < SAMPLE_CAPACITY - offset ? count : SAMPLE_CAPACITY - offset;
    memcpy(destination, &samples[offset], first * sizeof(float));
    if (first < count) memcpy((char *)destination + first * sizeof(float), samples, (count - first) * sizeof(float));
    atomic_store_explicit(&readIndex, read + count, memory_order_release);
    return count * sizeof(float);
}

bool SAPCaptureActive(void) {return atomic_load_explicit(&capturing,memory_order_relaxed);}
SAP_EXPORT uint64_t SpotifyAudioProbeDroppedCaptureFrames(void) { return atomic_load(&dropped); }
SAP_EXPORT bool SpotifyAudioProbeCaptureFormatChanged(void) { return atomic_load(&changed); }
#else
SAP_EXPORT void SpotifyAudioProbeEndCapture(void) {}
bool SAPCaptureStart(const void *token,const AudioStreamBasicDescription *format) {return false;}
void SAPCapturePush(const void *token,const AudioStreamBasicDescription *format,const AudioBufferList *data,UInt32 frames) {}
SAP_EXPORT size_t SpotifyAudioProbeReadCapture(void *destination,size_t capacity) {return 0;}
bool SAPCaptureActive(void) {return false;}
SAP_EXPORT uint64_t SpotifyAudioProbeDroppedCaptureFrames(void) {return 0;}
SAP_EXPORT bool SpotifyAudioProbeCaptureFormatChanged(void) {return false;}
#endif
