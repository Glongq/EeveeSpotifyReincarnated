#import "JailbreakSupport.h"
#import "TargetProfile.h"
#import "JailbreakPlan.h"
#import "ImportMemory.h"
#import "JailbreakIdentity.h"
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>

static uintptr_t image;
static void (*hookMemory)(void *, const void *, size_t);
static BOOL nativeReady;
static NSString *reason = @"not_started";
static NSMutableDictionary *details;
static NSMutableArray *writeFailures;
#define SAP_JB_COUNT(a) (sizeof(a)/sizeof((a)[0]))
static SAPJBPatch imports[SAP_JB_COUNT(SAPJBImports)];
static uintptr_t importBefore[SAP_JB_COUNT(SAPJBImports)], importAfter[SAP_JB_COUNT(SAPJBImports)];
static vm_prot_t importProtection[SAP_JB_COUNT(SAPJBImports)];
static size_t importCount;

static bool readMemory(void *context, uintptr_t offset, void *out, size_t size) {
    uintptr_t base = (uintptr_t)context;
    if (offset > UINTPTR_MAX-base || size > UINTPTR_MAX-base-offset) return false;
    vm_size_t copied = 0;
    return vm_read_overwrite(mach_task_self(), base+offset, size, (vm_address_t)out, &copied) == KERN_SUCCESS && copied == size;
}
static bool writeMemory(void *context, uintptr_t offset, const void *bytes, size_t size) {
    for (size_t i = 0; i < importCount; i++) {
        if (offset != imports[i].offset) continue;
        if (size != sizeof(uintptr_t)) return false;
        uintptr_t value;
        memcpy(&value, bytes, sizeof(value));
        return SAPJBWritePointer((uintptr_t)context+offset, value, importProtection[i]);
    }
    hookMemory((void *)((uintptr_t)context+offset), bytes, size);
    uint8_t observed[1024];
    BOOL readable = size <= sizeof(observed) && readMemory(context, offset, observed, size);
    BOOL matches = readable && !memcmp(bytes, observed, size);
    if (!matches && writeFailures.count < 16) {
        [writeFailures addObject:@{@"offset":[NSString stringWithFormat:@"0x%lx",(unsigned long)offset],
            @"size":@(size), @"readable":@(readable)}];
    }
    return matches; // MSHookMemory returns void: verify what it actually wrote.
}
// Dyld image indices are not an executable identity. Select the unique main
// MH_EXECUTE mapping, record its index and validate its actual UUID.
static NSDictionary *findExecutable(void) {
    NSMutableArray *candidates = [NSMutableArray array];
    NSDictionary *loaded = @{@"status":@"executable_unavailable"};
    for (uint32_t i = 0; i < _dyld_image_count(); i++) {
        uintptr_t base = (uintptr_t)_dyld_get_image_header(i);
        struct mach_header_64 header;
        if (!readMemory((void *)base, 0, &header, sizeof(header))) continue;
        if (i == 0) {
            details[@"dyld_image_zero"] = @{@"path":@(_dyld_get_image_name(i) ?: "unavailable"),
                @"file_type":@(header.filetype)};
        }
        if (header.magic != MH_MAGIC_64 || header.filetype != MH_EXECUTE) continue;
        NSMutableDictionary *candidate = [SAPJBImageIdentity((void *)base, readMemory) mutableCopy];
        candidate[@"dyld_index"] = @(i);
        candidate[@"path"] = @(_dyld_get_image_name(i) ?: "unavailable");
        [candidates addObject:candidate];
        image = base; loaded = candidate;
    }
    details[@"executable_candidates"] = candidates;
    if (candidates.count > 1) return @{@"status":@"multiple_executable_images"};
    return loaded;
}

static NSString *codeHex(const uint8_t *bytes, size_t size) {
    NSMutableString *value = [NSMutableString string];
    for (size_t i = 0; i < MIN(size, 16); i++) [value appendFormat:@"%02x", bytes[i]];
    return value;
}

// These are executable-code samples only, never audio keys or import pointers.
static void captureNativeChecks(void) {
    NSMutableArray *checks = [NSMutableArray array];
    for (size_t i = 0; i < SAP_JB_COUNT(SAPJBNativePatches); i++) {
        const SAPJBPatch *p = SAPJBNativePatches+i;
        uint8_t bytes[1024];
        BOOL readable = p->size <= sizeof(bytes) && readMemory((void *)image, p->offset, bytes, p->size);
        NSMutableDictionary *check = [@{@"offset":[NSString stringWithFormat:@"0x%lx",(unsigned long)p->offset],
            @"size":@(p->size), @"phase":@(p->phase), @"readable":@(readable),
            @"matches_original":@(readable && !memcmp(bytes,p->before,p->size)),
            @"matches_installed":@(readable && !memcmp(bytes,p->after,p->size)),
            @"expected_original_head":codeHex(p->before,p->size),
            @"expected_installed_head":codeHex(p->after,p->size)} mutableCopy];
        if (readable) check[@"observed_head"] = codeHex(bytes,p->size);
        [checks addObject:check];
    }
    details[@"native_checks_before_transaction"] = checks;
}

// Called by the existing AudioProbe backend setup. Stage all five rebindings
// first, preserving any previous hook; the transaction installs them together.
bool SAPJBRebindImport(const char *symbol, void *replacement, void **original) {
    void *held = NULL;
    size_t start = importCount;
    for (size_t i = 0; i < SAP_JB_COUNT(SAPJBImports); i++) {
        if (strcmp(symbol, SAPJBImports[i].symbol)) continue;
        uintptr_t pointer = 0;
        Dl_info location = {0};
        NSString *failure = nil;
        if (!readMemory((void *)image, SAPJBImports[i].offset, &pointer, sizeof(pointer))) failure = @"slot_unreadable";
        else if (!pointer) failure = @"slot_is_null";
        else if (pointer == (uintptr_t)replacement) failure = @"already_rebound";
        else if (!dladdr((void *)pointer, &location)) failure = @"provider_unresolved";
        else if (held && held != (void *)pointer) failure = @"different_previous_hooks";
        else if (importCount == SAP_JB_COUNT(imports)) failure = @"import_capacity";
        else if (!SAPJBPointerProtection(image+SAPJBImports[i].offset, importProtection+importCount)) failure = @"slot_protection_unavailable";
        if (failure) {
            details[@"import_failure"] = @{@"symbol":@(symbol), @"reason":failure,
                @"offset":[NSString stringWithFormat:@"0x%lx",(unsigned long)SAPJBImports[i].offset]};
            return false;
        }
        held = (void *)pointer;
        importBefore[importCount] = pointer;
        importAfter[importCount] = (uintptr_t)replacement;
        imports[importCount] = (SAPJBPatch){SAPJBImports[i].offset, sizeof(pointer),
            (const uint8_t *)(importBefore+importCount), (const uint8_t *)(importAfter+importCount), 2};
        importCount++;
    }
    *original = held;
    return held && importCount > start;
}

bool SAPInstallJailbreakSupport(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSBundle *host = NSBundle.mainBundle;
        NSDictionary *info = host.infoDictionary ?: @{};
        id build = info[@"CFBundleVersion"];
        details = [@{@"bootstrap_revision":@"deb-bootstrap-2",
            @"expected":@{@"bundle_identifier":@"com.spotify.client", @"version":@SAP_SPOTIFY_VERSION,
                @"build":@SAP_JB_SPOTIFY_BUILD, @"uuid":@SAP_SPOTIFY_UUID_HEX},
            @"detected":@{@"bundle_identifier":host.bundleIdentifier ?: @"unavailable",
                @"version":SAPJBMetadataString(info[@"CFBundleShortVersionString"]),
                @"build":SAPJBMetadataString(build), @"build_value_type":build ? NSStringFromClass([build class]) : @"missing"},
            @"build_metadata_matches":@([SAPJBMetadataString(build) isEqual:@SAP_JB_SPOTIFY_BUILD]),
            @"build_metadata_policy":@"informational; exact executable UUID and guarded bytes are required"} mutableCopy];
        writeFailures = [NSMutableArray array];
        NSDictionary *loaded = findExecutable();
        details[@"loaded_executable"] = loaded;
        NSString *identityFailure = SAPJBIdentityFailure(host.bundleIdentifier, info, loaded, @SAP_SPOTIFY_VERSION, @SAP_SPOTIFY_UUID_HEX);
        if (identityFailure) { reason = identityFailure; return; }
        captureNativeChecks();
        hookMemory = dlsym(RTLD_DEFAULT, "MSHookMemory");
        if (!hookMemory) { reason = @"memory_patch_backend_unavailable"; return; }
        Dl_info backend = {0};
        if (dladdr((void *)hookMemory, &backend) && backend.dli_fname) details[@"memory_patch_backend_image"] = @(backend.dli_fname);
        // Detect another Pixie companion before redirecting any native call.
        extern void SAPTraceNativeBoundary(unsigned, const uint64_t *);
        if (dlsym(RTLD_DEFAULT, "SAPTraceNativeBoundary") != (void *)SAPTraceNativeBoundary) {
            reason = @"another_pixie_companion_loaded"; return;
        }
        extern bool SAPInstallJailbreakAudioImports(void);
        if (!SAPInstallJailbreakAudioImports() || importCount != SAP_JB_COUNT(SAPJBImports)) {
            reason = @"audio_import_validation_failed"; return;
        }
        SAPJBPatch patches[SAP_JB_COUNT(SAPJBNativePatches)+SAP_JB_COUNT(SAPJBImports)];
        memcpy(patches, SAPJBNativePatches, sizeof(SAPJBNativePatches));
        memcpy(patches+SAP_JB_COUNT(SAPJBNativePatches), imports, sizeof(imports));
        details[@"prepared_import_slots"] = @(importCount);
        SAPJBResult result = SAPJBApply((void *)image, readMemory, writeMemory, patches, SAP_JB_COUNT(patches));
        NSString *states[] = {@"complete", @"already_installed", @"native_bytes_differ", @"patch_write_failed", @"patch_rollback_failed"};
        reason = states[result];
        details[@"write_verification_failures"] = writeFailures;
        nativeReady = result == SAPJBInstalled || result == SAPJBAlreadyInstalled;
    });
    return nativeReady;
}

NSDictionary *SAPJailbreakSupportReport(void) {
    NSMutableDictionary *report = [details mutableCopy] ?: [NSMutableDictionary dictionary];
    report[@"native_patches_ready"] = @(nativeReady);
    report[@"reason"] = reason;
    report[@"detected_spotify_version"] = SAPJBMetadataString(NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"]);
    report[@"supported_spotify_version"] = @SAP_SPOTIFY_VERSION;
    return report;
}
