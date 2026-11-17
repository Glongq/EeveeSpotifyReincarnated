#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// Payloads must exist before entry branches. Imports are installed last.
typedef struct {
    uintptr_t offset;
    size_t size;
    const uint8_t *before, *after;
    unsigned phase;
} SAPJBPatch;
typedef bool (*SAPJBRead)(void *, uintptr_t, void *, size_t);
typedef bool (*SAPJBWrite)(void *, uintptr_t, const void *, size_t);
typedef enum {
    SAPJBInstalled, SAPJBAlreadyInstalled, SAPJBConflict,
    SAPJBWriteFailed, SAPJBRollbackFailed
} SAPJBResult;

static inline bool SAPJBMatches(void *context, SAPJBRead read, const SAPJBPatch *patch, const uint8_t *bytes) {
    uint8_t buffer[1024];
    return patch->size && patch->size <= sizeof(buffer) &&
        read(context, patch->offset, buffer, patch->size) && !memcmp(buffer, bytes, patch->size);
}

static inline SAPJBResult SAPJBApply(void *context, SAPJBRead read, SAPJBWrite write,
                                   const SAPJBPatch *patches, size_t count) {
    bool original = true, installed = true;
    for (size_t i = 0; i < count; i++) {
        original &= SAPJBMatches(context, read, patches+i, patches[i].before);
        installed &= SAPJBMatches(context, read, patches+i, patches[i].after);
    }
    if (installed) return SAPJBAlreadyInstalled;
    if (!original) return SAPJBConflict; // Verify everything before the first write.
    for (unsigned phase = 0; phase < 3; phase++) {
        for (size_t i = 0; i < count; i++) {
            const SAPJBPatch *p = patches+i;
            if (p->phase != phase || !memcmp(p->before, p->after, p->size)) continue;
            if (write(context, p->offset, p->after, p->size) && SAPJBMatches(context, read, p, p->after)) continue;
            // Restore entry branches before removing any payload they could use.
            bool restored = true;
            for (int undoPhase = (int)phase; undoPhase >= 0; undoPhase--) {
                for (size_t j = count; j > 0; j--) {
                    const SAPJBPatch *q = patches+j-1;
                    if (q->phase != (unsigned)undoPhase || (undoPhase == (int)phase && j-1 > i)) continue;
                    if (SAPJBMatches(context, read, q, q->before)) continue;
                    bool wrote = write(context, q->offset, q->before, q->size);
                    restored &= wrote && SAPJBMatches(context, read, q, q->before);
                }
                // Keep payloads intact if an entry branch could not be restored.
                if (!restored) return SAPJBRollbackFailed;
            }
            return SAPJBWriteFailed;
        }
    }
    return SAPJBInstalled;
}
