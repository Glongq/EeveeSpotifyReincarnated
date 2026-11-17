#pragma once
#import <Foundation/Foundation.h>
#include <mach-o/loader.h>
#include "GuardedPatches.h"

static inline NSString *SAPJBMetadataString(id value) {
    if ([value isKindOfClass:NSString.class]) return value;
    if ([value isKindOfClass:NSNumber.class]) return [value stringValue];
    return @"unavailable";
}

// Inspect the loaded executable, without trusting its bundle metadata or index.
static inline NSDictionary *SAPJBImageIdentity(void *context, SAPJBRead read) {
    struct mach_header_64 header;
    if (!read(context, 0, &header, sizeof(header))) return @{@"status":@"header_unreadable"};
    if (header.magic != MH_MAGIC_64 || header.cputype != CPU_TYPE_ARM64 || header.filetype != MH_EXECUTE)
        return @{@"status":@"not_arm64_executable", @"file_type":@(header.filetype), @"cpu_type":@(header.cputype)};
    if (header.ncmds > 1024 || header.sizeofcmds > 1048576) return @{@"status":@"invalid_load_commands"};
    uintptr_t cursor = sizeof(header), end = cursor + header.sizeofcmds;
    for (unsigned i = 0; i < header.ncmds; i++) {
        struct load_command command;
        if (cursor > end || sizeof(command) > end-cursor || !read(context, cursor, &command, sizeof(command)) ||
            command.cmdsize < sizeof(command) || command.cmdsize > end-cursor)
            return @{@"status":@"invalid_load_commands"};
        if (command.cmd == LC_UUID) {
            struct uuid_command uuid;
            if (command.cmdsize < sizeof(uuid) || !read(context, cursor, &uuid, sizeof(uuid)))
                return @{@"status":@"uuid_unreadable"};
            NSMutableString *hex = [NSMutableString stringWithCapacity:32];
            for (unsigned j = 0; j < sizeof(uuid.uuid); j++) [hex appendFormat:@"%02x", uuid.uuid[j]];
            return @{@"status":@"read", @"uuid":hex, @"file_type":@(header.filetype), @"cpu_type":@(header.cputype)};
        }
        cursor += command.cmdsize;
    }
    return @{@"status":@"uuid_missing"};
}

static inline NSString *SAPJBIdentityFailure(NSString *identifier, NSDictionary *info,
                                            NSDictionary *loaded, NSString *version, NSString *uuid) {
    if (![identifier isEqual:@"com.spotify.client"]) return @"bundle_identifier_mismatch";
    if (![SAPJBMetadataString(info[@"CFBundleShortVersionString"]) isEqual:version]) return @"spotify_version_mismatch";
    if (![loaded[@"status"] isEqual:@"read"]) return loaded[@"status"] ?: @"executable_unavailable";
    if (![loaded[@"uuid"] isEqual:uuid]) return @"spotify_uuid_mismatch";
    // CFBundleVersion can change during repackaging. The exact executable UUID
    // AND every guarded native byte still have to match before any write.
    return nil;
}
