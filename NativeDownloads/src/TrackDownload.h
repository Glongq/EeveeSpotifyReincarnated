#pragma once
#import <Foundation/Foundation.h>
void SAPInstallTrackDownloader(void);
void SAPDownloadCurrentTrack(void (^message)(NSString *));
void SAPCancelTrackDownload(void);
void SAPVerifyCurrentTrack(void (^message)(NSString *));
BOOL SAPTrackDownloadActive(void);
NSString *SAPTrackDownloadSummary(void);
NSDictionary *SAPTrackDownloadReport(void);
NSDictionary *SAPTrackDownloadReportWithJournal(NSDictionary *journalReport);
