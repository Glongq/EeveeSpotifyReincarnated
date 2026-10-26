#import <UIKit/UIKit.h>
// The action-row layout fixture has no Spotify collection-state provider.
// Follow semantics are exercised on-device; this adapter only declares absence.
NSInteger EeveePixieArtistFollowing(UIView *header,void (^changed)(void)){return -1;}
void EeveePixieInstallArtistFollow(void){}
