import SwiftUI
import WebKit

// MARK: - JS: sign-in + toast + section navigation + back to top ONLY.
// Injected at document end, main frame only. Nothing else.
// localStorage holds only the sign-in date guard — never any session,
// token or credential.
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

  // Sign-in (best effort, once per day). Called ONLY from native code
  // after a real page load (didFinish) on a 52pojie host — never fired on
  // challenge/error pages. Endpoint is from an older source and NOT
  // guaranteed on the current site; the button-click fallback below covers
  // the case where the endpoint moved.
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

  // Section navigation (tap a section name in the native picker)
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

  // Back to top
  window.__wjTop = function(){ window.scrollTo({top:0, behavior:'smooth'}); };

  // In-site search history (localStorage, max 10)
  window.__wjAddSearchHist = function(q){
    try{
      var a=JSON.parse(localStorage.getItem('wj_searchHist')||'[]');
      if(!Array.isArray(a)) a=[];
      var i=a.indexOf(q);
      if(i!==-1) a.splice(i,1);
      a.unshift(q);
      localStorage.setItem('wj_searchHist', JSON.stringify(a.slice(0,10)));
    }catch(e){}
  };
  window.__wjGetSearchHist = function(){
    try{ return localStorage.getItem('wj_searchHist')||'[]'; }catch(e){ return '[]'; }
  };
})();
"""

// MARK: - Model
final class BrowserModel: ObservableObject {
    weak var webView: WKWebView?

    let homeURL = URL(string: "https://www.52pojie.cn/")!
    // Board names verified from the live site (2026-11-17); navigation is by
    // JS link-text click, no hardcoded board URLs.
    let sections = ["原创发布区","脱壳破解区","移动安全区","软件调试区","编程语言区","动画发布区","逆向资源区","精品软件区","悬赏问答区","病毒分析区","病毒救援区","安全工具区"]

    func load(_ url: URL) {
        webView?.load(URLRequest(url: url))
    }
    func goHome() { load(homeURL) }
    func reload() { webView?.reload() }
    func backToTop() {
        webView?.evaluateJavaScript("window.__wjTop && window.__wjTop();", completionHandler: nil)
    }
    func goSection(_ name: String) {
        webView?.evaluateJavaScript("window.__wjGoSection && window.__wjGoSection('\(name)');") { _, _ in }
    }
    func manualSignIn() {
        webView?.evaluateJavaScript("window.__wjTrySignIn && window.__wjTrySignIn(true); window.__wjToast && window.__wjToast('已尝试签到');", completionHandler: nil)
    }
    private func jsString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
    func searchForum(_ query: String) {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        webView?.evaluateJavaScript("window.__wjAddSearchHist && window.__wjAddSearchHist('\(jsString(q))');", completionHandler: nil)
        let enc = q.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? q
        if let url = URL(string: "https://www.52pojie.cn/search.php?mod=forum&srchtxt=\(enc)&searchsubmit=yes") {
            load(url)
        }
    }
    func loadSearchHistory(_ completion: @escaping ([String]) -> Void) {
        guard let webView = webView else { completion([]); return }
        webView.evaluateJavaScript("window.__wjGetSearchHist && window.__wjGetSearchHist();") { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let arr = try? JSONDecoder().decode([String].self, from: data) else {
                completion([])
                return
            }
            completion(arr)
        }
    }
}

// MARK: - ContentView
struct ContentView: View {
    @StateObject private var model = BrowserModel()
    @State private var showSections = false
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            WebView(model: model)
                .ignoresSafeArea(edges: .top)
            BottomBar(model: model, showSections: $showSections, showSearch: $showSearch)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSections) { SectionSheet(model: model) }
        .sheet(isPresented: $showSearch) { SearchSheet(model: model) }
    }
}

// MARK: - WebView (created eagerly as the root view; loads immediately)
// Speed comes from: early WKWebView creation + immediate load, the default
// persistent website data store (cache + cookies persist, so login stays
// and repeat opens skip verification), and tiny injected JS. No cache
// clearing, no .nonPersistent(), no .reloadIgnoringLocalCacheData,
// no custom UA.
struct WebView: UIViewRepresentable {
    @ObservedObject var model: BrowserModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = WKWebsiteDataStore.default()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let script = WKUserScript(source: wjJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
        config.userContentController.addUserScript(script)
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = true
        webView.scrollView.bounces = true
        webView.scrollView.contentInsetAdjustmentBehavior = .always
        // leave room so the last line is never hidden behind the bottom bar
        webView.scrollView.contentInset = UIEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        webView.scrollView.scrollIndicatorInsets = UIEdgeInsets(top: 0, left: 0, bottom: 76, right: 0)
        webView.load(URLRequest(url: model.homeURL))
        model.webView = webView
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let model: BrowserModel
        init(model: BrowserModel) { self.model = model }
        // Links that open in a new window (target="_blank", e.g. search results
        // and second-level pages) would otherwise do nothing: WKWebView has no
        // second web view to hand them to. Load them in this same web view.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if navigationAction.targetFrame == nil, let url = navigationAction.request.url {
                webView.load(URLRequest(url: url))
            }
            return nil
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // sign-in only on a real 52pojie page — never on a challenge or
            // error page
            if let host = webView.url?.host, host == "www.52pojie.cn" || host == "52pojie.cn" {
                webView.evaluateJavaScript("window.__wjTrySignIn && window.__wjTrySignIn(false);", completionHandler: nil)
            }
        }
    }
}

// MARK: - Bottom bar (5 buttons: home / sections / sign-in / search / top)
struct BottomBar: View {
    @ObservedObject var model: BrowserModel
    @Binding var showSections: Bool
    @Binding var showSearch: Bool

    var body: some View {
        HStack(spacing: 4) {
            BarButton(icon: "house", label: "首页") { model.goHome() }
            BarButton(icon: "square.grid.2x2", label: "分区") { showSections = true }
            BarButton(icon: "checkmark.seal", label: "签到") { model.manualSignIn() }
            BarButton(icon: "magnifyingglass", label: "搜索") { showSearch = true }
            BarButton(icon: "arrow.up", label: "顶部") { model.backToTop() }
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

// MARK: - Search sheet (in-site search with history)
// Search runs against 52pojie's own search.php (GET form, the standard
// Discuz way). Discuz search usually requires a logged-in session; this
// app keeps the login in the webview cookie jar. History lives in
// localStorage (max 10) and is read back through the JS bridge.
struct SearchSheet: View {
    @ObservedObject var model: BrowserModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var history: [String] = []

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    TextField("搜帖子、搜作者", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .onSubmit { doSearch() }
                    Button("搜索") { doSearch() }
                        .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !history.isEmpty {
                    Text("最近搜索")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], alignment: .leading, spacing: 8) {
                        ForEach(history, id: \.self) { item in
                            Button {
                                query = item
                                doSearch()
                            } label: {
                                Text(item)
                                    .font(.system(size: 14))
                                    .lineLimit(1)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color(.secondarySystemBackground), in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                Text("使用 52pojie 站内搜索（search.php）。站内搜索通常需要登录后才能用；本 App 已保持登录态。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(16)
            .navigationTitle("搜索论坛")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .onAppear {
                model.loadSearchHistory { history = $0 }
            }
        }
        .presentationDetents([.medium])
    }

    private func doSearch() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        model.searchForum(q)
        dismiss()
    }
}
