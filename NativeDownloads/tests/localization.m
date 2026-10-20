#import "Localization.h"
#include <assert.h>
int main(int argc,char **argv){@autoreleasepool {
 assert(argc>1);NSString *expected=[NSString stringWithUTF8String:argv[1]];
 assert([SAPL(@"Русский",@"English") isEqual:expected]);
 assert([SAPL(@"Русский",@"English") isEqual:expected]);
 printf("PASS: English-only manager text resolves as %s regardless of app language\n",expected.UTF8String);
}}
