#import "Localization.h"

NSString *SAPL(NSString *russian,NSString *english) {
    static BOOL useEnglish;static dispatch_once_t once;
    dispatch_once(&once,^{
        NSBundle *bundle=NSBundle.mainBundle;
        NSString *language=(bundle.localizations.count ? bundle.preferredLocalizations.firstObject : NSLocale.preferredLanguages.firstObject).lowercaseString;
        useEnglish=[language isEqual:@"en"] || [language hasPrefix:@"en-"];
    });
    return useEnglish?english:russian;
}
