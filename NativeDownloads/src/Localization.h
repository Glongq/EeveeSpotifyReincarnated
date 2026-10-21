#pragma once
#import <Foundation/Foundation.h>

// Pixie uses English regardless of Spotify's or iOS's selected language.
// Discard the legacy translation before compilation, including its string data.
#define SAPL(legacyTranslation, english) (english)
#define SAPManagerName @"Pixie Download Manager"
#define SAPManagerVersion @"1"
