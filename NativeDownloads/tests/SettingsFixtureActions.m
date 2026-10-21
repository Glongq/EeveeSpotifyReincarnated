#import <UIKit/UIKit.h>
#import "AudioProbeUI.h"
static void (^slotPreview)(NSDictionary *,NSString *);
static void (^slotRelease)(NSDictionary *,NSString *);
static NSUInteger slotReleaseCalls;
void SAPFixtureCompleteSlotPreview(BOOL success) {
 void (^done)(NSDictionary *,NSString *)=slotPreview;slotPreview=nil;NSCAssert(done,@"No pending preview");
 NSDictionary *device=@{@"name":@"Fixture phone",@"cache_id":@"fixture-cache-123",@"device_id":@"fixture-device-123"};
 done(success?@{@"id":@"fixture-plan",@"free_licenses":@4,@"max_licenses":@5,@"active_devices":@[device]}:nil,success?nil:@"fixture: registration check failed");
}
void SAPFixtureCompleteSlotRelease(BOOL success) {
 void (^done)(NSDictionary *,NSString *)=slotRelease;slotRelease=nil;NSCAssert(done,@"No pending release");
 done(success?@{@"free_licenses":@5,@"max_licenses":@5}:nil,success?nil:@"fixture: release not confirmed");
}
NSUInteger SAPFixtureSlotReleaseCalls(void) {return slotReleaseCalls;}
@implementation SAPSettingsActions
+ (NSDictionary *)snapshot {
 return @{@"report":@{},@"diagnostics":@"Audio diagnostics disabled",@"journal_summary":@"Downloaded: 118\nWaiting: 0\nErrors: 0",@"download_active":@NO,@"recording":@NO,@"last_wav_available":@NO,@"key_request_mode":@{@"selected_mode":@0,@"configured_mode":@0,@"last_selector_returned_mode":@(-1),@"runtime_selection_supported":@NO,@"configuration_source":@"verified_static_trace_argument",@"restart_required":@NO,@"detail":@"Mode 0 is verified in this Spotify 9.1.88 executable. Download authorization is checked separately."}};
}
+ (NSDictionary *)snapshotForDetails:(BOOL)journal {return [self snapshot];}
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion {dispatch_async(dispatch_get_main_queue(),^{completion([self snapshot]);});}
+ (void)perform:(SAPSettingsAction)action { }
+ (void)setKeyRequestMode:(NSInteger)mode completion:(void (^)(BOOL,NSString *))completion {NSCAssert(mode==0,@"Selecting mode 1 must not be offered");if(completion)completion(NO,@"Spotify reports 0 free device-license slots. Mode was not changed.");}
+ (void)refreshDownloadCompatibility:(void (^)(NSDictionary *))completion {if(completion)completion(@{@"status":@"complete"});}
+ (void)previewOfflineDeviceSlots:(void (^)(NSDictionary *,NSString *))completion {NSCAssert(!slotPreview,@"Duplicate preview");slotPreview=[completion copy];}
+ (void)releaseOfflineDeviceSlots:(NSString *)planID cacheIDs:(NSArray *)cacheIDs completion:(void (^)(NSDictionary *,NSString *))completion {NSCAssert([planID isEqual:@"fixture-plan"]&&[cacheIDs isEqual:@[@"fixture-cache-123"]],@"Unreviewed release");slotReleaseCalls++;slotRelease=[completion copy];}
+ (void)enableOfflineOnCurrentDevice:(void (^)(NSDictionary *,NSString *))completion {completion(nil,@"fixture: no mutation performed");}
@end
void SAPJournalNoteAction(NSString *name,NSDictionary *facts) {}
NSString *SAPDownloadCompatibilityText(NSDictionary *report) {return @"Device licenses: 0 of 5 free. Mode was not changed.";}

// SAPFixtureChrome: stand-in for Spotify's existing mini-player controller.
@interface _TtC18NowPlaying_BarImpl27NowPlayingBarViewController : UIViewController @end
@implementation _TtC18NowPlaying_BarImpl27NowPlayingBarViewController
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithRed:0.22 green:0.08 blue:0.15 alpha:1];self.view.layer.cornerRadius=8;
 UILabel *label=[UILabel new];label.text=@"   Текущий трек · мини-плеер                 ▶";label.textColor=UIColor.whiteColor;
 label.frame=CGRectMake(0,0,430,56);label.autoresizingMask=UIViewAutoresizingFlexibleWidth;[self.view addSubview:label];
}
@end

@protocol SPTPageController <NSObject>
- (NSString *)spt_pageIdentifier;
- (NSURL *)spt_pageURI;
@end
@protocol _TtP19Tome_PageAttributes17SPTPageController_ <NSObject>
- (NSString *)spt_pageIdentifier;
- (NSURL *)spt_pageURI;
@end
__attribute__((constructor)) static void SAPFixtureRegisterProtocols(void) {
 (void)[NSObject conformsToProtocol:@protocol(SPTPageController)];
 (void)[NSObject conformsToProtocol:@protocol(_TtP19Tome_PageAttributes17SPTPageController_)];
}
