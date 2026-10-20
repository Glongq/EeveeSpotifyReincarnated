#import "Localization.h"
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import "AudioProbeUI.h"
#import "Diagnostics.h"
#include <math.h>

static NSString *const SAPUIChanged=@"SAPDownloadSettingsChanged";
static const void *SAPAttachmentKey=&SAPAttachmentKey;
static void *SAPContentSizeContext=&SAPContentSizeContext;
static void (*originalSettingsLoad)(id,SEL);
static void (*originalSettingsLayout)(id,SEL);

// Resolve Spotify's bottom chrome once per page. Layout callbacks only read
// the cached views' current geometry; there is no timer or playback hook.
@interface SAPBottomChrome : NSObject
@property(nonatomic,weak) UIWindow *window;
@property(nonatomic,strong) NSHashTable<UIView *> *views;
- (CGFloat)coveredBottomOfScroll:(UIScrollView *)scroll;
@end
@implementation SAPBottomChrome
- (void)collect:(UIViewController *)controller depth:(unsigned)depth {
    if(depth>20 || !controller)return;
    NSString *name=NSStringFromClass(controller.class);
    if([name isEqual:@"NowPlaying_BarImpl.NowPlayingBarContainerViewController"] ||
       [name isEqual:@"NowPlaying_BarImpl.NowPlayingBarViewController"] ||
       [name isEqual:@"_TtC18NowPlaying_BarImpl36NowPlayingBarContainerViewController"] ||
       [name isEqual:@"_TtC18NowPlaying_BarImpl27NowPlayingBarViewController"])
        if(controller.isViewLoaded)[self.views addObject:controller.view];
    if([controller isKindOfClass:UITabBarController.class])
        [self.views addObject:((UITabBarController *)controller).tabBar];
    if([name isEqual:@"NavigationUI_TabBarImpl.TabBarContainerImpl"] ||
       [name isEqual:@"_TtC23NavigationUI_TabBarImpl19TabBarContainerImpl"]) {
        SEL selector=NSSelectorFromString(@"tabBarView");
        if([controller respondsToSelector:selector]) {
            id bar=((id(*)(id,SEL))objc_msgSend)(controller,selector);
            if([bar isKindOfClass:UIView.class])[self.views addObject:bar];
        }
    }
    for(UIViewController *child in controller.childViewControllers)[self collect:child depth:depth+1];
}
- (CGFloat)coveredBottomOfScroll:(UIScrollView *)scroll {
    UIWindow *window=scroll.window;if(!window)return 0;
    if(self.window!=window) {
        self.window=window;self.views=[NSHashTable weakObjectsHashTable];
        [self collect:window.rootViewController depth:0];
    }
    CGRect viewport=[scroll convertRect:scroll.bounds toView:window];
    CGFloat top=CGRectGetMaxY(window.bounds)-window.safeAreaInsets.bottom;
    for(UIView *view in self.views) {
        BOOL visible=view.window==window;
        for(UIView *parent=view;visible && parent;parent=parent.superview)
            if(parent.hidden || parent.alpha<0.01)visible=NO;
        if(!visible)continue;
        CGRect rect=[view convertRect:view.bounds toView:window];
        if(rect.size.width<viewport.size.width*0.5 || rect.size.height<=0 ||
           rect.size.height>window.bounds.size.height*0.45 ||
           CGRectGetMinY(rect)<CGRectGetMidY(window.bounds) ||
           !CGRectIntersectsRect(viewport,rect))continue;
        top=MIN(top,CGRectGetMinY(rect));
    }
    return MAX(0,CGRectGetMaxY(viewport)-top);
}
@end

static CGFloat SAPBottomInset(UIScrollView *scroll,SAPBottomChrome *chrome,CGFloat base) {
    CGFloat automatic=scroll.adjustedContentInset.bottom-scroll.contentInset.bottom;
    return MAX(base,[chrome coveredBottomOfScroll:scroll]+12-automatic);
}

static UIImage *SAPSettingsIcon(NSString *symbol,UIColor *color,UITraitCollection *traits) {
    static NSCache *cache;static dispatch_once_t once;
    dispatch_once(&once,^{cache=[NSCache new];cache.countLimit=64;});
    UIColor *resolved=[color resolvedColorWithTraitCollection:traits];
    NSString *key=[NSString stringWithFormat:@"%@|%@|%ld|%.2f",symbol,resolved,(long)traits.accessibilityContrast,traits.displayScale];
    UIImage *cached=[cache objectForKey:key];if(cached)return cached;
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat preferredFormat];if(traits.displayScale>0)format.scale=traits.displayScale;
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc]initWithSize:CGSizeMake(30,30) format:format];
    UIImage *result=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){
        UIBezierPath *shape=[UIBezierPath bezierPathWithRoundedRect:CGRectMake(0,0,30,30) cornerRadius:8];
        CGContextSaveGState(context.CGContext);[shape addClip];
        NSArray *colors=@[(id)[resolved colorWithAlphaComponent:0.85].CGColor,(id)resolved.CGColor];
        CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
        CGGradientRef gradient=CGGradientCreateWithColors(space,(__bridge CFArrayRef)colors,NULL);
        CGContextDrawLinearGradient(context.CGContext,gradient,CGPointZero,CGPointMake(0,30),0);
        CGGradientRelease(gradient);CGColorSpaceRelease(space);CGContextRestoreGState(context.CGContext);
        UIImage *icon=[[UIImage systemImageNamed:symbol withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold]]imageWithTintColor:UIColor.whiteColor renderingMode:UIImageRenderingModeAlwaysOriginal];
        CGSize size=icon.size;[icon drawInRect:CGRectMake((30-size.width)/2,(30-size.height)/2,size.width,size.height)];
    }];
    [cache setObject:result forKey:key];return result;
}
static UITableViewCell *SAPSettingsCell(UITableView *table,NSString *title,NSString *subtitle,NSString *symbol,UIColor *color,BOOL chevron) {
    UITableViewCell *cell=[table dequeueReusableCellWithIdentifier:@"SAPSettingsRow"];
    if(!cell){cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"SAPSettingsRow"];
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:64].active=YES;}
    UIListContentConfiguration *content=[UIListContentConfiguration subtitleCellConfiguration];
    content.text=title;content.secondaryText=subtitle;content.image=SAPSettingsIcon(symbol,color,table.traitCollection);
    content.textProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleBody];
    content.textProperties.color=UIColor.labelColor;content.textProperties.numberOfLines=0;
    content.secondaryTextProperties.font=[UIFont preferredFontForTextStyle:UIFontTextStyleFootnote];
    content.secondaryTextProperties.color=UIColor.secondaryLabelColor;content.secondaryTextProperties.numberOfLines=0;
    content.imageToTextPadding=14;content.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(12,20,12,20);
    content.imageProperties.reservedLayoutSize=CGSizeMake(30,30);
    cell.contentConfiguration=content;cell.accessoryType=chevron?UITableViewCellAccessoryDisclosureIndicator:UITableViewCellAccessoryNone;
    cell.accessoryView=nil;
    cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;cell.accessibilityLabel=title;
    return cell;
}

@interface SAPSettingsTable : UITableViewController
@property(nonatomic,strong) NSDictionary *snapshot;
@property(nonatomic,strong) id changeObserver;
@property(nonatomic,strong) SAPBottomChrome *bottomChrome;
@property(nonatomic) CGFloat baseBottom,appliedBottom;
- (void)refresh;
@end
@implementation SAPSettingsTable
- (instancetype)init {return [super initWithStyle:UITableViewStyleInsetGrouped];}
- (void)viewDidLoad {
    [super viewDidLoad];self.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
    self.tableView.backgroundColor=UIColor.blackColor;self.tableView.rowHeight=UITableViewAutomaticDimension;
    self.tableView.estimatedRowHeight=70;self.tableView.separatorInset=UIEdgeInsetsMake(0,64,0,20);
    self.bottomChrome=[SAPBottomChrome new];
    self.baseBottom=self.appliedBottom=self.tableView.contentInset.bottom;
    self.navigationItem.rightBarButtonItem=[[UIBarButtonItem alloc]initWithImage:[UIImage systemImageNamed:@"arrow.clockwise"] style:UIBarButtonItemStylePlain target:self action:@selector(refresh)];
}
- (void)viewDidLayoutSubviews {[super viewDidLayoutSubviews];[self updateBottomInset];}
- (void)viewSafeAreaInsetsDidChange {[super viewSafeAreaInsetsDidChange];[self updateBottomInset];}
- (void)updateBottomInset {
    if(!self.tableView.window)return;
    UIEdgeInsets inset=self.tableView.contentInset;
    if(fabs(inset.bottom-self.appliedBottom)>0.5)self.baseBottom=inset.bottom;
    self.appliedBottom=SAPBottomInset(self.tableView,self.bottomChrome,self.baseBottom);
    if(fabs(inset.bottom-self.appliedBottom)>0.5) {
        inset.bottom=self.appliedBottom;self.tableView.contentInset=inset;
    }
    UIEdgeInsets indicator=self.tableView.verticalScrollIndicatorInsets;
    indicator.bottom=self.appliedBottom;if(!UIEdgeInsetsEqualToEdgeInsets(indicator,self.tableView.verticalScrollIndicatorInsets))self.tableView.verticalScrollIndicatorInsets=indicator;
}
- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];[self refresh];
    __weak typeof(self) weak=self;
    self.changeObserver=[NSNotificationCenter.defaultCenter addObserverForName:SAPUIChanged object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *note){[weak refresh];}];
}
- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];if(self.changeObserver)[NSNotificationCenter.defaultCenter removeObserver:self.changeObserver];self.changeObserver=nil;
}
- (void)dealloc {if(_changeObserver)[NSNotificationCenter.defaultCenter removeObserver:_changeObserver];}
- (void)refresh {self.snapshot=[SAPSettingsActions snapshot];[self.tableView reloadData];}
- (BOOL)conformsToProtocol:(Protocol *)protocol {
    // Match Eevee's SPTPageViewController: Spotify also asks for the Swift
    // protocol _TtP19Tome_PageAttributes17SPTPageController_, whose displayed
    // name includes its module. Checking only the legacy short name crashes
    // SPNavigationController when it revalidates the current page.
    if([NSStringFromProtocol(protocol)containsString:@"SPTPageController"])return YES;
    return [super conformsToProtocol:protocol];
}
- (NSString *)spt_pageIdentifier {return @"EeveeSpotify";}
- (NSURL *)spt_pageURI {return [NSURL URLWithString:@""];}
- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header=(id)view;
        header.textLabel.text=[self tableView:table titleForHeaderInSection:section];
        header.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];header.textLabel.textColor=UIColor.secondaryLabelColor;
    }
}
@end

@interface SAPDetailsSettings : SAPSettingsTable
@property(nonatomic) BOOL journal;
@property(nonatomic) NSUInteger detailsGeneration;
@end
@implementation SAPDetailsSettings
- (void)viewDidLoad {[super viewDidLoad];self.title=self.journal?SAPL(@"Состояние загрузок",@"Download status"):SAPL(@"Диагностика аудио",@"Audio diagnostics");}
- (void)refresh {
    if(self.journal && SAPDiagnosticsEnabled())[SAPSettingsActions perform:SAPSettingsRefreshJournal];
    [self fetchDetails];NSUInteger expected=self.detailsGeneration;__weak typeof(self) weak=self;
    if(self.journal && SAPDiagnosticsEnabled())dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1200*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        if(weak.detailsGeneration==expected && weak.view.window && SAPDiagnosticsEnabled())[weak fetchDetails];
    });
}
- (void)fetchDetails {
    NSUInteger expected=++self.detailsGeneration;__weak typeof(self) weak=self;
    if(!self.snapshot){NSMutableDictionary *loading=[[SAPSettingsActions snapshot]mutableCopy];loading[@"journal_summary"]=loading[@"diagnostics"]=SAPL(@"Обновление…",@"Updating…");self.snapshot=loading;[self.tableView reloadData];}
    [SAPSettingsActions loadDetails:self.journal completion:^(NSDictionary *value){
        if(weak.detailsGeneration!=expected)return;weak.snapshot=value;[weak.tableView reloadData];
    }];
}
- (void)viewWillDisappear:(BOOL)animated {self.detailsGeneration++;[super viewWillDisappear:animated];}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 2;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return section==0?1:(self.journal?3:2);}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return section==0?SAPL(@"Текущее состояние",@"Current status"):SAPL(@"Действия",@"Actions");}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    if(index.section==0) {
        UITableViewCell *cell=[[UITableViewCell alloc]initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        UIListContentConfiguration *content=[UIListContentConfiguration cellConfiguration];
        content.text=self.snapshot[self.journal?@"journal_summary":@"diagnostics"]?:SAPL(@"Нет данных",@"No data");
        content.textProperties.font=[UIFont monospacedSystemFontOfSize:13 weight:UIFontWeightRegular];
        content.textProperties.numberOfLines=0;content.textProperties.color=UIColor.labelColor;
        content.directionalLayoutMargins=NSDirectionalEdgeInsetsMake(16,20,16,20);cell.contentConfiguration=content;
        cell.backgroundColor=UIColor.secondarySystemGroupedBackgroundColor;cell.selectionStyle=UITableViewCellSelectionStyleNone;return cell;
    }
    NSArray *titles=self.journal?@[SAPL(@"Обновить состояние",@"Refresh status"),SAPL(@"Экспорт журнала",@"Export download log"),SAPL(@"Сбросить журнал",@"Reset download log")]:@[SAPL(@"Обновить состояние",@"Refresh status"),SAPL(@"Экспорт отчёта",@"Export report")];
    NSArray *symbols=self.journal?@[@"arrow.clockwise",@"square.and.arrow.up",@"trash.fill"]:@[@"arrow.clockwise",@"square.and.arrow.up"];
    return SAPSettingsCell(table,titles[index.row],nil,symbols[index.row],index.row==2?UIColor.systemRedColor:UIColor.systemBlueColor,NO);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];if(index.section==0)return;
    if(index.row==0) {
        [self refresh];
    }else if(self.journal && index.row==2) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:SAPL(@"Сбросить журнал?",@"Reset download log?") message:SAPL(@"Будет очищена история диагностики загрузок.",@"This will clear the download diagnostic history.") preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"Отмена",@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"Сбросить",@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action){[SAPSettingsActions perform:SAPSettingsResetJournal];[self fetchDetails];}]];
        [self presentViewController:confirm animated:YES completion:nil];
    }else [SAPSettingsActions perform:self.journal?SAPSettingsExportJournal:SAPSettingsExportReport];
}
@end

@interface SAPDownloadsSettings : SAPSettingsTable @end
@implementation SAPDownloadsSettings
- (void)viewDidLoad {[super viewDidLoad];self.title=SAPManagerName;}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 3;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {
    if(section==0)return [self.snapshot[@"download_active"]boolValue]?3:2;
    if(section==1)return 3;
    return 3;
}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {
    return @[SAPL(@"Загрузка",@"Download"),SAPL(@"Журнал загрузок",@"Download log"),SAPL(@"Диагностика",@"Diagnostics")][section];
}
- (NSString *)tableView:(UITableView *)table titleForFooterInSection:(NSInteger)section {
    if(section==0)return SAPL(@"Треки сохраняются в Spotify для прослушивания без интернета.",@"Tracks are saved in Spotify for offline listening.");
    if(section==2)return [NSString stringWithFormat:@"Enable to collect logs and detailed reports. Downloading and checking the current track also work with diagnostics off.\n\n%@ · Version %@",SAPManagerName,SAPManagerVersion];
    return nil;
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    NSString *title,*subtitle=nil,*symbol;UIColor *color;BOOL chevron=NO;
    if(index.section==0) {
        NSArray *titles=@[[self.snapshot[@"download_active"]boolValue]?SAPL(@"Статус скачивания трека",@"Track download status"):SAPL(@"Скачать текущий трек",@"Download current track"),SAPL(@"Проверить текущий трек",@"Check current track"),SAPL(@"Отменить скачивание",@"Cancel download")];
        title=titles[index.row];symbol=@[@"arrow.down.circle.fill",@"checkmark.circle.fill",@"xmark.circle.fill"][index.row];
        color=index.row==2?UIColor.systemOrangeColor:UIColor.systemGreenColor;
    }else if(index.section==1) {
        title=@[SAPL(@"Состояние загрузок",@"Download status"),SAPL(@"Экспорт журнала",@"Export download log"),SAPL(@"Сбросить журнал",@"Reset download log")][index.row];
        symbol=@[@"chart.bar.fill",@"square.and.arrow.up",@"trash.fill"][index.row];color=index.row==2?UIColor.systemGrayColor:UIColor.systemBlueColor;chevron=index.row==0;
    }else {
        title=@[SAPL(@"Диагностика",@"Diagnostics"),SAPL(@"Диагностика аудио",@"Audio diagnostics"),SAPL(@"Экспорт отчёта",@"Export report")][index.row];
        symbol=@[@"slider.horizontal.3",@"waveform.path.ecg",@"square.and.arrow.up"][index.row];color=UIColor.systemTealColor;chevron=index.row==1;
    }
    UITableViewCell *cell=SAPSettingsCell(table,title,subtitle,symbol,color,chevron);
    if(index.section==2 && index.row==0) {
        UISwitch *toggle=[UISwitch new];toggle.on=SAPDiagnosticsEnabled();
        toggle.accessibilityLabel=SAPL(@"Диагностика",@"Diagnostics");toggle.accessibilityIdentifier=@"SpotifyDiagnosticsSwitch";
        [toggle addTarget:self action:@selector(diagnosticsChanged:) forControlEvents:UIControlEventValueChanged];cell.accessoryView=toggle;
    }
    return cell;
}
- (void)diagnosticsChanged:(UISwitch *)toggle {SAPDiagnosticsSetEnabled(toggle.on);[self refresh];}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    if(index.section==2 && index.row==0){SAPDiagnosticsSetEnabled(!SAPDiagnosticsEnabled());[self refresh];return;}
    if((index.section==1 && index.row==0) || (index.section==2 && index.row==1)) {
        SAPDetailsSettings *page=[SAPDetailsSettings new];page.journal=index.section==1;
        [self.navigationController pushViewController:page animated:YES];return;
    }
    SAPSettingsAction action;
    if(index.section==0)action=index.row==0?SAPSettingsDownload:(index.row==1?SAPSettingsVerify:SAPSettingsCancelDownload);
    else if(index.section==1)action=index.row==1?SAPSettingsExportJournal:SAPSettingsResetJournal;
    else action=SAPSettingsExportReport;
    if(action==SAPSettingsResetJournal) {
        UIAlertController *confirm=[UIAlertController alertControllerWithTitle:SAPL(@"Сбросить журнал?",@"Reset download log?") message:SAPL(@"Будет очищена история диагностики загрузок.",@"This will clear the download diagnostic history.") preferredStyle:UIAlertControllerStyleAlert];
        [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"Отмена",@"Cancel") style:UIAlertActionStyleCancel handler:nil]];
        [confirm addAction:[UIAlertAction actionWithTitle:SAPL(@"Сбросить",@"Reset") style:UIAlertActionStyleDestructive handler:^(UIAlertAction *a){[SAPSettingsActions perform:action];[self refresh];}]];
        [self presentViewController:confirm animated:YES completion:nil];return;
    }
    [SAPSettingsActions perform:action];
    if(action==SAPSettingsCancelDownload)[self refresh];
}
@end

// Embedded footer is a view/data source, not a child view controller. The
// existing SwiftUI hosting controller retains sole ownership of its view tree.
@interface SAPDownloadsEntry : NSObject <UITableViewDataSource,UITableViewDelegate>
@property(nonatomic,weak) UIViewController *settingsHost;
@property(nonatomic,strong) UITableView *view;
@end
@implementation SAPDownloadsEntry
- (instancetype)init {
    if((self=[super init])) {
        self.view=[[UITableView alloc]initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
        self.view.dataSource=self;self.view.delegate=self;
        self.view.overrideUserInterfaceStyle=UIUserInterfaceStyleDark;
        self.view.rowHeight=UITableViewAutomaticDimension;self.view.estimatedRowHeight=76;
        self.view.scrollEnabled=NO;self.view.contentInsetAdjustmentBehavior=UIScrollViewContentInsetAdjustmentNever;
        self.view.backgroundColor=UIColor.clearColor;self.view.accessibilityIdentifier=@"SpotifyTrackDownloadsSection";
    }
    return self;
}
- (NSInteger)numberOfSectionsInTableView:(UITableView *)table {return 1;}
- (NSInteger)tableView:(UITableView *)table numberOfRowsInSection:(NSInteger)section {return 1;}
- (NSString *)tableView:(UITableView *)table titleForHeaderInSection:(NSInteger)section {return SAPManagerName;}
- (void)tableView:(UITableView *)table willDisplayHeaderView:(UIView *)view forSection:(NSInteger)section {
    if([view isKindOfClass:UITableViewHeaderFooterView.class]) {
        UITableViewHeaderFooterView *header=(id)view;
        header.textLabel.text=SAPManagerName;
        header.textLabel.font=[UIFont preferredFontForTextStyle:UIFontTextStyleHeadline];
        header.textLabel.textColor=UIColor.secondaryLabelColor;
    }
}
- (UITableViewCell *)tableView:(UITableView *)table cellForRowAtIndexPath:(NSIndexPath *)index {
    return SAPSettingsCell(table,SAPManagerName,@"Current track and download log",@"arrow.down.circle.fill",UIColor.systemGreenColor,YES);
}
- (void)tableView:(UITableView *)table didSelectRowAtIndexPath:(NSIndexPath *)index {
    [table deselectRowAtIndexPath:index animated:YES];
    [self.settingsHost.navigationController pushViewController:[SAPDownloadsSettings new] animated:YES];
}
@end

@interface SAPSettingsAttachment : NSObject
@property(nonatomic,weak) UIViewController *host;
@property(nonatomic,weak) UIScrollView *scroll;
@property(nonatomic,strong) SAPDownloadsEntry *entry;
@property(nonatomic,strong) SAPBottomChrome *bottomChrome;
@property(nonatomic) CGFloat baseBottom,appliedBottom;
@property(nonatomic) BOOL observing,updating;
- (void)layout;
@end
@implementation SAPSettingsAttachment
- (void)dealloc {
    if(_observing && _scroll)[_scroll removeObserver:self forKeyPath:@"contentSize" context:SAPContentSizeContext];
}
- (void)layout {
    if(self.updating || !self.scroll || !self.host.view.window)return;
    self.updating=YES;
    UIScrollView *scroll=self.scroll;
    CGFloat height=[[UIFontMetrics metricsForTextStyle:UIFontTextStyleBody]scaledValueForValue:152];
    if(fabs(scroll.contentInset.bottom-self.appliedBottom)>0.5)self.baseBottom=scroll.contentInset.bottom;
    // Eevee ends its SwiftUI List with a separate, empty Spacer section.
    // Start after the final real footer, before that reserved blank space.
    CGFloat start=scroll.contentSize.height;
    if([scroll isKindOfClass:UICollectionView.class]) {
        UICollectionView *list=(id)scroll;
        for(NSInteger section=list.numberOfSections-1;section>=0;section--) {
            UICollectionViewLayoutAttributes *footer=[list.collectionViewLayout layoutAttributesForSupplementaryViewOfKind:UICollectionElementKindSectionFooter atIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            if(footer && footer.frame.size.height>1){start=CGRectGetMaxY(footer.frame);break;}
        }
    }else if([scroll isKindOfClass:UITableView.class]) {
        UITableView *list=(id)scroll;
        for(NSInteger section=list.numberOfSections-1;section>=0;section--) {
            CGRect footer=[list rectForFooterInSection:section];
            if(footer.size.height>1){start=CGRectGetMaxY(footer);break;}
        }
    }
    CGRect frame=CGRectMake(0,start,scroll.bounds.size.width,height);
    if(!CGRectEqualToRect(self.entry.view.frame,frame))self.entry.view.frame=frame;
    if(self.entry.view.superview!=scroll)[scroll addSubview:self.entry.view];
    if(scroll.subviews.lastObject!=self.entry.view)[scroll bringSubviewToFront:self.entry.view];
    CGFloat extension=MAX(0,start+height-scroll.contentSize.height);
    UIEdgeInsets inset=scroll.contentInset;
    self.appliedBottom=SAPBottomInset(scroll,self.bottomChrome,self.baseBottom)+extension;
    if(fabs(inset.bottom-self.appliedBottom)>0.5){inset.bottom=self.appliedBottom;scroll.contentInset=inset;}
    UIEdgeInsets indicator=scroll.verticalScrollIndicatorInsets;
    indicator.bottom=MAX(self.baseBottom,self.appliedBottom-extension);
    if(!UIEdgeInsetsEqualToEdgeInsets(indicator,scroll.verticalScrollIndicatorInsets))scroll.verticalScrollIndicatorInsets=indicator;
    self.updating=NO;
}
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context {
    if(context!=SAPContentSizeContext){[super observeValueForKeyPath:keyPath ofObject:object change:change context:context];return;}
    if(NSThread.isMainThread)[self layout];else dispatch_async(dispatch_get_main_queue(),^{[self layout];});
}
@end
static UIScrollView *SAPSettingsList(UIView *root,CGFloat width,unsigned depth) {
    if(depth>12)return nil;
    if([root isKindOfClass:UIScrollView.class] && root.bounds.size.width>width*0.65 &&
        ([root isKindOfClass:UITableView.class] || [root isKindOfClass:UICollectionView.class]))return (id)root;
    for(UIView *view in root.subviews){UIScrollView *found=SAPSettingsList(view,width,depth+1);if(found)return found;}
    return nil;
}
static void SAPAttachSettings(UIViewController *host) {
    if(![host.title isEqual:@"EeveeSpotify"])return;
    SAPSettingsAttachment *attachment=objc_getAssociatedObject(host,SAPAttachmentKey);
    if(attachment){[attachment layout];return;}
    UIScrollView *list=SAPSettingsList(host.view,host.view.bounds.size.width,0);if(!list)return;
    attachment=[SAPSettingsAttachment new];attachment.host=host;attachment.scroll=list;
    attachment.bottomChrome=[SAPBottomChrome new];
    attachment.baseBottom=list.contentInset.bottom;attachment.appliedBottom=list.contentInset.bottom;
    SAPDownloadsEntry *entry=[SAPDownloadsEntry new];entry.settingsHost=host;attachment.entry=entry;
    [list addSubview:entry.view];
    objc_setAssociatedObject(host,SAPAttachmentKey,attachment,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [list addObserver:attachment forKeyPath:@"contentSize" options:NSKeyValueObservingOptionNew context:SAPContentSizeContext];attachment.observing=YES;
    [attachment layout];
}
static void SAPSettingsLoaded(id self,SEL selector) {originalSettingsLoad(self,selector);SAPAttachSettings(self);}
static void SAPSettingsLayout(id self,SEL selector) {originalSettingsLayout(self,selector);SAPAttachSettings(self);}
void SAPInstallDownloadSettings(void) {
    static dispatch_once_t once;dispatch_once(&once,^{
        #ifdef SAP_UI_FIXTURE
        Class cls=NSClassFromString(@"SAPFixtureEeveeSettingsViewController");
#else
        Class cls=NSClassFromString(@"EeveeSpotify.EeveeSettingsViewController");
#endif
        if(!cls)cls=NSClassFromString(@"_TtC12EeveeSpotify27EeveeSettingsViewController");
        if(!cls)return;
        SEL load=@selector(viewDidLoad),layout=@selector(viewDidLayoutSubviews);
        Method lm=class_getInstanceMethod(cls,load),dm=class_getInstanceMethod(cls,layout);
        if(!lm || !dm || method_getNumberOfArguments(lm)!=2 || method_getNumberOfArguments(dm)!=2)return;
        originalSettingsLoad=(void *)method_getImplementation(lm);originalSettingsLayout=(void *)method_getImplementation(dm);
        // Add overrides only to Eevee's existing controller; inherited UIKit methods are not changed.
        class_replaceMethod(cls,load,(IMP)SAPSettingsLoaded,method_getTypeEncoding(lm));
        class_replaceMethod(cls,layout,(IMP)SAPSettingsLayout,method_getTypeEncoding(dm));
    });
}
