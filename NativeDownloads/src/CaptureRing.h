#pragma once
#include "AudioProbe.h"
bool SAPCaptureActive(void);

bool SAPCaptureStart(const void *token, const AudioStreamBasicDescription *format);
void SAPCapturePush(const void *token, const AudioStreamBasicDescription *format,
                    const AudioBufferList *data, UInt32 frames);
bool SAPFormatSupported(const AudioStreamBasicDescription *format);
