import UIKit
import SwiftUI

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
    let cellRect=entry.convert(entry.rectForRow(at:IndexPath(row:0,section:0)),to:window)
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
     precondition(page.tableView.numberOfSections==3)
     let english=ProcessInfo.processInfo.arguments.contains("(en)")
     precondition(page.title==(english ? "Track downloads" : "Загрузки треков"),"wrong app language")
     for section in 0..<3 {for row in 0..<page.tableView.numberOfRows(inSection:section) {
      let cell=page.tableView.dataSource!.tableView(page.tableView,cellForRowAt:IndexPath(row:row,section:section))
      if let content=cell.contentConfiguration as? UIListContentConfiguration {
       precondition(!(content.text ?? "").contains("WAV"),"WAV row still present")
      }
     }}
     page.tableView.setContentOffset(CGPoint(x:0,y:max(0,page.tableView.contentSize.height-page.tableView.bounds.height+page.tableView.adjustedContentInset.bottom)),animated:false)
     DispatchQueue.main.asyncAfter(deadline:.now()+0.5){
      self.capture("downloads-bottom")
      let togglePath=IndexPath(row:0,section:2)
      if let toggle=page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch {
       precondition(!toggle.isOn,"diagnostics must default off")
       toggle.isOn=true;toggle.sendActions(for:.valueChanged)
       precondition((page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch)?.isOn == true)
       if let current=page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch {current.isOn=false;current.sendActions(for:.valueChanged)}
       precondition((page.tableView.cellForRow(at:togglePath)?.accessoryView as? UISwitch)?.isOn == false)
       self.write("PASS: legacy and module-qualified native page protocols; diagnostics switch defaults OFF and toggles ON/OFF")
      } else {preconditionFailure("diagnostics switch not visible")}

      let last=page.tableView.convert(page.tableView.rectForRow(at:IndexPath(row:3,section:2)),to:window)
      self.write("downloads last row bottom=\(last.maxY); mini top=\(miniTop); inset=\(page.tableView.contentInset)")
      precondition(last.maxY<=miniTop-10,"downloads row under mini-player")
      page.tableView.delegate?.tableView?(page.tableView,didSelectRowAt:IndexPath(row:1,section:2))
      DispatchQueue.main.asyncAfter(deadline:.now()+0.7){self.capture("diagnostics");self.write("PASS: entry spacing, mini-player clearance, navigation and native pages rendered")}
     }
    }
   }
  }
 }
 func descendants(_ view:UIView)->[UIView]{[view]+view.subviews.flatMap{descendants($0)}}
 func capture(_ name:String){guard let w=window else{return};let image=UIGraphicsImageRenderer(bounds:w.bounds).image{_ in w.drawHierarchy(in:w.bounds,afterScreenUpdates:true)};try? image.pngData()?.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent(name+".png"))}
 func write(_ value:String){let u=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.log");let old=(try?String(contentsOf:u,encoding:.utf8)) ?? "";try?(old+value+"\n").write(to:u,atomically:true,encoding:.utf8)}
}
