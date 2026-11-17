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
// long-press preview, export helpers (Markdown / TTS text / images),
// Batch B: user notes + blacklist, keyword highlight, reply templates
// (insert only), code copy + highlight, search history, share info,
// in-page bilingual translation (user-triggered only).
// No auto-reply / auto-comment. localStorage holds only the sign-in date
// guard, display settings, read list, notes, blacklist, keywords,
// highlight words, search history and translation config — never any
// session, token or credential.
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
      applyNotesBlacklist(); applyHighlight(); applyCodeBlocks();
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

  // ---------- 18. User notes + blacklist (settings-driven, read-only) ----------
  // Notes: {username: note} — a small yellow badge next to the username on
  // thread pages. Blacklist: [username] — their rows on list pages and
  // their posts on thread pages are hidden. Both live in localStorage
  // only; never any session/token/credential.
  function wjNotesObj(){
    try{ var o=JSON.parse(localStorage.getItem('wj_notes')||'{}'); return (o && typeof o==='object')?o:{}; }catch(e){ return {}; }
  }
  function wjBlacklist(){
    try{ var a=JSON.parse(localStorage.getItem('wj_blacklist')||'[]'); return Array.isArray(a)?a:[]; }catch(e){ return []; }
  }
  function applyNotesBlacklist(){
    var notes = wjNotesObj();
    var bl = wjBlacklist();
    var blLookup = {};
    bl.forEach(function(u){ blLookup[u]=true; });
    document.querySelectorAll('[data-wj-bl]').forEach(function(el){ el.style.display=''; el.removeAttribute('data-wj-bl'); });
    document.querySelectorAll('.authi a, .pls .xw1, .authi .xw1').forEach(function(a){
      var name=(a.textContent||'').trim();
      if(!name) return;
      var old = a.parentNode.querySelector('.wj-note-badge');
      if(old) old.remove();
      if(notes[name]){
        var b=document.createElement('span');
        b.className='wj-note-badge';
        b.textContent=' ' + notes[name];
        b.style.cssText='background:#fff3b0;color:#7a5c00;font-size:12px;padding:1px 6px;border-radius:8px;margin-left:4px;';
        a.parentNode.insertBefore(b, a.nextSibling);
      }
      if(blLookup[name]){
        var post = a.closest('div[id^="post_"]') || a.closest('table') || a.closest('tr');
        if(post){ post.style.display='none'; post.setAttribute('data-wj-bl','1'); }
      }
    });
    document.querySelectorAll('tbody[id^="normalthread_"]').forEach(function(row){
      var author = row.querySelector('.by cite a') || row.querySelector('td.by a');
      if(author && blLookup[(author.textContent||'').trim()]){ row.style.display='none'; row.setAttribute('data-wj-bl','1'); }
    });
  }
  window.__wjSetNotes = function(json){ try{ localStorage.setItem('wj_notes', json); }catch(e){} applyNotesBlacklist(); };
  window.__wjSetBlacklist = function(json){ try{ localStorage.setItem('wj_blacklist', json); }catch(e){} applyNotesBlacklist(); };
  window.__wjApplyNotesBlacklist = applyNotesBlacklist;
  applyNotesBlacklist();

  // ---------- 19. Keyword highlight (separate group from the filter) ----------
  function wjHlWords(){
    var csv=''; try{ csv=localStorage.getItem('wj_hlwords')||''; }catch(e){}
    return csv.split(',').map(function(s){ return s.trim(); }).filter(function(s){ return s.length>0; });
  }
  function wjHighlightNode(node, words){
    var text=node.nodeValue;
    if(!text) return;
    var lower=text.toLowerCase();
    var best=-1, bestWord='';
    words.forEach(function(w){
      var i=lower.indexOf(w.toLowerCase());
      if(i!==-1 && (best===-1 || i<best)){ best=i; bestWord=w; }
    });
    if(best===-1) return;
    var before=document.createTextNode(text.slice(0,best));
    var mark=document.createElement('span');
    mark.className='wj-hl';
    mark.style.cssText='background:#ffeb3b;color:#111;border-radius:2px;';
    mark.textContent=text.slice(best, best+bestWord.length);
    var after=document.createTextNode(text.slice(best+bestWord.length));
    var parent=node.parentNode;
    parent.insertBefore(before, node);
    parent.insertBefore(mark, node);
    parent.insertBefore(after, node);
    parent.removeChild(node);
    if(after.nodeValue) wjHighlightNode(after, words);
  }
  function applyHighlight(){
    var words=wjHlWords();
    if(words.length===0) return;
    var targets=document.querySelectorAll('a[href*="thread-"], .by cite a, td.by a');
    targets.forEach(function(a){
      var walker=document.createTreeWalker(a, NodeFilter.SHOW_TEXT, null);
      var nodes=[];
      while(walker.nextNode()) nodes.push(walker.currentNode);
      nodes.forEach(function(n){
        if(n.parentNode && n.parentNode.classList && n.parentNode.classList.contains('wj-hl')) return;
        wjHighlightNode(n, words);
      });
    });
  }
  window.__wjSetHighlight = function(csv){
    try{ localStorage.setItem('wj_hlwords', csv||''); }catch(e){}
    document.querySelectorAll('.wj-hl').forEach(function(s){
      var p=s.parentNode; if(!p) return;
      p.replaceChild(document.createTextNode(s.textContent), s); p.normalize();
    });
    applyHighlight();
  };
  window.__wjApplyHighlight = applyHighlight;
  applyHighlight();

  // ---------- 20. Quick reply templates (insert into reply box ONLY) ----------
  // The reply-box selector is a best-effort fallback chain. It could NOT be
  // verified against the real logged-in reply form (no logged-in HTML was
  // available when this was written); if tapping a template does nothing
  // while logged in, the selector chain needs to be adjusted to the live
  // page. Nothing is ever submitted automatically — the user taps publish.
  window.__wjInsertTemplate = function(text){
    var box = document.querySelector('#reply_content')
      || document.querySelector('textarea[name="content"]')
      || document.querySelector('form textarea')
      || document.querySelector('textarea');
    if(!box){ showToast('没找到回复框，请先打开回帖框'); return false; }
    try{
      var setter = Object.getOwnPropertyDescriptor(window.HTMLTextAreaElement.prototype, 'value').set;
      setter.call(box, (box.value ? box.value + String.fromCharCode(10) : '') + text);
      box.dispatchEvent(new Event('input', {bubbles:true}));
      box.focus();
      box.scrollIntoView({behavior:'smooth', block:'center'});
      showToast('模板已插入，检查后自己点发表');
      return true;
    }catch(e){ return false; }
  };

  // ---------- 21. Code block copy + basic highlight ----------
  function wjHighlightCode(el){
    if(el.getAttribute('data-wj-code')) return;
    el.setAttribute('data-wj-code','1');
    var code=el.textContent||'';
    var esc=code.replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;');
    var re=/("(?:[^"]*)"|'(?:[^']*)')|(\\/\\/.*)|([/][*][^]*?[*][/])|(^|[^A-Za-z0-9_])(function|var|let|const|if|else|for|while|return|class|import|export|from|new|try|catch|public|private|static|void|int|char|def|print|break|continue|switch|case|do|this|self|nil|null|true|false)(?![A-Za-z0-9_])|(^|[^A-Za-z0-9_])([0-9]+(?:[.][0-9]+)?)/g;
    var html=esc.replace(re, function(m, str, lineCom, blkCom, kwPre, kw, numPre, num){
      if(str!==undefined) return '<span style="color:#a31515">'+m+'</span>';
      if(lineCom!==undefined) return '<span style="color:#6a9955">'+m+'</span>';
      if(blkCom!==undefined) return '<span style="color:#6a9955">'+m+'</span>';
      if(kw!==undefined) return kwPre+'<span style="color:#0000ff">'+kw+'</span>';
      if(num!==undefined) return numPre+'<span style="color:#098658">'+num+'</span>';
      return m;
    });
    el.innerHTML=html;
    var btn=document.createElement('button');
    btn.textContent='复制';
    btn.style.cssText='position:absolute;top:6px;right:6px;padding:3px 10px;font-size:12px;border:1px solid #ccc;border-radius:12px;background:#fff;';
    btn.addEventListener('click', function(ev){
      ev.stopPropagation();
      var t=el.textContent||'';
      function done(){ showToast('代码已复制'); }
      if(navigator.clipboard && navigator.clipboard.writeText){ navigator.clipboard.writeText(t).then(done, function(){ showToast('复制失败'); }); }
      else {
        var ta=document.createElement('textarea'); ta.value=t; document.body.appendChild(ta); ta.select();
        try{ document.execCommand('copy'); done(); }catch(e){ showToast('复制失败'); }
        ta.remove();
      }
    });
    var cs=getComputedStyle(el);
    if(cs.position==='static') el.style.position='relative';
    el.appendChild(btn);
  }
  function applyCodeBlocks(){
    document.querySelectorAll('pre').forEach(function(p){ wjHighlightCode(p); });
  }
  window.__wjApplyCodeBlocks = applyCodeBlocks;
  applyCodeBlocks();

  // ---------- 22. In-site search history (localStorage, max 10) ----------
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

  // ---------- 23. In-page bilingual translation (user-triggered only) ----------
  // Default: free MyMemory, no key, 450 bytes per request, page cap 2500
  // chars. Optional BYOK: OpenAI-compatible /chat/completions (default
  // OpenRouter deepseek-chat), page cap 8000 chars. The API is called ONLY
  // when the user taps translate; nothing is translated automatically.
  function wjTransCfg(){
    try{
      var c=JSON.parse(localStorage.getItem('wj_transCfg')||'{}');
      return { key:(c.key||'').trim(), base:(c.base||'https://openrouter.ai/api/v1').replace(/\\/+$/,''), model:(c.model||'deepseek/deepseek-chat').trim() };
    }catch(e){ return { key:'', base:'https://openrouter.ai/api/v1', model:'deepseek/deepseek-chat' }; }
  }
  window.__wjSetTransCfg = function(json){ try{ localStorage.setItem('wj_transCfg', json); }catch(e){} };
  function wjIsChinese(s){ return /[一-鿿]/.test(s); }
  function wjByteLen(s){ try{ return new TextEncoder().encode(s).length; }catch(e){ return s.length; } }
  function wjSplitChunks(text, maxBytes){
    var chunks=[];
    var lines=text.split(String.fromCharCode(10));
    var cur='';
    function pushCur(){ if(cur){ chunks.push(cur); cur=''; } }
    lines.forEach(function(line){
      if(!line.trim()){ return; }
      if(wjByteLen(line) > maxBytes){
        pushCur();
        var part='';
        for(var i=0;i<line.length;i++){
          var cand=part+line[i];
          if(wjByteLen(cand) > maxBytes){ chunks.push(part); part=line[i]; }
          else part=cand;
        }
        if(part) chunks.push(part);
        return;
      }
      var cand = cur ? cur + String.fromCharCode(10) + line : line;
      if(wjByteLen(cand) > maxBytes){ pushCur(); cur=line; }
      else cur=cand;
    });
    pushCur();
    return chunks;
  }
  function wjTranslateMyMemory(text, fromZh){
    var pair = fromZh ? 'zh-CN|en-US' : 'en-US|zh-CN';
    var url='https://api.mymemory.translated.net/get?q='+encodeURIComponent(text)+'&langpair='+pair;
    return fetch(url).then(function(r){ return r.json(); }).then(function(j){
      if(j.responseStatus && j.responseStatus!==200) throw new Error('MyMemory '+j.responseStatus);
      var t=(j.responseData && j.responseData.translatedText) || '';
      if(!t || t==='QUERY LENGTH LIMIT EXCEEDED') throw new Error('MyMemory limit');
      return t;
    });
  }
  function wjTranslateBYOK(text, fromZh, cfg){
    var target = fromZh ? 'English' : 'Chinese (Simplified)';
    return fetch(cfg.base + '/chat/completions', {
      method:'POST',
      headers:{ 'Content-Type':'application/json', 'Authorization':'Bearer '+cfg.key },
      body: JSON.stringify({ model: cfg.model, temperature: 0.3, messages: [
        { role:'system', content:'You are a translator. Translate the user text into '+target+'. Output ONLY the translation, no explanations, keep line breaks.' },
        { role:'user', content: text }
      ]})
    }).then(function(r){ return r.json(); }).then(function(j){
      if(j.error) throw new Error(j.error.message || 'BYOK error');
      var c=j.choices && j.choices[0] && j.choices[0].message && j.choices[0].message.content;
      if(!c) throw new Error('BYOK empty');
      return c.trim();
    });
  }
  function wjTranslateChunk(text, fromZh){
    var cfg=wjTransCfg();
    if(cfg.key) return wjTranslateBYOK(text, fromZh, cfg);
    return wjTranslateMyMemory(text, fromZh);
  }
  function wjShowTransPanel(title){
    var old=document.getElementById('wj-trans-panel');
    if(old) old.remove();
    var ov=document.createElement('div');
    ov.id='wj-trans-panel';
    ov.style.cssText='position:fixed;left:10px;right:10px;top:12%;max-height:70%;overflow:auto;background:#fff;color:#111;border-radius:14px;box-shadow:0 8px 30px rgba(0,0,0,0.35);padding:16px;z-index:999999;';
    var h=document.createElement('div');
    h.textContent=title; h.style.cssText='font-weight:bold;font-size:16px;margin-bottom:10px;';
    var b=document.createElement('button');
    b.textContent='关闭'; b.style.cssText='float:right;padding:4px 14px;border-radius:14px;border:1px solid #ccc;background:#f5f5f5;font-size:14px;';
    b.addEventListener('click', function(){ ov.remove(); });
    h.appendChild(b);
    var body=document.createElement('div');
    body.id='wj-trans-body';
    ov.appendChild(h); ov.appendChild(body);
    document.body.appendChild(ov);
    return body;
  }
  function wjAddTransPair(body, orig, trans){
    var o=document.createElement('div');
    o.textContent=orig; o.style.cssText='font-size:14px;line-height:1.6;color:#333;margin-bottom:2px;white-space:pre-wrap;';
    var t=document.createElement('div');
    t.textContent=trans; t.style.cssText='font-size:14px;line-height:1.6;color:#2563eb;margin-bottom:14px;white-space:pre-wrap;';
    body.appendChild(o); body.appendChild(t);
  }
  window.__wjTranslateSelection = function(){
    var sel='';
    try{ sel=(window.getSelection()||'').toString().trim(); }catch(e){}
    if(!sel){ showToast('请先选中要翻译的文字'); return; }
    var fromZh=wjIsChinese(sel);
    var body=wjShowTransPanel('选中文字翻译');
    var chunks=wjSplitChunks(sel, 450);
    var chain=Promise.resolve();
    chunks.forEach(function(c){
      chain=chain.then(function(){ return wjTranslateChunk(c, fromZh); }).then(function(t){ wjAddTransPair(body, c, t); }).catch(function(){ wjAddTransPair(body, c, '（翻译失败）'); });
    });
  };
  window.__wjTranslatePage = function(){
    var cfg=wjTransCfg();
    var cap = cfg.key ? 8000 : 2500;
    var titleEl=document.querySelector('#thread_subject') || document.querySelector('h1');
    var title=titleEl ? (titleEl.textContent||'').trim() : document.title;
    var texts=[];
    document.querySelectorAll('.t_f').forEach(function(p){
      var t=(p.textContent||'').trim();
      if(t) texts.push(t);
    });
    var all=(title+String.fromCharCode(10)+texts.join(String.fromCharCode(10))).slice(0, cap);
    if(!all.trim()){ showToast('本页没有可翻译的正文'); return; }
    var fromZh=wjIsChinese(all);
    var body=wjShowTransPanel('本页翻译（原文在上，译文在下）');
    var maxBytes = cfg.key ? 2000 : 450;
    var chunks=wjSplitChunks(all, maxBytes);
    var chain=Promise.resolve();
    chunks.forEach(function(c){
      chain=chain.then(function(){ return wjTranslateChunk(c, fromZh); }).then(function(t){ wjAddTransPair(body, c, t); }).catch(function(){ wjAddTransPair(body, c, '（翻译失败）'); });
    });
  };

  // ---------- 24. Share info (title + URL, native share sheet) ----------
  window.__wjShareInfo = function(){
    try{
      var titleEl=document.querySelector('#thread_subject') || document.querySelector('h1');
      var title=titleEl ? (titleEl.textContent||'').trim() : document.title;
      return JSON.stringify({ title: title, url: location.href });
    }catch(e){ return JSON.stringify({ title: document.title, url: location.href }); }
  };

  // ---------- 25. Batch B re-apply (one observer for notes/blacklist/highlight/code) ----------
  new MutationObserver(function(){ applyNotesBlacklist(); applyHighlight(); applyCodeBlocks(); }).observe(document.documentElement, {childList:true, subtree:true});

  // ---------- 17. Re-apply after a real load (called from native didFinish) ----------
  window.__wjReapply = function(){
    applyKeywords();
    applyHideReward();
    applyRead();
    foldLongPosts();
    applyNotesBlacklist();
    applyHighlight();
    applyCodeBlocks();
    try{
      var y=parseInt(sessionStorage.getItem('wj_pos_'+location.pathname)||'0',10);
      if(y>200){ setTimeout(function(){ window.scrollTo(0,y); }, 300); }
    }catch(e){}
  };
})();
"""

// MARK: - Reply template group (Batch B; id excluded from Codable so
// hand-edited or older JSON without an id still decodes)
struct ReplyTemplateGroup: Codable, Identifiable {
    var id = UUID()
    var group: String
    var items: [String]

    enum CodingKeys: String, CodingKey { case group, items }
}

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
    // --- v2 batch B: user-managed data (UserDefaults mirrors; the page
    // itself reads the same values from localStorage) ---
    @Published var notes: [String: String] = [:]
    @Published var blacklist: [String] = []
    @Published var highlightWords = ""
    @Published var templates: [ReplyTemplateGroup] = [ReplyTemplateGroup(group: "常用", items: ["感谢分享！", "学习了，谢谢楼主", "已收藏，谢谢分享"])]
    @Published var transKey = ""
    @Published var transBase = "https://openrouter.ai/api/v1"
    @Published var transModel = "deepseek/deepseek-chat"
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
    // --- v2 batch B: notes / blacklist / highlight / templates / search / share / translate ---
    // All user-triggered or read-only. No auto-reply, no auto-comment.
    private func jsString(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
    }
    private func jsonString<T: Encodable>(_ v: T) -> String {
        (try? String(data: JSONEncoder().encode(v), encoding: .utf8)) ?? "null"
    }
    func toast(_ msg: String) {
        webView?.evaluateJavaScript("window.__wjToast && window.__wjToast('\(jsString(msg))');", completionHandler: nil)
    }
    func setNotes(_ n: [String: String]) {
        notes = n
        UserDefaults.standard.set(jsonString(n), forKey: "wj_notes")
        webView?.evaluateJavaScript("window.__wjSetNotes && window.__wjSetNotes('\(jsString(jsonString(n)))');", completionHandler: nil)
    }
    func setBlacklist(_ b: [String]) {
        blacklist = b
        UserDefaults.standard.set(jsonString(b), forKey: "wj_blacklist")
        webView?.evaluateJavaScript("window.__wjSetBlacklist && window.__wjSetBlacklist('\(jsString(jsonString(b)))');", completionHandler: nil)
    }
    func setHighlightWords(_ s: String) {
        highlightWords = s
        UserDefaults.standard.set(s, forKey: "wj_highlightWords")
        webView?.evaluateJavaScript("window.__wjSetHighlight && window.__wjSetHighlight('\(jsString(s))');", completionHandler: nil)
    }
    func setTemplates(_ t: [ReplyTemplateGroup]) {
        templates = t
        UserDefaults.standard.set(jsonString(t), forKey: "wj_templates")
    }
    func setTransCfg(key: String, base: String, model: String) {
        transKey = key; transBase = base; transModel = model
        let cfg = ["key": key, "base": base, "model": model]
        UserDefaults.standard.set(jsonString(cfg), forKey: "wj_transCfg")
        webView?.evaluateJavaScript("window.__wjSetTransCfg && window.__wjSetTransCfg('\(jsString(jsonString(cfg)))');", completionHandler: nil)
    }
    func insertTemplate(_ text: String) {
        webView?.evaluateJavaScript("window.__wjInsertTemplate && window.__wjInsertTemplate('\(jsString(text))');", completionHandler: nil)
    }
    func shareCurrent() {
        webView?.evaluateJavaScript("window.__wjShareInfo && window.__wjShareInfo();") { result, _ in
            guard let json = result as? String,
                  let data = json.data(using: .utf8),
                  let info = try? JSONDecoder().decode([String: String].self, from: data),
                  let urlString = info["url"], let url = URL(string: urlString) else { return }
            var items: [Any] = [url]
            if let title = info["title"], !title.isEmpty { items.insert(title, at: 0) }
            Self.presentShare(items)
        }
    }
    func translateSelection() {
        webView?.evaluateJavaScript("window.__wjTranslateSelection && window.__wjTranslateSelection();", completionHandler: nil)
    }
    func translatePage() {
        webView?.evaluateJavaScript("window.__wjTranslatePage && window.__wjTranslatePage();", completionHandler: nil)
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
    @State private var showSearch = false

    var body: some View {
        ZStack(alignment: .bottom) {
            WebView(model: model)
                .ignoresSafeArea(edges: .top)
            BottomBar(model: model, showSections: $showSections, showSettings: $showSettings, showSearch: $showSearch)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
        }
        .sheet(isPresented: $showSections) { SectionSheet(model: model) }
        .sheet(isPresented: $showSettings) { SettingsSheet(model: model) }
        .sheet(isPresented: $showSearch) { SearchSheet(model: model) }
        .onAppear {
            model.isDark = UserDefaults.standard.bool(forKey: "wj_dark")
            model.hideAds = UserDefaults.standard.object(forKey: "wj_hideAds") as? Bool ?? true
            model.hideReward = UserDefaults.standard.bool(forKey: "wj_hideReward")
            model.keywords = UserDefaults.standard.string(forKey: "wj_keywords") ?? ""
            let fs = UserDefaults.standard.double(forKey: "wj_fontScale")
            if fs > 0 { model.fontScale = CGFloat(fs) }
            // Batch B persisted values (UserDefaults mirrors of localStorage)
            if let s = UserDefaults.standard.string(forKey: "wj_notes"),
               let d = s.data(using: .utf8),
               let n = try? JSONDecoder().decode([String: String].self, from: d) { model.notes = n }
            if let s = UserDefaults.standard.string(forKey: "wj_blacklist"),
               let d = s.data(using: .utf8),
               let b = try? JSONDecoder().decode([String].self, from: d) { model.blacklist = b }
            model.highlightWords = UserDefaults.standard.string(forKey: "wj_highlightWords") ?? ""
            if let s = UserDefaults.standard.string(forKey: "wj_templates"),
               let d = s.data(using: .utf8),
               let t = try? JSONDecoder().decode([ReplyTemplateGroup].self, from: d) { model.templates = t }
            if let s = UserDefaults.standard.string(forKey: "wj_transCfg"),
               let d = s.data(using: .utf8),
               let c = try? JSONDecoder().decode([String: String].self, from: d) {
                model.transKey = c["key"] ?? ""
                model.transBase = c["base"] ?? "https://openrouter.ai/api/v1"
                model.transModel = c["model"] ?? "deepseek/deepseek-chat"
            }
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
    @Binding var showSearch: Bool

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
                Divider()
                Button("搜索论坛") { showSearch = true }
                Menu("插入回复模板") {
                    ForEach(model.templates) { group in
                        Menu(group.group) {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                Button(item) { model.insertTemplate(item) }
                            }
                        }
                    }
                }
                Button("翻译选中文字") { model.translateSelection() }
                Button("翻译本页") { model.translatePage() }
                Button("分享帖子") { model.shareCurrent() }
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
    @State private var highlightText = ""
    @State private var importText = ""
    @State private var noteUser = ""
    @State private var noteText = ""
    @State private var blacklistUser = ""
    @State private var templateGroup = "常用"
    @State private var templateText = ""
    @State private var transKeyText = ""
    @State private var transBaseText = ""
    @State private var transModelText = ""

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
                Section("用户备注") {
                    ForEach(Array(model.notes.keys.sorted()), id: \.self) { user in
                        HStack {
                            Text(user).fontWeight(.medium)
                            Text(model.notes[user] ?? "")
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .onDelete { offsets in
                        var n = model.notes
                        let keys = n.keys.sorted()
                        for i in offsets { n.removeValue(forKey: keys[i]) }
                        model.setNotes(n)
                    }
                    TextField("用户名", text: $noteUser)
                    TextField("备注（显示在用户名旁的小黄条）", text: $noteText)
                    Button("添加备注") {
                        let u = noteUser.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !u.isEmpty, !noteText.isEmpty else { return }
                        var n = model.notes
                        n[u] = noteText
                        model.setNotes(n)
                        noteUser = ""; noteText = ""
                    }
                    .disabled(noteUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || noteText.isEmpty)
                }
                Section("黑名单") {
                    ForEach(model.blacklist, id: \.self) { user in
                        Text(user)
                    }
                    .onDelete { offsets in
                        var b = model.blacklist
                        b.remove(atOffsets: offsets)
                        model.setBlacklist(b)
                    }
                    TextField("用户名", text: $blacklistUser)
                    Button("加入黑名单") {
                        let u = blacklistUser.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !u.isEmpty, !model.blacklist.contains(u) else { return }
                        model.setBlacklist(model.blacklist + [u])
                        blacklistUser = ""
                    }
                    .disabled(blacklistUser.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("黑名单用户在列表页和帖子页都会被隐藏。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("关键词高亮") {
                    TextField("多个高亮词用英文逗号隔开", text: $highlightText)
                        .onChange(of: highlightText) { model.setHighlightWords($0) }
                    Text("命中高亮词的帖子标题和用户名会标黄。和屏蔽关键词是分开的两组。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    Button("复制导出高亮词") {
                        UIPasteboard.general.string = model.highlightWords
                        model.toast("高亮词已复制到剪贴板")
                    }
                    TextField("粘贴导入（逗号隔开）", text: $importText)
                    Button("导入高亮词") {
                        guard !importText.isEmpty else { return }
                        highlightText = importText
                        model.setHighlightWords(importText)
                        importText = ""
                    }
                    .disabled(importText.isEmpty)
                }
                Section("快捷回复模板") {
                    ForEach(Array(model.templates.enumerated()), id: \.element.id) { idx, group in
                        Section(group.group) {
                            ForEach(Array(group.items.enumerated()), id: \.offset) { _, item in
                                Text(item)
                            }
                            .onDelete { offsets in
                                var t = model.templates
                                t[idx].items.remove(atOffsets: offsets)
                                model.setTemplates(t)
                            }
                        }
                    }
                    TextField("分组（默认“常用”）", text: $templateGroup)
                    TextField("模板文字", text: $templateText)
                    Button("添加模板") {
                        let t = templateText.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !t.isEmpty else { return }
                        let g = templateGroup.trimmingCharacters(in: .whitespacesAndNewlines)
                        var groups = model.templates
                        if let i = groups.firstIndex(where: { $0.group == (g.isEmpty ? "常用" : g) }) {
                            if !groups[i].items.contains(t) { groups[i].items.append(t) }
                        } else {
                            groups.append(ReplyTemplateGroup(group: g.isEmpty ? "常用" : g, items: [t]))
                        }
                        model.setTemplates(groups)
                        templateText = ""
                    }
                    .disabled(templateText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    Text("点模板只会插进回复框，发表必须自己点。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("页内翻译") {
                    SecureField("API Key（可空）", text: $transKeyText)
                        .onChange(of: transKeyText) { model.setTransCfg(key: $0, base: model.transBase, model: model.transModel) }
                    TextField("Base URL", text: $transBaseText)
                        .onChange(of: transBaseText) { model.setTransCfg(key: model.transKey, base: $0, model: model.transModel) }
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    TextField("模型", text: $transModelText)
                        .onChange(of: transModelText) { model.setTransCfg(key: model.transKey, base: model.transBase, model: $0) }
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                    Text("不填 Key 时用免费 MyMemory（整页上限 2500 字）；填 Key 后走 OpenAI 兼容接口（默认 OpenRouter deepseek-chat，整页上限 8000 字）。只在点翻译时才调接口。")
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
            .onAppear {
                keywordsText = model.keywords
                highlightText = model.highlightWords
                transKeyText = model.transKey
                transBaseText = model.transBase
                transModelText = model.transModel
            }
        }
        .presentationDetents([.medium, .large])
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
