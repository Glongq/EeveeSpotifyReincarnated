#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
typedef void (*SAPJBWrite)(void *target,const void *bytes,size_t length,void *context);
// Same instruction changes as the IPA patchers, on a verified mapped __TEXT.
bool SAPJBApplyPatches(uint8_t *image,size_t textSize,SAPJBWrite writer,void *context,const char **reason);
