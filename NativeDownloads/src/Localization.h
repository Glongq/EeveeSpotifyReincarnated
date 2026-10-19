#pragma once
#import <Foundation/Foundation.h>

// Follows the app's preferred language (including the iOS per-app language).
// Evaluated once per process, never from the real-time audio callback.
NSString *SAPL(NSString *russian,NSString *english);
