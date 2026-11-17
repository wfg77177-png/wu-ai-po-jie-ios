import SwiftUI
import WebKit
import Photos
import AVFoundation

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
    // suppress the native long-press callout on thread links so the
    // long-press preview (JS #2 section 15) shows cleanly
    var c = document.createElement('style'); c.id = 'wj-touch-style';
    c.textContent = 'a[href*="thread-"]{-webkit-touch-callout:none;}';
    document.documentElement.appendChild(c);
  }catch(e){}
})();
"""

// MARK: - JS #2: features, injected at document end, main frame only
// Safe features only: sign-in (called from native after real load),
// dark mode, hide ads, keyword filter, hide 悬赏/导读， fullscreen images,
// remember scroll position, section navigation, back to top,
// infinite scroll, read markers, long-post folding, only-OP,
// long-press preview, export helpers (Markdown / TTS text / images).
// No auto-reply / auto-comment. localStorage holds only the sign-in date
// guard, display settings and the read-post list — never any session,
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

  // ---------- 11. Read markers (localStorage list of thread IDs only) ----------
  function wjReadSet(){
    try{ var a=JSON.parse(localStorage.getItem('wj_read')||'[]'); return Array.isArray(a)?a:[]; }catch(e){ return []; }
  }
  function wjThreadId(href){
    if(!href) return null;
    var p = href.split('thread-');
    if(p.length < 2) return null;
    var id = p[1].split('-')[0];
    return (id !== '' && !isNaN(Number(id))) ? id : null;
  }
  function applyRead(){
    var set = wjReadSet();
    if(set.length===0) return;
    var lookup = {};
    set.forEach(function(id){ lookup[id]=true; });
    document.querySelectorAll('a[href*="thread-"]').forEach(function(a){
      var id = wjThreadId(a.getAttribute('href'));
      if(id && lookup[id]){
        var row = a.closest('li, article, div, tr');
        if(row) row.style.opacity='0.45';
      }
    });
  }
  window.__wjClearRead = function(){
    try{ localStorage.removeItem('wj_read'); }catch(e){}
    document.querySelectorAll('a[href*="thread-"]').forEach(function(a){
      var row = a.closest('li, article, div, tr');
      if(row) row.style.opacity='';
    });
    showToast('已读记录已清空');
  };
  document.addEventListener('click', function(e){
    var a = e.target.closest ? e.target.closest('a[href*="thread-"]') : null;
    if(!a) return;
    var id = wjThreadId(a.getAttribute('href'));
    if(!id) return;
    try{
      var set = wjReadSet();
      if(set.indexOf(id)===-1){ set.push(id); if(set.length>500) set=set.slice(-500); localStorage.setItem('wj_read', JSON.stringify(set)); }
    }catch(err){}
  }, true);
  applyRead();
  new MutationObserver(function(){ applyRead(); }).observe(document.documentElement, {childList:true, subtree:true});

  // ---------- 12. Infinite scroll (Discuz list pages only, read-only fetch) ----------
  var wjLoadingNext = false;
  var wjNextUrl = null;
  function wjFindNextUrl(doc){
    var links = doc.querySelectorAll('.pg a, #fd_page_bottom a, .pgs a');
    for(var i=0;i<links.length;i++){
      var t=(links[i].textContent||'').trim();
      if(t.indexOf('下一页')!==-1){ return links[i].getAttribute('href'); }
    }
    return null;
  }
  function wjAppendNextPage(){
    if(wjLoadingNext) return;
    if(!document.querySelector('#threadlist') && !document.querySelector('tbody[id^="normalthread_"]')) return;
    if(!wjNextUrl) wjNextUrl = wjFindNextUrl(document);
    if(!wjNextUrl) return;
    wjLoadingNext = true;
    fetch(wjNextUrl, {credentials:'include'}).then(function(r){ return r.text(); }).then(function(html){
      var doc = new DOMParser().parseFromString(html, 'text/html');
      var rows = doc.querySelectorAll('tbody[id^="normalthread_"]');
      var table = document.querySelector('#threadlist table');
      if(rows.length && table){
        rows.forEach(function(r){ table.appendChild(document.importNode(r, true)); });
      } else {
        var seen = {};
        doc.querySelectorAll('a[href*="thread-"]').forEach(function(a){
          var row = a.closest('li, article, div, tr');
          var href = a.getAttribute('href');
          if(row && href && !seen[href]){
            seen[href]=1;
            var parent = document.querySelector('#threadlist') || document.body;
            parent.appendChild(document.importNode(row, true));
          }
        });
      }
      wjNextUrl = wjFindNextUrl(doc);
      applyRead(); applyKeywords(); foldLongPosts();
      wjLoadingNext = false;
    }).catch(function(){ wjLoadingNext = false; });
  }
  window.addEventListener('scroll', function(){
    if(wjLoadingNext) return;
    if(window.innerHeight + window.scrollY > document.body.scrollHeight - 600) wjAppendNextPage();
  }, {passive:true});

  // ---------- 13. Long-post folding (thread pages) ----------
  function foldLongPosts(){
    document.querySelectorAll('.t_f').forEach(function(el){
      if(el.getAttribute('data-wj-folded')) return;
      var txt = el.textContent || '';
      if(txt.length < 1200) return;
      el.setAttribute('data-wj-folded','1');
      el.style.maxHeight='420px';
      el.style.overflow='hidden';
      var btn=document.createElement('button');
      btn.textContent='展开全文';
      btn.style.cssText='display:block;margin:8px 0;padding:6px 14px;border:1px solid #ccc;border-radius:16px;background:#f5f5f5;font-size:14px;';
      btn.addEventListener('click', function(){
        el.style.maxHeight='none'; el.style.overflow='visible'; btn.remove();
      });
      el.parentNode.insertBefore(btn, el.nextSibling);
    });
  }
  foldLongPosts();

  // ---------- 14. Only OP (thread pages) ----------
  window.__wjOnlyOP = function(){
    var links = document.querySelectorAll('a');
    for(var i=0;i<links.length;i++){
      var t=(links[i].textContent||'').trim();
      if(t.indexOf('只看该作者')!==-1 || t.indexOf('只看楼主')!==-1){ links[i].click(); return true; }
    }
    showToast('本页没有“只看该作者”');
    return false;
  };

  // ---------- 15. Long-press preview on list pages ----------
  var wjPressTimer=null, wjPressTarget=null, wjPressMoved=false, wjSuppressClick=false;
  function wjClosePreview(){ var c=document.getElementById('wj-preview-card'); if(c) c.remove(); }
  function wjShowPreview(title, text){
    wjClosePreview();
    var card=document.createElement('div');
    card.id='wj-preview-card';
    card.style.cssText='position:fixed;left:12px;right:12px;top:18%;max-height:55%;overflow:auto;background:#fff;color:#111;border-radius:14px;box-shadow:0 8px 30px rgba(0,0,0,0.35);padding:16px;z-index:999999;';
    var h=document.createElement('div');
    h.textContent=title; h.style.cssText='font-weight:bold;font-size:16px;margin-bottom:8px;';
    var p=document.createElement('div');
    p.textContent=text; p.style.cssText='font-size:14px;line-height:1.6;white-space:pre-wrap;';
    var b=document.createElement('button');
    b.textContent='关闭'; b.style.cssText='margin-top:12px;padding:6px 16px;border-radius:16px;border:1px solid #ccc;background:#f5f5f5;font-size:14px;';
    b.addEventListener('click', wjClosePreview);
    card.appendChild(h); card.appendChild(p); card.appendChild(b);
    document.body.appendChild(card);
  }
  document.addEventListener('touchstart', function(e){
    var a = e.target.closest ? e.target.closest('a[href*="thread-"]') : null;
    if(!a) return;
    wjPressTarget=a; wjPressMoved=false;
    wjPressTimer=setTimeout(function(){
      if(wjPressMoved || !wjPressTarget) return;
      var href=wjPressTarget.getAttribute('href');
      var title=(wjPressTarget.textContent||'').trim();
      wjSuppressClick=true;
      fetch(href, {credentials:'include'}).then(function(r){ return r.text(); }).then(function(html){
        var doc=new DOMParser().parseFromString(html,'text/html');
        var first=doc.querySelector('.t_f');
        var text=first ? (first.textContent||'').trim().slice(0,400) : '（未能读取预览）';
        wjShowPreview(title, text);
      }).catch(function(){ wjShowPreview(title,'（预览加载失败）'); });
    }, 550);
  }, {passive:true});
  document.addEventListener('touchmove', function(){ wjPressMoved=true; if(wjPressTimer){ clearTimeout(wjPressTimer); wjPressTimer=null; } }, {passive:true});
  document.addEventListener('touchend', function(){ if(wjPressTimer){ clearTimeout(wjPressTimer); wjPressTimer=null; } }, {passive:true});
  document.addEventListener('click', function(e){
    if(wjSuppressClick){
      var a = e.target.closest ? e.target.closest('a[href*="thread-"]') : null;
      if(a){ e.preventDefault(); e.stopPropagation(); }
      wjSuppressClick=false;
    }
    var card=document.getElementById('wj-preview-card');
    if(card && !card.contains(e.target)) wjClosePreview();
  }, true);

  // ---------- 16. Export helpers (called from native; read-only) ----------
  window.__wjExportMarkdown = function(){
    try{
      var titleEl = document.querySelector('#thread_subject') || document.querySelector('h1');
      var title = titleEl ? (titleEl.textContent||'').trim() : document.title;
      var posts = document.querySelectorAll('.t_f');
      var lines = ['# ' + title, ''];
      posts.forEach(function(p, idx){
        var cell = p.closest('td.plc') || p.parentNode;
        var author = '';
        if(cell){
          var a = cell.querySelector('.xw1') || cell.querySelector('.authi a');
          if(a) author = (a.textContent||'').trim();
        }
        lines.push('## ' + (author || ('楼层 ' + (idx+1))));
        lines.push('');
        p.querySelectorAll('img').forEach(function(im){
          var src = im.getAttribute('file') || im.getAttribute('src') || '';
          if(src) lines.push('![](' + src + ')');
        });
        lines.push((p.textContent||'').trim());
        lines.push('');
      });
      return lines.join(String.fromCharCode(10));
    }catch(e){ return null; }
  };
  window.__wjThreadText = function(){
    try{
      var titleEl = document.querySelector('#thread_subject') || document.querySelector('h1');
      var title = titleEl ? (titleEl.textContent||'').trim() : document.title;
      var texts = [];
      document.querySelectorAll('.t_f').forEach(function(p){
        var t=(p.textContent||'').trim();
        if(t) texts.push(t);
      });
      return (title + String.fromCharCode(10) + texts.join(String.fromCharCode(10))).slice(0, 20000);
    }catch(e){ return ''; }
  };
  window.__wjCollectImages = function(){
    try{
      var urls = [];
      document.querySelectorAll('.t_f img').forEach(function(im){
        var src = im.getAttribute('file') || im.getAttribute('src') || '';
        if(!src) return;
        if(src.indexOf('http')!==0){
          if(src.indexOf('/')===0) src = location.origin + src;
          else src = location.href.replace(/[^/]*$/,'') + src;
        }
        if(urls.indexOf(src)===-1) urls.push(src);
      });
      return JSON.stringify(urls.slice(0, 50));
    }catch(e){ return '[]'; }
  };

  // ---------- 17. Re-apply after a real load (called from native didFinish) ----------
  window.__wjReapply = function(){
    applyKeywords();
    applyHideReward();
    applyRead();
    foldLongPosts();
    try{
      var y=parseInt(sessionStorage.getItem('wj_pos_'+location.pathname)||'0',10);
      if(y>200){ setTimeout(function(){ window.scrollTo(0,y); }, 300); }
    }catch(e){}
  };
})();
"""

// MARK: - Model
final class BrowserModel: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    weak var webView: WKWebView?
    @Published var isDark = false
    @Published var fontScale: CGFloat = 1.0
    @Published var hideAds = true
    @Published var hideReward = false
    @Published var keywords = ""
    @Published var canGoBack = false
    @Published var isSpeaking = false
    private let speech = AVSpeechSynthesizer()

    override init() {
        super.init()
        speech.delegate = self
    }

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
    // --- v2 batch A: safe thread tools (read-only or user-triggered) ---
    func onlyOP() {
        webView?.evaluateJavaScript("window.__wjOnlyOP && window.__wjOnlyOP();", completionHandler: nil)
    }
    func clearReadHistory() {
        webView?.evaluateJavaScript("window.__wjClearRead && window.__wjClearRead();", completionHandler: nil)
    }
    func exportMarkdown() {
        webView?.evaluateJavaScript("window.__wjExportMarkdown && window.__wjExportMarkdown();") { result, _ in
            guard let md = result as? String, !md.isEmpty else { return }
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("52pojie-thread.md")
            try? md.write(to: url, atomically: true, encoding: .utf8)
            Self.presentShare([url])
        }
    }
    func exportPDF() {
        guard let webView = webView else { return }
        webView.createPDF { result in
            switch result {
            case .success(let data):
                let url = FileManager.default.temporaryDirectory.appendingPathComponent("52pojie-thread.pdf")
                try? data.write(to: url)
                Self.presentShare([url])
            case .failure:
                break
            }
        }
    }
    func savePageImages() {
        webView?.evaluateJavaScript("window.__wjCollectImages && window.__wjCollectImages();") { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let urls = try? JSONDecoder().decode([String].self, from: data),
                  !urls.isEmpty else {
                self.webView?.evaluateJavaScript("window.__wjToast && window.__wjToast('本页没有可保存的图片');", completionHandler: nil)
                return
            }
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
                guard status == .authorized || status == .limited else {
                    DispatchQueue.main.async {
                        self.webView?.evaluateJavaScript("window.__wjToast && window.__wjToast('请在设置中允许访问相册');", completionHandler: nil)
                    }
                    return
                }
                self.downloadAndSaveImages(urls)
            }
        }
    }
    private func downloadAndSaveImages(_ urls: [String]) {
        DispatchQueue(label: "wj.saveImages").async {
            var saved = 0
            for u in urls {
                guard let url = URL(string: u) else { continue }
                let sem = DispatchSemaphore(value: 0)
                URLSession.shared.dataTask(with: url) { data, _, _ in
                    defer { sem.signal() }
                    guard let data = data, let image = UIImage(data: data) else { return }
                    do {
                        try PHPhotoLibrary.shared().performChangesAndWait {
                            PHAssetChangeRequest.creationRequestForAsset(from: image)
                        }
                        saved += 1
                    } catch { }
                }.resume()
                sem.wait()
            }
            DispatchQueue.main.async {
                self.webView?.evaluateJavaScript("window.__wjToast && window.__wjToast('已保存 \(saved) 张图片到相册');", completionHandler: nil)
            }
        }
    }
    func toggleSpeech() {
        if isSpeaking {
            speech.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        webView?.evaluateJavaScript("window.__wjThreadText && window.__wjThreadText();") { result, _ in
            guard let text = result as? String, !text.isEmpty else { return }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = AVSpeechSynthesisVoice(language: "zh-CN")
            utterance.rate = 0.5
            self.speech.speak(utterance)
            self.isSpeaking = true
        }
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        isSpeaking = false
    }
    static func presentShare(_ items: [Any]) {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController else { return }
        let vc = UIActivityViewController(activityItems: items, applicationActivities: nil)
        if let pop = vc.popoverPresentationController {
            pop.sourceView = root.view
            pop.sourceRect = CGRect(x: root.view.bounds.midX, y: root.view.bounds.midY, width: 0, height: 0)
            pop.permittedArrowDirections = []
        }
        root.present(vc, animated: true)
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
            Menu {
                Button("只看楼主") { model.onlyOP() }
                Button("导出 Markdown") { model.exportMarkdown() }
                Button("导出 PDF") { model.exportPDF() }
                Button("保存本页图片") { model.savePageImages() }
                Button(model.isSpeaking ? "停止朗读" : "朗读帖子") { model.toggleSpeech() }
            } label: {
                VStack(spacing: 3) {
                    Image(systemName: "ellipsis.circle")
                        .font(.system(size: 19, weight: .medium))
                    Text("更多")
                        .font(.system(size: 10.5, weight: .medium))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.primary)
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
                Section("已读记录") {
                    Button("清空已读记录") { model.clearReadHistory() }
                    Text("点过的帖子会变暗，方便区分。")
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
