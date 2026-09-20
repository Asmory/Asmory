(() => {
  const qs = (s) => document.querySelector(s);
  const qsa = (s) => [...document.querySelectorAll(s)];
  const root = document.documentElement;
  const THEME_KEY = 'asmory-theme';
  const icons = {
    light:`<svg class="sun" viewBox="0 0 24 24" aria-hidden="true"><circle cx="12" cy="12" r="4"></circle><path d="M12 2v2M12 20v2M4.93 4.93l1.41 1.41M17.66 17.66l1.41 1.41M2 12h2M20 12h2M4.93 19.07l1.41-1.41M17.66 6.34l1.41-1.41"></path></svg>`,
    dark:`<svg class="moon" viewBox="0 0 24 24" aria-hidden="true"><path d="M20.2 15.3A8.3 8.3 0 0 1 8.7 3.8 8.7 8.7 0 1 0 20.2 15.3Z"></path></svg>`
  };
  const systemTheme=()=>window.matchMedia&&window.matchMedia('(prefers-color-scheme: light)').matches?'light':'dark';
  const effectiveTheme=()=>root.dataset.theme||localStorage.getItem(THEME_KEY)||systemTheme();
  const applyTheme=(theme,persist=true)=>{
    root.dataset.theme=theme;
    if(persist)localStorage.setItem(THEME_KEY,theme);
    const meta=qs('meta[name="theme-color"]');
    if(meta)meta.setAttribute('content',theme==='light'?'#f5f2ea':'#090a0d');
    const toggle=qs('[data-theme-toggle]');
    if(toggle){
      toggle.setAttribute('aria-label',`Switch to ${theme==='light'?'dark':'light'} theme`);
      toggle.setAttribute('title',`Switch to ${theme==='light'?'dark':'light'} theme`);
    }
  };
  const stored=localStorage.getItem(THEME_KEY);
  if(stored==='light'||stored==='dark')root.dataset.theme=stored;
  const nav=qs('.nav');
  if(nav&&!qs('[data-theme-toggle]')){
    const toggle=document.createElement('button');
    toggle.type='button';toggle.className='theme-toggle';toggle.setAttribute('data-theme-toggle','');
    toggle.innerHTML=icons.light+icons.dark;
    const cta=nav.querySelector('.navcta');
    if(cta)nav.insertBefore(toggle,cta);else nav.appendChild(toggle);
    applyTheme(effectiveTheme(),Boolean(stored));
    toggle.addEventListener('click',()=>applyTheme(effectiveTheme()==='light'?'dark':'light',true));
  }
  qsa('[data-copy]').forEach((button)=>{
    button.addEventListener('click',async()=>{
      const value=button.getAttribute('data-copy');
      try{await navigator.clipboard.writeText(value);const old=button.textContent;button.textContent='copied';setTimeout(()=>button.textContent=old,1100)}
      catch(_){button.textContent='copy failed'}
    });
  });
  const list=qs('#package-results');if(!list)return;
  const search=qs('#search'),arch=qs('#arch'),isa=qs('#isa'),sort=qs('#sort'),count=qs('#result-count');
  let packages=[];
  const chip=(v,hot=false)=>`<span class="chip${hot?' hot':''}">${v}</span>`;
  const allTargets=(p)=>p.targets||[];
  const allFeatures=(p)=>allTargets(p).flatMap((t)=>[t.baseline,...(t.required||[])].filter(Boolean));
  const render=()=>{
    const needle=search.value.trim().toLowerCase();
    let rows=packages.filter((p)=>{
      const targets=allTargets(p);
      const haystack=[p.name,p.description,p.license,...(p.owners||[]),...(p.keywords||[]),...(p.categories||[]),...targets.flatMap((t)=>[t.arch,t.os,t.object,t.abi,t.baseline,...(t.required||[])])].join(' ').toLowerCase();
      return(!needle||haystack.includes(needle))&&(!arch.value||targets.some((t)=>t.arch===arch.value))&&(!isa.value||allFeatures(p).includes(isa.value));
    });
    if(sort.value==='downloads')rows.sort((a,b)=>(b.downloads||0)-(a.downloads||0));
    else if(sort.value==='recent')rows.sort((a,b)=>(b.updated||'').localeCompare(a.updated||''));
    else rows.sort((a,b)=>a.name.localeCompare(b.name));
    count.textContent=`${rows.length} project${rows.length===1?'':'s'}`;
    list.innerHTML=rows.length?rows.map((p)=>{
      const t=allTargets(p)[0]||{},features=allFeatures(p);
      const releaseText=`${p.releases||0} release${p.releases===1?'':'s'}`;
      const pullText=p.downloads?`${p.downloads.toLocaleString()} pulls`:releaseText;
      return `<a class="result" href="${p.href||'#'}"><div><div class="result-name">${p.name} <span class="result-version">${p.latest_version||''}</span></div><div class="result-desc">${p.description}</div><div class="result-meta">${(p.owners||[]).join(', ')} · ${t.arch||'multi-arch'} · ${t.abi||'multi-ABI'} · ${p.license}</div></div><div class="result-right"><div class="chips">${features.slice(0,3).map((x,i)=>chip(x,i===0)).join('')}</div><div class="result-meta">${pullText}</div></div></a>`;
    }).join(''):'<div class="empty">No package project matches this query or target filter.</div>';
  };
  fetch('/api/v1/packages').then((r)=>r.json()).then((data)=>{
    packages=data.packages||[];
    [search,arch,isa,sort].forEach((el)=>el.addEventListener(el===search?'input':'change',render));
    render();
  }).catch(()=>{list.innerHTML='<div class="empty">Registry API unavailable.</div>'});
})();
