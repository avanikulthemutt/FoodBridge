/* FoodBridge UI effects: animations only, no app logic */
(function(){
  const reduce=matchMedia('(prefers-reduced-motion: reduce)').matches;

  // sticky header shadow
  const bar=document.getElementById('topbar');
  const onScroll=()=>bar&&bar.classList.toggle('scrolled',scrollY>8);
  addEventListener('scroll',onScroll,{passive:true});onScroll();

  // scroll reveal
  const io='IntersectionObserver' in window?new IntersectionObserver(es=>es.forEach(e=>{if(e.isIntersecting){e.target.classList.add('in');io.unobserve(e.target)}}),{threshold:.12}):null;
  document.querySelectorAll('.reveal').forEach(el=>io?io.observe(el):el.classList.add('in'));

  // auth tabs
  const seg=document.getElementById('seg');
  function tab(name){
    if(!seg)return;
    seg.querySelectorAll('button').forEach(b=>b.classList.toggle('on',b.dataset.tab===name));
    seg.classList.toggle('right',name==='register');
    const l=document.getElementById('login'),r=document.getElementById('register');
    if(!l||!r)return;
    l.hidden=name!=='login';r.hidden=name!=='register';
    (name==='login'?l:r).classList.remove('swap');void (name==='login'?l:r).offsetWidth;(name==='login'?l:r).classList.add('swap');
  }
  seg&&seg.addEventListener('click',e=>{const b=e.target.closest('[data-tab]');if(b)tab(b.dataset.tab)});
  document.querySelectorAll('[data-auth]').forEach(a=>a.addEventListener('click',()=>tab(a.dataset.auth)));
  document.documentElement.style.scrollBehavior='smooth';

  // count-up numbers
  function countUp(el){
    const raw=el.textContent.trim();
    const m=raw.match(/^(-?[\d,]*\.?\d+)(%?)$/);
    if(!m||reduce)return;
    const hasComma=raw.includes(','),dec=(m[1].split('.')[1]||'').length,end=parseFloat(m[1].replace(/,/g,'')),suf=m[2];
    const t0=performance.now(),dur=900;
    (function f(t){
      const p=Math.min(1,(t-t0)/dur),e=1-Math.pow(1-p,3),v=end*e;
      let s=v.toFixed(dec);if(hasComma)s=Number(s).toLocaleString(undefined,{minimumFractionDigits:dec,maximumFractionDigits:dec});
      el.textContent=s+suf;if(p<1)requestAnimationFrame(f);
    })(t0);
  }
  document.querySelectorAll('[data-count]').forEach(countUp);

  // animate dynamic content rendered by app.js
  function enhance(root){
    root.querySelectorAll('.metric b:not([data-fx])').forEach(b=>{b.dataset.fx=1;countUp(b)});
    root.querySelectorAll('.cards .metric:not([data-fx])').forEach((m,i)=>{m.dataset.fx=1;m.style.setProperty('--i',i)});
    root.querySelectorAll('.content > .panel:not([data-fx]), .content > .notice:not([data-fx]), .content > .cards:not([data-fx])').forEach((p,i)=>{p.dataset.fx=1;p.style.setProperty('--i',Math.min(i,8))});
  }
  const app=document.getElementById('app');
  if(app){
    let q=false;
    new MutationObserver(()=>{if(q)return;q=true;requestAnimationFrame(()=>{q=false;enhance(app)})}).observe(app,{childList:true,subtree:true});
    enhance(app);
  }
})();
