#import "Diagnostics.h"
#include <stdatomic.h>

NSNotificationName const SAPDiagnosticsDidChangeNotification=@"SAPDiagnosticsDidChange";
static NSString *const preferenceKey=@"SAPDiagnosticsEnabled";
static atomic_bool enabled;

bool SAPDiagnosticsEnabled(void) {return atomic_load_explicit(&enabled,memory_order_relaxed);}
void SAPDiagnosticsInitialize(void) {
    static dispatch_once_t once;
    dispatch_once(&once,^{atomic_store(&enabled,[NSUserDefaults.standardUserDefaults boolForKey:preferenceKey]);});
}
void SAPDiagnosticsSetEnabled(bool value) {
    SAPDiagnosticsInitialize();
    if(atomic_exchange(&enabled,value)==value)return;
    [NSUserDefaults.standardUserDefaults setBool:value forKey:preferenceKey];
    [NSNotificationCenter.defaultCenter postNotificationName:SAPDiagnosticsDidChangeNotification object:nil];
}
