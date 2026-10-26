#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AudioProbeUI.h"
#include <assert.h>

id SGPageRow(NSString *title,UIViewController *(^page)(void)) {return @{@"title":title,@"page":[page copy]};}
id SGActionRow(NSString *title,NSString *subtitle,void (^action)(void)) {return @{@"title":title,@"action":[action copy]};}
id SGWithTile(id row,NSString *symbol,UIColor *color) {return row;}
id SGSection(NSString *title,NSArray *rows) {return @{@"rows":rows};}

@interface FixtureVitrinePage:UITableViewController
@property(nonatomic,strong) NSArray *groups;
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer;
@end
@implementation FixtureVitrinePage
- (instancetype)initWithTitle:(NSString *)title intro:(NSString *)intro sections:(NSArray *)sections footer:(NSString *)footer {
    if((self=[super initWithStyle:UITableViewStyleInsetGrouped])){self.title=title;self.groups=sections;}return self;
}
@end

@interface VitrineFixtureScene:UIResponder<UIWindowSceneDelegate>
@property(nonatomic,strong) UIWindow *window;
@end
@implementation VitrineFixtureScene
- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)options {
    // The first attempt deliberately precedes both host classes becoming available.
    SAPInstallDownloadSettings();assert(![SAPDownloadSettingsInstallReport()[@"installed"]boolValue]);
    Class old=objc_allocateClassPair(UIViewController.class,"SAPFixtureEeveeSettingsViewController",0);objc_registerClassPair(old);
    Class cls=objc_allocateClassPair(FixtureVitrinePage.class,"SGModPage",0);objc_registerClassPair(cls);
    SAPInstallDownloadSettings();assert([SAPDownloadSettingsInstallReport()[@"status"]isEqual:@"vitrine_page_hook_installed"]);
    FixtureVitrinePage *root=((id(*)(id,SEL,id,id,id,id))objc_msgSend)([cls alloc],@selector(initWithTitle:intro:sections:footer:),@"Vitrine",nil,@[],nil);
    assert(root.groups.count==1&&[root.groups[0][@"rows"]count]==2);
    NSArray *rows=root.groups[0][@"rows"];assert([rows[0][@"title"]isEqual:@"Pixie Download Manager"]&&[rows[1][@"title"]isEqual:@"Send log"]);
    SAPInstallDownloadSettings();
    FixtureVitrinePage *again=((id(*)(id,SEL,id,id,id,id))objc_msgSend)([cls alloc],@selector(initWithTitle:intro:sections:footer:),@"Vitrine",nil,@[],nil);
    assert(again.groups.count==1); // Reinstallation must not duplicate rows.
    self.window=[[UIWindow alloc]initWithWindowScene:(UIWindowScene *)scene];
    UINavigationController *navigation=[[UINavigationController alloc]initWithRootViewController:root];self.window.rootViewController=navigation;[self.window makeKeyAndVisible];
    UIViewController *(^factory)(void)=rows[0][@"page"];UITableViewController *page=(id)factory();[navigation pushViewController:page animated:NO];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC),dispatch_get_main_queue(),^{
        assert(page.tableView.numberOfSections==4);
        NSString *header=[page.tableView.dataSource tableView:page.tableView titleForHeaderInSection:3];assert([header isEqual:@"Me"]);
        BOOL unsupported=[NSProcessInfo.processInfo.arguments containsObject:@"--unsupported"];
        NSString *footer=[page.tableView.dataSource tableView:page.tableView titleForFooterInSection:0];
        assert([footer containsString:@"unsupported_image"]==unsupported);
        if(unsupported)assert([footer containsString:@"9.1.92"]&&[footer containsString:@"9.1.90"]);
        page.tableView.contentOffset=CGPointMake(0,MAX(0,page.tableView.contentSize.height-page.tableView.bounds.size.height+page.tableView.adjustedContentInset.bottom));
        UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithBounds:self.window.bounds];
        UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){[self.window drawViewHierarchyInRect:self.window.bounds afterScreenUpdates:YES];}];
        NSURL *folder=[NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        [UIImagePNGRepresentation(image)writeToURL:[folder URLByAppendingPathComponent:@"vitrine-pixie.png"] atomically:YES];
        [@"PASS: Vitrine priority, late host registration, idempotent menu, Send log and Me section; native refusal remains visible\n"writeToURL:[folder URLByAppendingPathComponent:@"result.log"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    });
}
@end
@interface VitrineFixtureDelegate:UIResponder<UIApplicationDelegate> @end
@implementation VitrineFixtureDelegate @end
int main(int argc,char **argv){@autoreleasepool{return UIApplicationMain(argc,argv,nil,NSStringFromClass(VitrineFixtureDelegate.class));}}
