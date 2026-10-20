// Reuse the real AudioUnit fixture after runtime (not on-disk) import rebinding.
#define main OfflineFixtureMain
#include "../tests/offline_unit.c"
#undef main
int main(int argc,char **argv) {
    assert(argc==2);
    void *library=dlopen(argv[1],RTLD_NOW|RTLD_GLOBAL);
    if(!library) {fprintf(stderr,"%s\n",dlerror());return 1;}
    void (*installImports)(void)=dlsym(library,"SAPJBTestInstallImports");
    assert(installImports);installImports();
    OfflineFixtureMain();
    puts("PASS: main-image runtime rebinding forwards real AudioToolbox calls without recursion");
    return 0;
}
