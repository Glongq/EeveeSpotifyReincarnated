import UIKit
class GradientView:UIView {}
enum Theme {static let accent=UIColor.systemGreen}
extension String {var localized:String {self=="playlist_play" ? "Играть" : self=="playlist_pause" ? "Пауза" : self}}
func eeveeLog(_ format:String,_ arguments:CVarArg...) {}
final class CountingRoot:UIView {
 var reads=0
 override var subviews:[UIView] {reads+=1;return super.subviews}
}
@available(iOS 26.0, *)
final class Fixture:UIViewController {
 let row=PlaylistActionRow(frame:CGRect(x:0,y:190,width:430,height:48))
 let originals=UIView(frame:CGRect(x:0,y:190,width:430,height:48))
 var count=[String:Int]();var native=[String:UIButton]();var icons=[String:UIImageView]()
 override func viewDidLoad(){
  super.viewDidLoad();view.backgroundColor = .black
  let title=UILabel(frame:CGRect(x:16,y:105,width:390,height:45));title.text="Кнопки плейлиста";title.textColor = .white;title.font = .boldSystemFont(ofSize:26);view.addSubview(title)
  view.addSubview(originals)
  for name in ["explore","download","shuffle","play","add","share"] {
   let button=UIButton(type:.custom);button.frame=CGRect(x:name=="download" ? 76 : 16,y:0,width:48,height:48);button.accessibilityLabel=name
   let icon=UIImageView(frame:CGRect(x:12,y:12,width:24,height:24));icon.image=UIImage(systemName:name=="download" ? "arrow.down.circle" : "music.note")?.withTintColor(.white,renderingMode:.alwaysOriginal);button.addSubview(icon);icons[name]=icon
   button.addAction(UIAction{[weak self]_ in self?.count[name,default:0]+=1},for:.touchUpInside)
   if name=="download" {button.accessibilityIdentifier="DownloadButton.Granular.None"}
   button.alpha=["download","explore"].contains(name) ? 1 : 0
   native[name]=button;originals.addSubview(button)
  }

  row.shuffle=native["shuffle"];row.play=native["play"];row.add=native["add"];row.share=native["share"]
  view.addSubview(row);row.sync();PlaylistActionRow.current=row
  DispatchQueue.main.asyncAfter(deadline:.now()+0.4){self.row.bindNative(download:PlaylistActionRow.downloadControl(in:self.originals),preview:self.native["explore"],root:self.originals);self.row.sync();self.check()}
 }
 func log(_ text:String){let url=FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("result.log");let old=(try?String(contentsOf:url,encoding:.utf8)) ?? "";try?(old+text+"\n").write(to:url,atomically:true,encoding:.utf8)}
 func descendants(_ view:UIView)->[UIView]{[view]+view.subviews.flatMap{descendants($0)}}
 func check(){
  let nodes=descendants(row);let play=nodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Play"} as! UIButton
  let strip=nodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Actions"} as! UIScrollView
  let share=nodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Share"} as! UIButton
  let download=native["download"]!
  precondition(!nodes.contains{$0.accessibilityIdentifier=="Eevee.Playlist.Download" || $0.accessibilityIdentifier=="Eevee.Playlist.Explore"},"native controls must not be replaced")
  precondition(download.superview===strip && native["explore"]?.superview===strip && icons["download"]?.superview===download)
  precondition(download.configuration==nil,"native button configuration changed")
  let pane=download.subviews.first as! UIVisualEffectView
  precondition(pane.effect is UIGlassEffect && pane.frame==download.bounds && !pane.isUserInteractionEnabled)
  PlaylistDownloadControl.style(download);precondition(download.subviews.filter{$0 is UIVisualEffectView}.count==1)
  for width in [320.0,390.0,430.0,768.0] {
   row.frame.size.width=width;row.setNeedsLayout();row.layoutIfNeeded()
   precondition(abs(play.frame.maxX-(width-16))<0.5)
   precondition(strip.frame.maxX<=play.frame.minX-12)
   precondition(strip.frame.minX==16)
   precondition(download.frame.maxX+12 <= (nodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Shuffle"} as! UIButton).frame.minX)
   precondition(!strip.alwaysBounceVertical && strip.contentSize.height==48)
   let fixed=play.frame;strip.contentOffset=CGPoint(x:max(0,strip.contentSize.width-strip.bounds.width),y:0)
   precondition(play.frame==fixed && strip.touchesShouldCancel(in:share))
   precondition(share.convert(share.bounds,to:strip).maxX<=strip.bounds.maxX+0.5)
   strip.contentOffset = .zero
   precondition(row.hitTest(download.convert(CGPoint(x:24,y:24),to:row),with:nil)===download,"native download hit target lost")
   log("PASS: width \(width), native download clear, Play right, horizontally reachable actions")
  }
  for name in ["Shuffle","Play","Add","Share"] {
   let button=nodes.first{$0.accessibilityIdentifier=="Eevee.Playlist."+name} as! UIButton
   button.sendActions(for:.primaryActionTriggered);precondition(count[name.lowercased()]==1)
  }
  download.sendActions(for:.touchUpInside);precondition(count["download"]==1)
  for state in ["None","Waiting","Downloading","Downloaded","Error"] {
   download.accessibilityIdentifier="DownloadButton.Granular."+state
   precondition(PlaylistActionRow.downloadControl(in:originals)===download)
  }
  icons["download"]!.image=UIImage(systemName:"checkmark.circle.fill")?.withTintColor(.systemGreen,renderingMode:.alwaysOriginal)
  precondition(icons["download"]?.superview===download && download.superview===strip)
  log("PASS: complete native icon/ring retained, native state updates and native tap; one glass pane")
  let root=CountingRoot();let source=UIButton();source.accessibilityIdentifier="DownloadButton.Granular.None";root.addSubview(source)
  precondition(PlaylistDownloadControl.resolve(in:root)===source);let reads=root.reads
  for _ in 0..<100 {precondition(PlaylistDownloadControl.resolve(in:root)===source)}
  precondition(root.reads==reads,"lookup repeatedly traverses the header")
  source.removeFromSuperview();let replacement=UIButton();replacement.accessibilityIdentifier="DownloadButton.Granular.Error";root.addSubview(replacement)
  precondition(PlaylistDownloadControl.resolve(in:root)===replacement)
  let empty=CountingRoot();precondition(PlaylistDownloadControl.resolve(in:empty)==nil);let misses=empty.reads
  for _ in 0..<100 {precondition(PlaylistDownloadControl.resolve(in:empty)==nil)}
  precondition(empty.reads==misses,"missing source repeatedly searched")
  for identifier in ["Components.UI.DownloadIcon","Components.UI.DownloadButton"] {let host=UIView();let control=UIButton();control.accessibilityIdentifier=identifier;host.addSubview(control);precondition(PlaylistDownloadControl.resolve(in:host)===control)}
  // Spotify can fade in the preview after the first row layout. The same
  // view binding must invalidate geometry when it becomes mountable.
  let delayed=PlaylistActionRow(frame:CGRect(x:0,y:400,width:430,height:48));view.addSubview(delayed)
  let delayedRoot=UIView(frame:CGRect(x:0,y:400,width:430,height:48));view.addSubview(delayedRoot)
  let delayedPreview=UIView(frame:CGRect(x:0,y:0,width:58,height:40));delayedRoot.addSubview(delayedPreview)
  delayedRoot.alpha=0
  delayed.bindNative(download:nil,preview:delayedPreview,root:delayedRoot);delayed.sync();delayed.layoutIfNeeded()
  delayedRoot.alpha=1
  delayed.bindNative(download:nil,preview:delayedPreview,root:delayedRoot);delayed.layoutIfNeeded()
  let delayedShuffle=descendants(delayed).first{$0.accessibilityIdentifier=="Eevee.Playlist.Shuffle"}!
  precondition(delayedPreview.frame.maxX+12<=delayedShuffle.frame.minX,"late native preview overlaps shuffle")
  delayed.removeFromSuperview();delayedRoot.removeFromSuperview()
  log("PASS: delayed preview appearance invalidates row geometry")
  let nativeFrame=download.frame
  for _ in 0..<100 {row.bindNative(download:PlaylistDownloadControl.resolve(in:originals),preview:native["explore"],root:originals)}
  precondition(download.superview===strip && download.frame==nativeFrame)
  // A reclaimed native view is not repeatedly moved back by a layout loop.
  let isolated=PlaylistActionRow();view.addSubview(isolated);let host=UIView();view.addSubview(host)
  let single=UIButton(frame:CGRect(x:0,y:0,width:48,height:48));single.accessibilityIdentifier="DownloadButton.Granular.None";host.addSubview(single)
  isolated.bindNative(download:single,preview:nil,root:host);host.addSubview(single)
  isolated.bindNative(download:single,preview:nil,root:host);precondition(single.superview===host)
  isolated.removeFromSuperview();host.removeFromSuperview()
  log("PASS: cached binding, no repeated tree searches or reparenting; native replacement; album/legacy components")
  native["explore"]!.isHidden=true
  row.frame.size.width=view.bounds.width;row.setNeedsLayout();row.layoutIfNeeded();strip.contentOffset = .zero
  precondition(strip.frame.minX==16 && download.frame.minX==0,"hidden preview reserves an empty slot")
  log("PASS: hidden preview does not reserve space; native preview never restyled; common horizontal area")
  let description=UILabel(frame:CGRect(x:16,y:270,width:view.bounds.width-32,height:100));description.numberOfLines=0;description.text="Родная кнопка скачивания со стеклом.\nСправа — «Играть», слева — действия.";description.textColor = .lightGray;view.addSubview(description)
  let lateRow=PlaylistActionRow(frame:CGRect(x:0,y:450,width:430,height:48));view.addSubview(lateRow)
  let lateRoot=UIView();view.addSubview(lateRoot)
  let latePreview=UIButton(frame:CGRect(x:8,y:0,width:8,height:48));latePreview.isHidden=true;lateRoot.addSubview(latePreview)
  lateRow.bindNative(download:nil,preview:latePreview,root:lateRoot);lateRow.sync();lateRow.layoutIfNeeded()
  precondition(latePreview.superview===lateRoot)
  // Exact device sequence: native content arrives without another bind or
  // controller layout. Only the native view's hidden/bounds events change.
  latePreview.frame.size=CGSize(width:58,height:40);latePreview.isHidden=false
  DispatchQueue.main.asyncAfter(deadline:.now()+0.2){
   lateRow.layoutIfNeeded()
   let lateNodes=self.descendants(lateRow)
   let strip=lateNodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Actions"}!
   let shuffle=lateNodes.first{$0.accessibilityIdentifier=="Eevee.Playlist.Shuffle"}!
   precondition(latePreview.superview===strip && latePreview.bounds.size==CGSize(width:58,height:40))
   precondition(latePreview.frame.maxX+12<=shuffle.frame.minX,"async native preview overlaps shuffle")
   precondition(PlaylistDownloadControl.resolve(in:lateRoot)==nil,"artist gained a synthetic download")
   self.log("PASS: native hidden 8pt placeholder becomes 58pt preview without rebinding; artist has no download")
   lateRow.removeFromSuperview();lateRoot.removeFromSuperview()
   self.checkNativeArtist()
  }
 }
 func checkNativeArtist(){
  let artistRow=PlaylistActionRow(frame:CGRect(x:0,y:550,width:430,height:48));view.addSubview(artistRow)
  let artistHost=UIView(frame:artistRow.frame);view.addSubview(artistHost)
  let preview=UIView(frame:CGRect(x:16,y:0,width:8,height:72));preview.isHidden=true;artistHost.addSubview(preview)
  let hit=UIButton(frame:CGRect(x:-16,y:14,width:44,height:44));preview.addSubview(hit)
  artistRow.bindNative(download:nil,preview:preview,root:artistHost,preservePreviewLayout:true);artistRow.sync();artistRow.layoutIfNeeded()
  preview.isHidden=false
  // Spotify, not the tweak, changes native component geometry after loading.
  preview.frame=CGRect(x:16,y:4,width:58,height:40);hit.frame=preview.bounds
  let expected=preview.frame
  DispatchQueue.main.asyncAfter(deadline:.now()+0.1){
   artistRow.layoutIfNeeded()
   let strip=self.descendants(artistRow).first{$0.accessibilityIdentifier=="Eevee.Playlist.Actions"} as! UIScrollView
   precondition(preview.superview===artistHost && preview.frame==expected,"artist native preview was moved or resized")
   precondition(strip.frame.minX >= preview.convert(preview.bounds,to:artistRow).maxX+12)
   precondition(!self.descendants(preview).contains{$0 is UIVisualEffectView},"artist preview gained glass")
   for _ in 0..<100 {artistRow.bindNative(download:nil,preview:preview,root:artistHost,preservePreviewLayout:true)}
   precondition(preview.superview===artistHost && preview.frame==expected)
   // Keep native overflow geometry: a small shell can draw outside its bounds.
   preview.frame.size.width=8;hit.frame=CGRect(x:-16,y:0,width:44,height:40)
   DispatchQueue.main.asyncAfter(deadline:.now()+0.1){
    artistRow.layoutIfNeeded()
    precondition(strip.frame.minX >= hit.convert(hit.bounds,to:artistRow).maxX+12,"artist artwork overflow intersects shuffle")
    precondition(preview.superview===artistHost && preview.bounds.width==8)
    self.log("PASS: artist keeps native preview parent/frame, async size and overflow reserved, no glass or synthetic download")
    artistRow.removeFromSuperview();artistHost.removeFromSuperview()
    self.capture();self.log("PASS: production PlaylistActionRow UI fixture complete")
   }
  }
 }
 func capture(){guard let w=view.window else{return};let png=UIGraphicsImageRenderer(bounds:w.bounds).image{_ in w.drawHierarchy(in:w.bounds,afterScreenUpdates:true)}.pngData();try?png?.write(to:FileManager.default.urls(for:.documentDirectory,in:.userDomainMask)[0].appendingPathComponent("action-row.png"))}
}
@main class App:UIResponder,UIApplicationDelegate {func application(_ app:UIApplication,didFinishLaunchingWithOptions options:[UIApplication.LaunchOptionsKey:Any]?=nil)->Bool {true}}
@objc(ActionRowSceneDelegate) class SceneDelegate:UIResponder,UIWindowSceneDelegate {
 var window:UIWindow?
 func scene(_ scene:UIScene,willConnectTo session:UISceneSession,options:UIScene.ConnectionOptions) {
  guard let scene=scene as? UIWindowScene else{return};let w=UIWindow(windowScene:scene);window=w;w.overrideUserInterfaceStyle = .dark;w.rootViewController=Fixture();w.makeKeyAndVisible()
 }
}
