#import <UIKit/UIKit.h>
#import "AudioProbeUI.h"
@implementation SAPSettingsActions
+ (NSDictionary *)snapshot {
 return @{@"report":@{},@"diagnostics":@"v22 · библиотека готова\nPCM получен\n\nCallback: 8169 · Кадров: 7685396\nPCM: 61483168 байт\n48000 Hz · 2 ch · 32 bit · lpcm\nИсточник: Spotify\nВыход: AirPods Pro 3\nОшибок: 0",@"journal_summary":@"Скачано: 118\nВ очереди: 0\nОшибок: 0\n\nВсе загрузки завершены.",@"download_active":@NO,@"recording":@NO,@"last_wav_available":@YES};
}
+ (NSDictionary *)snapshotForDetails:(BOOL)journal {return [self snapshot];}
+ (void)loadDetails:(BOOL)journal completion:(void (^)(NSDictionary *))completion {dispatch_async(dispatch_get_main_queue(),^{completion([self snapshot]);});}
+ (void)perform:(SAPSettingsAction)action { }
@end

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
