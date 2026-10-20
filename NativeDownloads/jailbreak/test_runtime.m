// Execute the production adapter against a synthetic mapped ARM64 image.
#define SAP_JB_TEST 1
#import "Runtime.m"
#import <sys/mman.h>
#import <assert.h>
const struct mach_header_64 *JBTestHeader;
static unsigned writes, failWrite;
BOOL JBTestWrite(void *p,const void *data,size_t size) {
    writes++;
    if(writes==failWrite) { // Simulate a partially completed engine write.
        memcpy(p,data,size/2); return NO;
    }
    memcpy(p,data,size); return YES;
}
static uint8_t *fixture(void) {
    size_t n=JB_MappingOffset+4096;
    uint8_t *p=mmap(NULL,n,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
    assert(p!=MAP_FAILED);
    struct mach_header_64 *h=(void *)p;
    h->magic=MH_MAGIC_64;h->cputype=CPU_TYPE_ARM64;h->ncmds=2;
    h->sizeofcmds=sizeof(struct uuid_command)+sizeof(struct segment_command_64)+sizeof(struct section_64);
    struct uuid_command *u=(void *)(h+1);u->cmd=LC_UUID;u->cmdsize=sizeof(*u);memcpy(u->uuid,JB_UUID,16);
    struct segment_command_64 *s=(void *)(u+1);s->cmd=LC_SEGMENT_64;s->cmdsize=sizeof(*s)+sizeof(struct section_64);
    strcpy(s->segname,"__TEXT");s->vmaddr=0x100000000;s->filesize=n;s->vmsize=n;s->initprot=5;s->nsects=1;
    struct section_64 *section=(void *)(s+1);section->addr=s->vmaddr+0x24000;section->size=n-0x24000;
    memcpy(p+JB_SetterOffset,JB_SetterOriginal,sizeof(JB_SetterOriginal));
    memcpy(p+JB_KeyWindowOffset,JB_KeyOriginal,sizeof(JB_KeyOriginal));
    memcpy(p+JB_ProviderOffset,JB_Provider,sizeof(JB_Provider));
    memcpy(p+JB_MappingOffset,JB_Mapping,sizeof(JB_Mapping));
    JBTestHeader=(void *)p; writes=0;failWrite=0;return p;
}
static void releaseImage(uint8_t *p) {munmap(p,JB_MappingOffset+4096);}
int main(void) {
    uint8_t *p=fixture();assert(install());assert(writes==3);
    assert(!memcmp(p+JB_KeyCallOffset,JB_KeyPatched,4));
    assert(!memcmp(p+JB_CaveOffset,JB_Trampoline,sizeof(JB_Trampoline)));
    assert(install());assert(writes==3);releaseImage(p);
    const size_t corrupt[]={sizeof(struct mach_header_64)+8,JB_SetterOffset,JB_CaveOffset,JB_KeyWindowOffset,JB_ProviderOffset,JB_MappingOffset};
    for(unsigned i=0;i<sizeof(corrupt)/sizeof(*corrupt);i++) {
        p=fixture();p[corrupt[i]]^=0x80;assert(!install());assert(writes==0);releaseImage(p);
    }
    for(unsigned failure=1;failure<=3;failure++) {
        p=fixture();failWrite=failure;assert(!install());
        assert(!memcmp(p+JB_SetterOffset,JB_SetterOriginal,sizeof(JB_SetterOriginal)));
        assert(!memcmp(p+JB_KeyWindowOffset,JB_KeyOriginal,sizeof(JB_KeyOriginal)));
        uint8_t zero[sizeof(JB_Trampoline)]={0};assert(!memcmp(p+JB_CaveOffset,zero,sizeof(zero)));
        releaseImage(p);
    }
    puts("PASS: v7 guards, idempotency, incompatible images, and partial-write rollback");
}
