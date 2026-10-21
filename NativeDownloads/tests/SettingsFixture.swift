import UIKit
import SwiftUI

private final class ReusingSettingsTable: UITableView {
 var recycled: UITableViewCell?
 override func dequeueReusableCell(withIdentifier identifier: String) -> UITableViewCell? {
  recycled ?? super.dequeueReusableCell(withIdentifier:identifier)
 }
}

private struct LabelRow: View {
 let title: String
 let subtitle: String?
 let icon: String
 let color: Color
 var body: some View {
  HStack(spacing:14) {
   Image(systemName:icon).font(.system(size:15,weight:.semibold)).foregroundStyle(.white)
    .frame(width:30,height:30).background(RoundedRectangle(cornerRadius:8).fill(color))
   VStack(alignment:.leading,spacing:2){Text(title).foregroundStyle(.primary);if let subtitle{Text(subtitle).font(.footnote).foregroundStyle(.secondary)}}
   Spacer(minLength:8)
  }.padding(.vertical,2)
 }
}
private struct SettingsRoot: View {
 @State var logging=false
 var body: some View {
  List {
   Section {Text("Developer’s Note...").foregroundStyle(.green)}
   Section {LabelRow(title:"Поддержать проект",subtitle:"Ваш вклад помогает обновлять этот твик и…",icon:"cup.and.saucer.fill",color:.red)}
   Section(header:Text("Устранение неполадок"),footer:Text("Включите ведение журнала, затем экспортируйте или очистите журнал.")) {
    Toggle("Журнал отладки",isOn:$logging)
    LabelRow(title:"Export Debug Log",subtitle:nil,icon:"square.and.arrow.up",color:.blue)
    LabelRow(title:"Clear Debug Log",subtitle:nil,icon:"trash.fill",color:.gray)
   }
   Section(header:Text("Сброс"),footer:Text("Оба действия закроют приложение по завершении.")) {
    LabelRow(title:"Очистить данные",subtitle:"Очищает кэши",icon:"arrow.counterclockwise",color:.orange)
    LabelRow(title:"Full Reset",subtitle:"Стирает всё и выполняет выход из аккаунта",icon:"exclamationmark.triangle.fill",color:.red)
   }
   Spacer().frame(height:40).listRowBackground(Color.clear).listRowSeparator(.hidden)
  }.listStyle(.insetGrouped).tint(.green).preferredColorScheme(.dark)
 }
}
@objc(SAPFixtureEeveeSettingsViewController)
class FixtureSettings: UIViewController {
 override func viewDidLoad(){
  super.viewDidLoad();title="EeveeSpotify"
  let child=UIHostingController(rootView:AnyView(SettingsRoot()));addChild(child)
  child.view.translatesAutoresizingMaskIntoConstraints=false;view.addSubview(child.view);child.didMove(toParent:self)
  NSLayoutConstraint.activate([child.view.topAnchor.constraint(equalTo:view.topAnchor),child.view.bottomAnchor.constraint(equalTo:view.bottomAnchor),child.view.leadingAnchor.constraint(equalTo:view.leadingAnchor),child.view.trailingAnchor.constraint(equalTo:view.trailingAnchor)])
 }
}
// Mirrors the native SPNavigationController page assertion, including the
// module-qualified Objective-C protocol in Spotify 9.1.88.
class FixtureNavigation:UINavigationController {
 override func pushViewController(_ page:UIViewController,animated:Bool) {
  if ["SAPDownloadsSettings","SAPDetailsSettings"].contains(NSStringFromClass(type(of:page))) {
   for name in ["SPTPageController","_TtP19Tome_PageAttributes17SPTPageController_"] {
    guard let proto=NSProtocolFromString(name) else {preconditionFailure("missing protocol fixture")}
    precondition(page.conforms(to:proto),"native SPTPageController assertion: "+name)
   }
  }
  super.pushViewController(page,animated:animated)
 }
}
class ChromeHost:UIViewController {
 let nav:UINavigationController
 let mini=(NSClassFromString("_TtC18NowPlaying_BarImpl27NowPlayingBarViewController") as! UIViewController.Type).init()
 let bottom=UILabel()
 init(_ nav:UINavigationController){self.nav=nav;super.init(nibName:nil,bundle:nil)}
 required init?(coder:NSCoder){fatalError()}
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .black
  addChild(nav);view.addSubview(nav.view);nav.didMove(toParent:self)
  bottom.text="Главная             Поиск             Медиатека";bottom.textColor = .lightGray;bottom.backgroundColor = .black;bottom.textAlignment = .center;view.addSubview(bottom)
  addChild(mini);view.addSubview(mini.view);mini.didMove(toParent:self)
 }
 override func viewDidLayoutSubviews(){
  super.viewDidLayoutSubviews();nav.view.frame=view.bounds
  mini.view.frame=CGRect(x:8,y:view.bounds.height-146,width:view.bounds.width-16,height:56)
  bottom.frame=CGRect(x:0,y:view.bounds.height-90,width:view.bounds.width,height:90)
 }
}
@main class AppDelegate:UIResponder,UIApplicationDelegate {
 func application(_ application:UIApplication,didFinishLaunchingWithOptions opts:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {SAPInstallDownloadSettings();return true}
}
@objc(SAPFixtureSceneDelegate) class SceneDelegate:UIResponder,UIWindowSceneDelegate {
 var window:UIWindow?
 func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
  guard let windowScene=scene as? UIWindowScene else{return}
  let window=UIWindow(windowScene:windowScene);self.window=window
  let root=FixtureSettings();root.title="EeveeSpotify";let nav=FixtureNavigation(rootViewController:root)
  let chrome=ChromeHost(nav);window.rootViewController=chrome;window.overrideUserInterfaceStyle = .dark;window.makeKeyAndVisible()
  DispatchQueue.main.asyncAfter(deadline:.now()+1.5){
   let lists=root.view.subviews.flatMap{self.descendants($0)}.compactMap{$0 as? UIScrollView}
   guard let list=lists.first(where:{$0 is UICollectionView}),let entry=lists.first(where:{$0.accessibilityIdentifier=="SpotifyTrackDownloadsSection"}) as? UITableView else {self.write("NO_ENTRY");return}
   list.setContentOffset(CGPoint(x:0,y:max(-list.adjustedContentInset.top,list.contentSize.height-list.bounds.height+list.adjustedContentInset.bottom)),animated:false)
   DispatchQueue.main.asyncAfter(deadline:.now()+0.7){
    self.capture("root-settings")
    let cellRect=entry.convert(entry.rectForRow(at:IndexPath(row:1,section:0)),to:window)
    let miniTop=chrome.mini.view.convert(chrome.mini.view.bounds,to:window).minY
    self.write("root last row bottom=\(cellRect.maxY); mini top=\(miniTop)")
    precondition(cellRect.maxY<=miniTop-10,"root row under mini-player")
    if let cv=list as? UICollectionView, let footer=cv.collectionViewLayout.layoutAttributesForSupplementaryView(ofKind:UICollectionView.elementKindSectionFooter,at:IndexPath(item:0,section:3)) {
     let gap=entry.frame.minY-footer.frame.maxY;self.write("entry-to-reset-footer gap=\(gap)");precondition(abs(gap)<1,"entry separated by spacer")
    }
    let rect=entry.convert(entry.bounds,to:window)
    self.write("entry frame=\(rect); contentSize=\(list.contentSize); inset=\(list.contentInset); roots=\(root.children.count)")
    entry.delegate?.tableView?(entry,didSelectRowAt:IndexPath(row:0,section:0))
    DispatchQueue.main.asyncAfter(deadline:.now()+0.8){
     self.capture("downloads-top")
     guard let page=nav.topViewController as? UITableViewController else{return}
     precondition(page.tableView.numberOfSections==5)
     precondition(page.tableView.numberOfRows(inSection:1)==4,"quota/license/device rows missing")
     let modeCell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:0,section:1))
     precondition((modeCell.contentConfiguration as? UIListContentConfiguration)?.text=="Configured request mode","selected mode must not be presented as verified execution")
     precondition(!modeCell.isUserInteractionEnabled,"mode 0 must be read-only")
     let reuseTable=ReusingSettingsTable(frame:.zero,style:.insetGrouped)
     let disabled=page.tableView.dataSource!.tableView(reuseTable,cellForRowAt:IndexPath(row:0,section:1))
     precondition(!disabled.isUserInteractionEnabled)
     reuseTable.recycled=disabled
     for _ in 0..<3 {for section in 0..<page.tableView.numberOfSections {for row in 0..<page.tableView.numberOfRows(inSection:section) {
      if section==1 && row==0 {continue}
      _=page.tableView.dataSource!.tableView(reuseTable,cellForRowAt:IndexPath(row:0,section:1))
      precondition(!disabled.isUserInteractionEnabled,"mode row must remain read-only")
      let action=page.tableView.dataSource!.tableView(reuseTable,cellForRowAt:IndexPath(row:row,section:section))
      precondition(action === disabled && action.isUserInteractionEnabled && action.selectionStyle == .default,"recycled read-only mode cell disabled an action")
     }}}
     self.write("PASS: every action remains tappable after repeated reuse of the disabled mode row")
     let modeFooter=page.tableView.dataSource!.tableView?(page.tableView,titleForFooterInSection:1) ?? ""
     precondition(modeFooter.contains("Device registrations control offline access on copies of Spotify."))
     precondition(!modeFooter.lowercased().contains("recovery"))
     let refreshCell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:1,section:1))
     precondition((refreshCell.contentConfiguration as? UIListContentConfiguration)?.text=="Refresh quotas and licenses")
     for (row,title) in [(2,"Manage offline device slots"),(3,"Enable offline listening on this copy")] {
      let cell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:row,section:1))
      precondition((cell.contentConfiguration as? UIListContentConfiguration)?.text==title)
     }
     precondition(page.title=="Pixie Download Manager","Pixie must remain in English")
     for section in 0..<page.tableView.numberOfSections {for row in 0..<page.tableView.numberOfRows(inSection:section) {
      let cell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:row,section:section))
      if let content=cell.contentConfiguration as? UIListContentConfiguration {
       precondition(!(content.text ?? "").contains("WAV"),"WAV row still present")
       precondition(!(content.text ?? "").contains("Заглушить") && !(content.text ?? "").contains("Mute audio"),"mute row still present")
       precondition(!(content.text ?? "").contains("Export") && !(content.text ?? "").contains("Send log"),"duplicate log export row")
      }
     }}
     self.exerciseSlots(page:page,nav:nav) {
     page.tableView.scrollToRow(at:IndexPath(row:0,section:3),at:.middle,animated:false)
     DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
      let togglePath=IndexPath(row:0,section:3)
      if let toggle=page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch {
       precondition(!toggle.isOn,"diagnostics must default off")
       toggle.isOn=true;toggle.sendActions(for:.valueChanged)
       precondition((page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch)?.isOn == true)
       if let current=page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch {current.isOn=false;current.sendActions(for:.valueChanged)}
       precondition((page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch)?.isOn == false)
       self.write("PASS: legacy and module-qualified native page protocols; diagnostics switch defaults OFF and toggles ON/OFF")
      } else {preconditionFailure("diagnostics switch not visible")}

      page.tableView.setContentOffset(CGPoint(x:0,y:max(0,page.tableView.contentSize.height-page.tableView.bounds.height+page.tableView.adjustedContentInset.bottom)),animated:false)
      page.tableView.layoutIfNeeded()
      self.capture("downloads-bottom")
      let last=page.tableView.convert(page.tableView.rectForRow(at:IndexPath(row:1,section:4)),to:window)
      self.write("downloads last row bottom=\(last.maxY); mini top=\(miniTop); inset=\(page.tableView.contentInset)")
      precondition(last.maxY<=miniTop-10,"downloads row under mini-player")
      page.tableView.delegate?.tableView?(page.tableView,didSelectRowAt:IndexPath(row:1,section:3))
      DispatchQueue.main.asyncAfter(deadline:.now()+0.7){self.capture("diagnostics");self.write("PASS: entry spacing, mini-player clearance, navigation and native pages rendered")}
     }
     }
    }
   }
  }
 }
 @MainActor func exerciseSlots(page:UITableViewController,nav:UINavigationController,completion:@escaping ()->Void) {
  Task { @MainActor in
   func settle() async {try? await Task.sleep(nanoseconds:450_000_000)}
   @MainActor func select(_ controller:UITableViewController,_ section:Int,_ row:Int) {
    controller.tableView.delegate?.tableView?(controller.tableView,didSelectRowAt:IndexPath(row:row,section:section))
   }
   @MainActor func currentAlert()->UIAlertController {
    let candidates:[UIViewController?]=[page,nav,self.window?.rootViewController]
    guard let alert=candidates.compactMap({$0?.presentedViewController as? UIAlertController}).first else {preconditionFailure("expected original slot dialog")}
    return alert
   }
   @MainActor func assertMenuHittable() {
    precondition(nav.topViewController===page,"original menu unexpectedly replaced")
    precondition(page.presentedViewController==nil && nav.presentedViewController==nil && self.window?.rootViewController?.presentedViewController==nil)
    page.tableView.scrollToRow(at:IndexPath(row:1,section:1),at:.middle,animated:false)
    page.tableView.layoutIfNeeded()
    for index in page.tableView.indexPathsForVisibleRows ?? [] where index != IndexPath(row:0,section:1) {
     guard let cell=page.tableView.cellForRow(at:index),let window=self.window else {preconditionFailure("missing visible action")}
     let center=cell.convert(CGPoint(x:cell.bounds.midX,y:cell.bounds.midY),to:window)
     if center.y<page.view.safeAreaInsets.top+8 || center.y>window.bounds.height-154 {continue}
     let hit=window.hitTest(center,with:nil)
     precondition(hit != nil && (hit===cell || hit!.isDescendant(of:cell)),"action intercepted after slots: \(index), hit=\(String(describing:hit))")
    }
   }
   for success in [false,true,false] {
    select(page,1,2);await settle();precondition(nav.topViewController===page)
    SAPFixtureCompleteSlotPreview(success);await settle();let alert=currentAlert()
    precondition(alert.preferredStyle==(success ? .actionSheet:.alert),"original slot dialog style changed")
    self.capture(success ? "slots-original-list":"slots-original-error")
    await withCheckedContinuation { (done:CheckedContinuation<Void,Never>) in alert.dismiss(animated:true,completion:{done.resume()}) }
    await settle();assertMenuHittable()
    select(page,2,0);await settle();precondition(nav.topViewController !== page,"status button stopped responding")
    nav.popViewController(animated:false);await settle();assertMenuHittable()
   }
   precondition(SAPFixtureSlotReleaseCalls()==0,"reading or dismissing slots sent a mutation")
   self.write("PASS: original slot dialogs success/error/dismissal repeated; every visible menu action is hittable and status navigation works")
   completion()
  }
 }
 func descendants(_ view:UIView)->[UIView]{[view]+view.subviews.flatMap{descendants($0)}}
 func capture(_ name:String){guard let w=window else{return};let image=UIGraphicsImageRenderer(bounds:w.bounds).image{_ in w.drawHierarchy(in:w.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(name+".png"))}
 func write(_ value:String){let u=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.log");let old=(try?String(contentsOf:u,encoding:.utf8)) ?? "";try?(old+value+"\n").write(to:u,atomically:true,encoding:.utf8)}
}
