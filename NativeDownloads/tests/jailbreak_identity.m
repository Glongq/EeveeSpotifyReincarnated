#import "../jailbreak/JailbreakIdentity.h"
#include <assert.h>

typedef struct { struct mach_header_64 header; struct uuid_command uuid; } Image;
static bool readImage(void *context, uintptr_t offset, void *out, size_t size) {
    if (offset > sizeof(Image) || size > sizeof(Image)-offset) return false;
    memcpy(out, (uint8_t *)context+offset, size); return true;
}
int main(void) { @autoreleasepool {
    Image image = {.header={.magic=MH_MAGIC_64,.cputype=CPU_TYPE_ARM64,.filetype=MH_EXECUTE,
        .ncmds=1,.sizeofcmds=sizeof(struct uuid_command)},.uuid={.cmd=LC_UUID,.cmdsize=sizeof(struct uuid_command)}};
    for (unsigned i=0;i<16;i++) image.uuid.uuid[i]=(uint8_t)i;
    NSString *uuid=@"000102030405060708090a0b0c0d0e0f";
    NSDictionary *loaded=SAPJBImageIdentity(&image,readImage);
    assert([loaded[@"uuid"] isEqual:uuid]);
    for (id build in @[@"920002054",@920002054,@"repackaged",NSNull.null]) {
        NSDictionary *info=@{@"CFBundleShortVersionString":@"9.2.0",@"CFBundleVersion":build};
        assert(!SAPJBIdentityFailure(@"com.spotify.client",info,loaded,@"9.2.0",uuid));
    }
    assert([SAPJBMetadataString(@920002054) isEqual:@"920002054"]);
    assert([SAPJBIdentityFailure(@"other",@{},loaded,@"9.2.0",uuid) isEqual:@"bundle_identifier_mismatch"]);
    assert([SAPJBIdentityFailure(@"com.spotify.client",@{},loaded,@"9.2.0",uuid) isEqual:@"spotify_version_mismatch"]);
    NSDictionary *info=@{@"CFBundleShortVersionString":@"9.2.0"};
    assert([SAPJBIdentityFailure(@"com.spotify.client",info,loaded,@"9.2.0",@"different") isEqual:@"spotify_uuid_mismatch"]);
    image.header.filetype=MH_DYLIB;
    assert([SAPJBImageIdentity(&image,readImage)[@"status"] isEqual:@"not_arm64_executable"]);
    image.header.filetype=MH_EXECUTE;image.header.sizeofcmds=8;
    assert([SAPJBImageIdentity(&image,readImage)[@"status"] isEqual:@"invalid_load_commands"]);
    image.header.sizeofcmds=sizeof(image.uuid);image.uuid.cmd=LC_SOURCE_VERSION;
    assert([SAPJBImageIdentity(&image,readImage)[@"status"] isEqual:@"uuid_missing"]);
    image.uuid.cmd=LC_UUID;image.uuid.cmdsize=8;
    assert([SAPJBImageIdentity(&image,readImage)[@"status"] isEqual:@"uuid_unreadable"]);
    image.header.ncmds=1025;
    assert([SAPJBImageIdentity(&image,readImage)[@"status"] isEqual:@"invalid_load_commands"]);
    puts("Jailbreak binary identity, metadata and malformed-image tests passed");
} }
