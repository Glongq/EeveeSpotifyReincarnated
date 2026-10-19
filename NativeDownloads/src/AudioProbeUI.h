#pragma once
#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, SAPSettingsAction) {
    SAPSettingsDownload, SAPSettingsVerify, SAPSettingsCancelDownload,
    SAPSettingsRefreshJournal, SAPSettingsExportJournal, SAPSettingsResetJournal,
    SAPSettingsMute, SAPSettingsToggleRecording, SAPSettingsExportWAV, SAPSettingsExportReport
};
// UI adapters; these call the existing v21 operations without altering them.
@interface SAPSettingsActions : NSObject
+ (NSDictionary *)snapshot;
+ (NSDictionary *)snapshotForDetails:(BOOL)journal;
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion;
+ (void)perform:(SAPSettingsAction)action;
@end
void SAPInstallDownloadSettings(void);
