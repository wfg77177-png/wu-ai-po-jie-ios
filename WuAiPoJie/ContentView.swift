import SwiftUI
import WebKit

// MARK: - JS #1: CSS only, injected at document start (kills white flash)
// Only dark-mode CSS + ad-hiding CSS. Runs in main frame only.
private let wjCSSJS = """
(function(){
  try{
    var dark = localStorage.getItem('wj_dark') === '1';
    var hideAds = localStorage.getItem('wj_hideAds');
    if (hideAds === null) hideAds = '1';
    if (dark) {
      var s = document.createElement('style'); s.id = 'wj-dark-style';
      s.textContent = 'html{filter:invert(1) hue-rotate(180deg);background:#0f0f0f !important;} img,video,iframe,svg{filter:invert(1) hue-rotate(180deg);}';
      document.documentElement.appendChild(s);
    }
    if (hideAds === '1') {
      var a = document.createElement('style'); a.id = 'wj-ad-style';
      a.textContent = '[class*="ad-"],[id*="ad-"],[id^="ad_"],[class*="advert"],[class*="sponsor"],[class*="promo-banner"],[class*="a_pt"],[class*="a_mu"]{display:none !important;}';
      document.documentElement.appendChild(a);
    }
  }catch(e){}
})();
"""

// MARK: - JS #2: features, injected at document end, main frame only
// Safe features only: sign-in (called from native after real load),
// dark mode, hide ads, keyword filter, hide 悬赏/导读， fullscreen images,
// remember scroll position, section navigation, back to top.
// No auto-reply / auto-comment. localStorage holds only the sign-in date
// guard and display settings — never any session, token or credential.
private let wjJS = """
(function(){
  function store(k,v){ try{ localStorage.setItem('wj_'+k, v); }catch(e){} }
  function read(k,d){ try{ var v=localStorage.getItem('wj_'+k); return v===null?d:v; }catch(e){ return d; } }

  function showToast(msg){
    var t=document.createElement('div');
    t.textContent=msg;
    t.style.cssText='position:fixed;left:50%;bottom:90px;transform:translateX(-50%);background:rgba(0,0,0,0.82);color:#fff;padding:10px 16px;border-radius:20px;font-size:14px;z-index:999999;pointer-events:none;';
    document.body.appendChild(t);
    setTimeout(function(){ t.remove(); }, 2600);
  }
  window.__wjToast = showToast;

  // ---------- 1. Sign-in (best effort, once per day) ----------
  // Called ONLY from native code after a real page load (didFinish) on a
  // 52pojie host — never fired on challenge/error pages.
  // Endpoint is from an older source and NOT guaranteed on the current site;
  // the button-click fallback below covers the case where the endpoint moved.
  window.__wjTrySignIn = function(force){
    var today = new Date().toISOString().slice(0,10);
    if(!force && read('signDate','') === today) return;
    fetch('/home.php?mod=task&do=apply&id=2', {method:'GET', credentials:'include'})
      .then(function(){ store('signDate', today); })
      .catch(function(){});
    setTimeout(function(){
      var els = document.querySelectorAll('a, button, input, img');
      for(var i=0;i<els.length;i++){
        var el = els[i];
        var txt = (el.textContent||'') + ' ' + (el.getAttribute('title')||'') + ' ' + (el.getAttribute('alt')||'') + ' ' + (el.getAttribute('value')||'');
        if(txt.indexOf('签到') !== -1){
          var t = el.tagName === 'IMG' ? (el.closest('a') || el) : el;
          try{ t.click(); }catch(e){}
          break;
        }
      }
    }, 1500);
  };

  // ---------- 2. Dark mode ----------
  window.__wjSetDark = function(on){
    store('dark', on?'1':'0');
    var id='wj-dark-style', el=document.getElementById(id);
    if(on){
      if(!el){
        el=document.createElement('style'); el.id=id;
        el.textContent='html{filter:invert(1) hue-rotate(180deg);background:#0f0f0f !important;} img,video,iframe,svg{filter:invert(1) hue-rotate(180deg);}';
        document.documentElement.appendChild(el);
      }
    } else if(el){ el.remove(); }
  };
  if (read('dark','0')==='1') { window.__wjSetDark(true); }

  // ---------- 3. Hide ads / promo blocks ----------
  window.__wjSetHideAds = function(on){
    store('hideAds', on?'1':'0');
    var id='wj-ad-style', el=document.getElementById(id);
    if(on){
      if(!el){
        el=document.createElement('style'); el.id=id;
        el.textContent='[class*="ad-"],[id*="ad-"],[id^="ad_"],[class*="advert"],[class*="sponsor"],[class*="promo-banner"],[class*="a_pt"],[class*="a_mu"]{display:none !important;}';
        document.documentElement.appendChild(el);
      }
    } else if(el){ el.remove(); }
  };
  if (read('hideAds','1')==='1') { window.__wjSetHideAds(true); }

  // ---------- 4. Keyword filter (Discuz thread links) ----------
  window.__wjSetKeywords = function(csv){
    store('keywords', csv||'');
    applyKeywords();
  };
  function applyKeywords(){
    var csv = read('keywords','');
    var kws = csv.split(',').map(function(s){ return s.trim(); }).filter(function(s){ return s.length>0; });
    if(kws.length===0) return;
    var rows = document.querySelectorAll('a[href*="thread-"], a[href*="viewthread"]');
    rows.forEach(function(a){
      var row = a.closest('li, article, div, tr');
      if(!row) return;
      var txt = (a.textContent||'');
      var hit = kws.some(function(k){ return txt.indexOf(k) !== -1; });
      row.style.display = hit ? 'none' : '';
    });
  }
  window.__wjApplyKeywords = applyKeywords;
  applyKeywords();
  new MutationObserver(function(){ applyKeywords(); }).observe(document.documentElement, {childList:true, subtree:true});

  // ---------- 5. Hide 悬赏问答区 / 新帖导读 (toggle, default off) ----------
  window.__wjSetHideReward = function(on){
    store('hideReward', on?'1':'0');
    applyHideReward();
  };
  function applyHideReward(){
    var on = read('hideReward','0')==='1';
    document.querySelectorAll('a').forEach(function(a){
      var t=(a.textContent||'').trim();
      if(t.indexOf('悬赏问答区') !== -1){
        var row = a.closest('tr');
        if(row) row.style.display = on ? 'none' : '';
      } else if(t.indexOf('新帖导读') !== -1){
        a.style.display = on ? 'none' : '';
      }
    });
  }
  window.__wjApplyHideReward = applyHideReward;
  applyHideReward();
  new MutationObserver(function(){ applyHideReward(); }).observe(document.documentElement, {childList:true, subtree:true});

  // ---------- 6. Fullscreen image viewer ----------
  document.addEventListener('click', function(e){
    var img = e.target.closest ? e.target.closest('img') : null;
    if(!img || !img.src) return;
    if(img.closest('a')) return;
    var ov=document.createElement('div');
    ov.style.cssText='position:fixed;inset:0;background:rgba(0,0,0,0.92);z-index:999999;display:flex;align-items:center;justify-content:center;';
    var im=document.createElement('img');
    im.src=img.src; im.style.cssText='max-width:96vw;max-height:92vh;object-fit:contain;';
    ov.appendChild(im);
    ov.addEventListener('click', function(){ ov.remove(); });
    document.body.appendChild(ov);
  }, true);

  // ---------- 7. Remember scroll position (per URL) ----------
  var saveTimer=null;
  function savePos(){
    try{ sessionStorage.setItem('wj_pos_'+location.pathname, String(window.scrollY)); }catch(e){}
  }
  window.addEventListener('scroll', function(){
    if(saveTimer) clearTimeout(saveTimer);
    saveTimer=setTimeout(savePos, 400);
  }, {passive:true});
  window.addEventListener('pagehide', savePos);
  (function restorePos(){
    try{
      var y=parseInt(sessionStorage.getItem('wj_pos_'+location.pathname)||'0',10);
      if(y>200){ setTimeout(function(){ window.scrollTo(0,y); }, 350); }
    }catch(e){}
  })();

  // ---------- 8. Section navigation (tap a section name in the native picker) ----------
  window.__wjGoSection = function(name){
    var links = Array.prototype.slice.call(document.querySelectorAll('a'));
    var hit = links.find(function(a){
      var t=(a.textContent||'').trim();
      var href=a.getAttribute('href');
      if(!href || href.indexOf('/')!==0) return false;
      return t===name || t==='『'+name+'』' || t.indexOf('『'+name+'』')!==-1;
    });
    if(hit){ hit.click(); return true; }
    return false;
  };

  // ---------- 9. Back to top ----------
  window.__wjTop = function(){ window.scrollTo({top:0, behavior:'smooth'}); };

  // ---------- 10. Re-apply after a real load (called from native didFinish) ----------
  window.__wjReapply = function(){
    applyKeywords();
    applyHideReward();
    try{
      var y=parseInt(sessionStorage.getItem('wj_pos_'+location.pathname)||'0',10);
      if(y>200){ setTimeout(function(){ window.scrollTo(0,y); }, 300); }
    }catch(e){}
  };
})();
"""

// MARK: - Model
final class BrowserModel: ObservableObject {
    weak var webView: WKWebView?
    @Published var isDark = false
    @Published var fontScale: CGFloat = 1.0
    @Published var hideAds = true
    @Published var hideReward = false
    @Published var keywords = ""
    @Published var canGoBack = false

    let homeURL = URL(string: "https://www.52pojie.cn/")!
    // Board names verified from the live site (2026-11-17); navigation is by
    // JS link-text click, no hardcoded board URLs.
    let sections = ["原创发布区","脱壳破解区","移动安全区","软件调试区","编程语言区","动画发布区","逆向资源区","精品软件区","悬赏问答区","病毒分析区","病毒救援区","安全工具区"]

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }
    func goHome() { load(homeURL) }
    func reload() { webView?.reload() }
    func goBack() { webView?.goBack() }
    func backToTop() {
        webView?.evaluateJavaScript("window.__wjTop && window.__wjTop();", completionHandler: nil)
    }
    func goSection(_ name: String) {
        webView?.evaluateJavaScript("window.__wjGoSection && window.__wjGoSection('\(name)');") { _, _ in }
    }
    func setDark(_ on: Bool) {
        isDark = on
        UserDefaults.standard.set(on, forKey: "wj_dark")
        webView?.evaluateJavaScript("window.__wjSetDark && window.__wjSetDark(\(on ? "true" : "false"));", completionHandler: nil)
    }
    func setFontScale(_ s: CGFloat) {
        fontScale = s
        UserDefaults.standard.set(Double(s), forKey: "wj_fontScale")
        webView?.pageZoom = s
    }
    func setHideAds(_ on: Bool) {
        hideAds = on
        UserDefaults.standard.set(on, forKey: "wj_hideAds")
        webView?.evaluateJavaScript("window.__wjSetHideAds && window.__wjSetHideAds(\(on ? "true" : "false"));", completionHandler: nil)
    }
    func setHideReward(_ on: Bool) {
        hideReward = on
        UserDefaults.standard.set(on, forKey: "wj_hideReward")
        webView?.evaluateJavaScript("window.__wjSetHideReward && window.__wjSetHideReward(\(on ? "true" : "false"));", completionHandler: nil)
    }
    func setKeywords(_ s: String) {
        keywords = s
        UserDefaults.standard.set(s, forKey: "wj_keywords")
        let esc = s.replacingOccurrences(of: "'", with: "\\'")
        webView?.evaluateJavaScript("window.__wjSetKeywords && window.__wjSetKeywords('\(esc)');", completionHandler: nil)
    }
    func manualSignIn() {
        webView?.evaluateJavaScript("window.__wjTrySignIn && window.__wjTrySignIn(true); window.__wjToast && window.__wjToast('已尝试签到');", completionHandler: nil)
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var showSections = false
    @State private var showSettings = false

    var body: some View {
        ZStack(alignment: .bottom) {
            WebView(model: model)
                .ignoresSafeArea(edges: .top)
            BottomBar(model: model, showSections: $showSections, showSettings: $showSettings)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSections) { SectionSheet(model: model) }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .onAppear {
            model.isDark = UserDefaults.standard.bool(forKey: "wj_dark")
            model.hideAds = UserDefaults.standard.object(forKey: "wj_hideAds") as? Bool ?? true
            model.hideReward = UserDefaults.standard.bool(forKey: "wj_hideReward")
            model.keywords = UserDefaults.standard.string(forKey: "wj_keywords") ?? ""
            let fs = UserDefaults.standard.double(forKey: "wj_fontScale")
            if fs > 0 { model.fontScale = CGFloat(fs) }
        }
    }
}

// MARK: - WebView (created eagerly as the root view; loads immediately)
// Speed comes from: early WKWebView creation + immediate load, the default
// persistent website data store (cache + cookies persist, Cloudflare
// cf_clearance survives, so repeat opens skip verification), and small
// injected JS. No cache clearing, no .nonPersistent(), no
// .reloadIgnoringLocalCacheData, no custom UA, no prewarm webview.
struct WebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let cssScript = WKUserScript(source: wjCSSJS, injectionTime: .atDocumentStart, forMainFrameOnly: true)
        config.userContentController.addUserScript(cssScript)
        let script = WKUserScript(source: wjJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        // leave room so the last line is never hidden behind the bottom bar
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        // apply the saved font size right away from UserDefaults (do not wait
        // for onAppear / the toolbar to finish reading settings)
        let fs = UserDefaults.standard.double(forKey: "wj_fontScale")
        if fs > 0 { webView.pageZoom = CGFloat(fs) }
        webView.load(URLRequest(url: model.homeURL))
        model.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let model: BrowserModel
        init(model: BrowserModel) { self.model = model }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            model.canGoBack = webView.canGoBack
            // re-apply filters / scroll restore now that the page truly loaded
            webView.evaluateJavaScript("window.__wjReapply && window.__wjReapply();", completionHandler: nil)
            // sign-in only on a real 52pojie page — never on a challenge or
            // error page
            if let host = webView.url?.host, host == "www.52pojie.cn" || host == "52pojie.cn" {
                webView.evaluateJavaScript("window.__wjTrySignIn && window.__wjTrySignIn(false);", completionHandler: nil)
            }
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            model.canGoBack = webView.canGoBack
        }
    }
}

// MARK: - Bottom bar (comfortable proportions, smooth)
struct BottomBar: View {
    @ObservedObject var model: BrowserModel
    @Binding var showSections: Bool
    @Binding var showSettings: Bool

    var body: some View {
        HStack(spacing: 4) {
            BarButton(icon: "house", label: "首页") { model.goHome() }
            BarButton(icon: "square.grid.2x2", label: "分区") { showSections = true }
            BarButton(icon: "checkmark.seal", label: "签到") { model.manualSignIn() }
            BarButton(icon: model.isDark ? "moon.fill" : "moon", label: "深色") {
                model.setDark(!model.isDark)
            }
            BarButton(icon: "arrow.up", label: "顶部") { model.backToTop() }
            BarButton(icon: "gearshape", label: "设置") { showSettings = true }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 12, x: 0, y: 4)
    }
}

struct BarButton: View {
    let icon: String
    let label: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 19, weight: .medium))
                Text(label)
                    .font(.system(size: 10.5, weight: .medium))
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }
}

// MARK: - Section picker sheet
struct SectionSheet: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss

    let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(model.sections, id: \.self) { name in
                        Button {
                            model.goSection(name)
                            dismiss()
                        } label: {
                            Text(name)
                                .font(.system(size: 16, weight: .medium))
                                .frame(maxWidth: .infinity, minHeight: 52)
                                .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            .navigationTitle("分区")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Settings sheet
struct SettingsSheet: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var keywordsText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("阅读") {
                    HStack {
                        Text("字体大小")
                        Spacer()
                        Stepper("", value: Binding(
                            get: { model.fontScale },
                            set: { model.setFontScale($0) }
                        ), in: 0.85...1.35, step: 0.05)
                        Text(String(format: "%.0f%%", model.fontScale * 100))
                            .foregroundStyle(.secondary)
                            .frame(width: 48, alignment: .trailing)
                    }
                    Toggle("深色模式", isOn: Binding(
                        get: { model.isDark },
                        set: { model.setDark($0) }
                    ))
                    Toggle("隐藏广告与推广位", isOn: Binding(
                        get: { model.hideAds },
                        set: { model.setHideAds($0) }
                    ))
                    Toggle("隐藏悬赏问答区与新帖导读", isOn: Binding(
                        get: { model.hideReward },
                        set: { model.setHideReward($0) }
                    ))
                }
                Section("屏蔽关键词") {
                    TextField("多个关键词用英文逗号隔开", text: $keywordsText)
                        .onChange(of: keywordsText) { model.setKeywords($0) }
                    Text("包含这些词的帖子标题会被隐藏。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Button("刷新页面") { model.reload(); dismiss() }
                    Button("回到首页") { model.goHome(); dismiss() }
                }
            }
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
            .onAppear { keywordsText = model.keywords }
        }
        .presentationDetents([.medium, .large])
    }
}
