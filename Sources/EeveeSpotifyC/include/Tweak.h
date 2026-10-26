#import <UIKit/UIKit.h>

#ifdef __cplusplus
extern "C" {
#endif

NS_ASSUME_NONNULL_BEGIN

void EeveeSBInvokeSeekDouble(id target, SEL selector, double argument);
NSString *EeveeJBRootPath(NSString *path);
BOOL EeveeSetMainInfoValue(NSString *key, id value);
UIImage *_Nullable EeveeRenderTemplate(UIView *view);
UIImage *_Nullable EeveeEncoreIconImage(UIView *iconView, BOOL active);
BOOL EeveeFireTap(UIView *root);
int EeveeInstallColorSwaps(BOOL amoled, NSInteger accentRGB);
void EeveeColorSwapStats(long *grey, long *green, long *uiColor);
// Defined only in the opt-in jailbreak build; Swift calls it under that flag.
BOOL EeveeNativeDownloadsIsReady(void);
BOOL EeveeNativeDownloadsWillHandleDownloads(void);
BOOL EeveePinSetter(id object, SEL setter, id value);
BOOL EeveeInterceptBackground(UIView *view, void (^sink)(UIColor *color));

void EeveePixieUpdateArtistDownloads(UIView *header, UIButton *_Nullable externalButton);

NSString *_Nullable EeveePixieArtistURIForHeader(UIView *header);
void EeveePixieInstallArtistFollow(void);
NSInteger EeveePixieArtistFollowing(UIView *header, void (^changed)(void));

NS_ASSUME_NONNULL_END

#ifdef __cplusplus
}
#endif
