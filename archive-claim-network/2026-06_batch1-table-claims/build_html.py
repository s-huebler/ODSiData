import json
data=json.load(open("graph_data.json"))
elements_js=json.dumps(data,separators=(",",":"))

HTML=r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GVHD Microbiome Claims &amp; Evidence Network</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.30.2/cytoscape.min.js"></script>
<style>
  :root{
    --claim:#bfdbfe;          /* claim node fill (light blue) */
    --paper:#f59e0b;          /* primary paper fill (amber) */
    --review:#fcd34d;         /* review paper fill (gold) */
    --fav:#16a34a;            /* favourable */
    --unfav:#dc2626;          /* unfavourable */
    --ctx:#64748b;            /* context/other */
    --bg:#ffffff; --panel:#f1f5f9; --ink:#0f172a; --muted:#64748b; --line:#cbd5e1;
  }
  *{box-sizing:border-box}
  html,body{margin:0;height:100%;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--ink)}
  #app{display:flex;flex-direction:column;height:100vh}
  header{padding:12px 18px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:14px;align-items:center}
  header h1{font-size:17px;margin:0;font-weight:600;letter-spacing:.2px}
  header .sub{font-size:12px;color:var(--muted)}
  .controls{display:flex;gap:10px;align-items:center;margin-left:auto;flex-wrap:wrap}
  .controls input,.controls select,.controls button{
    background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:7px;
    padding:6px 10px;font-size:13px;outline:none}
  .controls button{cursor:pointer}
  .controls button:hover{border-color:#94a3b8}
  #main{flex:1;position:relative;min-height:0}
  #cy{position:absolute;inset:0;background:#ffffff}
  #legend{position:absolute;top:12px;left:12px;background:rgba(255,255,255,.95);border:1px solid var(--line);
    border-radius:10px;padding:12px 14px;font-size:12.5px;max-width:250px;box-shadow:0 2px 10px rgba(15,23,42,.08)}
  #legend h3{margin:0 0 8px;font-size:12px;text-transform:uppercase;letter-spacing:.6px;color:var(--muted)}
  .lrow{display:flex;align-items:center;gap:8px;margin:5px 0}
  .swatch{width:16px;height:16px;border-radius:50%;flex:none;border:2px solid transparent}
  .swatch.dia{border-radius:3px;transform:rotate(45deg)}
  .line{width:22px;height:0;border-top:3px solid;flex:none}
  #info{position:absolute;bottom:12px;left:12px;right:12px;background:rgba(255,255,255,.97);
    border:1px solid var(--line);border-radius:10px;padding:12px 14px;font-size:13.5px;max-width:520px;display:none;box-shadow:0 2px 14px rgba(15,23,42,.12)}
  #info b{color:#0f172a}
  #info .tag{display:inline-block;font-size:11px;padding:2px 7px;border-radius:20px;margin-right:6px}
  #info .meta{color:var(--muted);font-size:12.5px;margin-top:6px;line-height:1.5}
  a{color:#2563eb}
</style>
</head>
<body>
<div id="app">
  <header>
    <div>
      <h1>GVHD Microbiome &mdash; Claims &amp; Evidence Network</h1>
      <div class="sub">Reviews <b>assert</b> claims &rarr; claims draw <b>evidence from</b> primary papers</div>
    </div>
    <div class="controls">
      <input id="search" type="text" placeholder="Search claims / papers&hellip;" autocomplete="off">
      <select id="layout">
        <option value="rings">Layout: Rings (reviews&rarr;claims&rarr;papers)</option>
        <option value="cose">Layout: Force (cose)</option>
        <option value="concentric">Layout: Concentric</option>
        <option value="breadthfirst">Layout: Hierarchy</option>
        <option value="circle">Layout: Circle</option>
        <option value="grid">Layout: Grid</option>
      </select>
      <button id="fit">Fit</button>
      <button id="reset">Reset</button>
      <button id="labels">Hide labels</button>
    </div>
  </header>
  <div id="main">
    <div id="cy"></div>
    <div id="legend">
      <h3>Nodes</h3>
      <div class="lrow"><span class="swatch" style="background:var(--claim);border-color:var(--fav)"></span> Claim (border = valence)</div>
      <div class="lrow"><span class="swatch" style="background:var(--paper)"></span> Primary paper</div>
      <div class="lrow"><span class="swatch dia" style="background:var(--review)"></span> Review paper</div>
      <h3 style="margin-top:12px">Valence</h3>
      <div class="lrow"><span class="line" style="border-color:var(--fav)"></span> Favourable (reduces GVHD)</div>
      <div class="lrow"><span class="line" style="border-color:var(--unfav)"></span> Unfavourable (exacerbates)</div>
      <div class="lrow"><span class="line" style="border-color:var(--ctx)"></span> Context / other</div>
      <div class="lrow" style="color:var(--muted);margin-top:8px">Node size &prop; references. Click a node to focus.</div>
    </div>
    <div id="info"></div>
  </div>
</div>
<script>
var ELEMENTS = __ELEMENTS__;

var valColor = {favourable:'#16a34a', unfavourable:'#dc2626', context:'#64748b', other:'#64748b'};

var cy = cytoscape({
  container: document.getElementById('cy'),
  elements: ELEMENTS,
  wheelSensitivity: 0.25,
  style: [
    { selector:'node', style:{
        'label':'data(label)','color':'#000000','font-size':'28px',
        'text-wrap':'wrap','text-max-width':'240px',
        'text-valign':'center','text-halign':'center',
        'width':'data(size)','height':'data(size)',
        'border-width':3,'transition-property':'opacity','transition-duration':'150ms'
    }},
    // claim nodes: light-blue fill (so black text reads), border encodes valence
    { selector:'node[ntype="claim"]', style:{
        'background-color':'#bfdbfe','shape':'round-rectangle',
        'text-max-width':'240px','font-size':'28px','color':'#000000','font-weight':'700',
        'border-color': function(e){ return valColor[e.data('valence')]||'#64748b'; },
        'border-width':6
    }},
    // primary papers: amber ellipse, black label sits OUTSIDE the node, angled along its spoke
    { selector:'node[ntype="paper"]', style:{
        'background-color':'#f59e0b','shape':'ellipse','color':'#000000',
        'border-color':'#b45309','font-size':'26px','font-weight':'700','text-wrap':'none',
        'text-margin-x':'data(tmx)','text-margin-y':'data(tmy)','text-rotation':'data(trot)'
    }},
    // review papers: gold diamond hubs, black label
    { selector:'node[role="review"]', style:{
        'background-color':'#fcd34d','shape':'diamond','color':'#000000',
        'border-color':'#b45309','border-width':5,'font-size':'32px','font-weight':'bold',
        'text-margin-x':0,'text-margin-y':0,'text-rotation':0
    }},
    // edges: clear directed arrows, colored by valence
    { selector:'edge', style:{
        'curve-style':'bezier','width':'data(ewidth)',
        'line-color': function(e){ return valColor[e.data('valence')]||'#64748b'; },
        'target-arrow-color': function(e){ return valColor[e.data('valence')]||'#64748b'; },
        'target-arrow-shape':'triangle','arrow-scale':1.7,
        'opacity':0.75,'transition-property':'opacity','transition-duration':'150ms'
    }},
    // ASSERTS edges (review -> claim): dashed to distinguish from evidence
    { selector:'edge[etype="ASSERTS"]', style:{ 'line-style':'dashed' }},
    { selector:'.faded', style:{'opacity':0.07,'text-opacity':0.07}},
    { selector:'.hi', style:{'opacity':1,'text-opacity':1}},
    { selector:'node.hi', style:{'border-color':'#fde047','border-width':5}},
    { selector:'edge.hi', style:{'opacity':1,'width':4}}
  ]
});

var layouts = {
  cose:{name:'cose',animate:true,padding:40,nodeRepulsion:9000,idealEdgeLength:110,nodeOverlap:24,gravity:0.25,numIter:1200},
  concentric:{name:'concentric',padding:40,minNodeSpacing:30,
      concentric:function(n){ return n.data('role')==='review'?3:(n.data('ntype')==='claim'?2:1); },
      levelWidth:function(){return 1;}},
  breadthfirst:{name:'breadthfirst',directed:true,padding:40,spacingFactor:1.1},
  circle:{name:'circle',padding:40},
  grid:{name:'grid',padding:40}
};
// custom radial layout: review papers in the center, claims on a middle ring,
// primary papers on the outer ring. Papers are ordered near the claims they support.
function ringLayout(){
  var cx=0, cy0=0;
  var reviews=cy.nodes('[role="review"]');
  var claims=cy.nodes('[ntype="claim"]');
  var papers=cy.nodes('[role="primary"]');
  var pos={};
  var revIndex={}; reviews.forEach(function(n,i){ revIndex[n.id()]=i; });
  // inner: review hubs
  var rR=190;
  if(reviews.length===1){ pos[reviews[0].id()]={x:cx,y:cy0}; }
  else reviews.forEach(function(n,i){ var a=2*Math.PI*i/reviews.length - Math.PI/2;
        pos[n.id()]={x:cx+rR*Math.cos(a), y:cy0+rR*Math.sin(a)}; });
  // middle ring: claims grouped by taxon (subjgroup) so claims about the same
  // organism sit next to each other (e.g. Lactobacillus reduces / exacerbates).
  var clist=claims.toArray().sort(function(a,b){
        var ga=a.data('subjgroup')||'zzz', gb=b.data('subjgroup')||'zzz';
        if(ga!==gb) return ga<gb?-1:1;
        var va=a.data('valence')||'', vb=b.data('valence')||'';
        if(va!==vb) return va<vb?-1:1;
        return a.id()<b.id()?-1:1; });
  var claimAngle={}, R1=640;
  clist.forEach(function(n,i){
        var a=2*Math.PI*i/clist.length - Math.PI/2;
        claimAngle[n.id()]=a;
        // jitter the radius so the now-large labels have room (deterministic)
        var stagger=(i%2===0? -1:1)*95;
        var noise=Math.sin(i*12.9898)*43758.5453; noise=(noise-Math.floor(noise)-0.5)*70;
        var r=R1+stagger+noise;
        pos[n.id()]={x:cx+r*Math.cos(a), y:cy0+r*Math.sin(a)}; });
  // outer ring: primary papers, placed at the circular mean angle of their claims
  var plist=papers.toArray();
  plist.forEach(function(p){
        var sx=0,sy=0,c=0;
        p.connectedEdges().connectedNodes('[ntype="claim"]').forEach(function(cn){
            var a=claimAngle[cn.id()]; if(a!=null){ sx+=Math.cos(a); sy+=Math.sin(a); c++; } });
        p._ang = c? Math.atan2(sy,sx) : 0; });
  plist.sort(function(a,b){ return a._ang-b._ang; });
  var R2=1180;
  plist.forEach(function(n,i){
        var a=2*Math.PI*i/plist.length - Math.PI/2;
        pos[n.id()]={x:cx+R2*Math.cos(a), y:cy0+R2*Math.sin(a)};
        // place label outside the node along the spoke, rotated to read radially
        var off=n.data('size')/2 + 12;
        var flip=Math.cos(a)<0;                 // left half: flip so text stays upright
        n.data('tmx', off*Math.cos(a));
        n.data('tmy', off*Math.sin(a));
        n.data('trot', flip ? a+Math.PI : a);
  });
  cy.layout({name:'preset', positions:function(n){return pos[n.id()];}, fit:true, padding:60, animate:true, animationDuration:500}).run();
  cy.style().update();
}
function resetPaperLabels(){
  cy.nodes('[ntype="paper"]').forEach(function(n){ n.data('tmx',0); n.data('tmy',0); n.data('trot',0); });
  cy.style().update();
}
function runLayout(n){ if(n==='rings'){ ringLayout(); } else { resetPaperLabels(); cy.layout(layouts[n]).run(); } }
runLayout('rings');

// focus on click
function focus(node){
  var nb = node.closedNeighborhood();
  cy.elements().addClass('faded').removeClass('hi');
  nb.removeClass('faded').addClass('hi');
  showInfo(node);
}
function clearFocus(){ cy.elements().removeClass('faded hi'); hideInfo(); }

cy.on('tap','node', function(e){ focus(e.target); });
cy.on('tap', function(e){ if(e.target===cy) clearFocus(); });

var info=document.getElementById('info');
function showInfo(node){
  var d=node.data(); var h='';
  if(d.ntype==='claim'){
    var c=valColor[d.valence]||'#64748b';
    h='<span class="tag" style="background:'+c+';color:#fff">'+d.valence+'</span>'+
      '<b>'+esc(d.label)+'</b>'+
      '<div class="meta">Subject: '+esc(d.subject)+' &middot; '+d.nprimary+' primary reference(s)'+
      '<br>Asserted by reviews; evidence drawn from the linked primary papers.</div>';
  } else {
    var role=d.role==='review'?'Review':'Primary';
    h='<span class="tag" style="background:'+(d.role==='review'?'#b45309':'#f59e0b')+';color:#fff">'+role+' paper</span>'+
      '<b>'+esc(d.label)+'</b>'+
      '<div class="meta">'+(d.role==='review'?'Touches '+d.ntouched+' claim(s).':'Cited as evidence for '+d.ntouched+' claim(s).')+
      (d.doi?'<br>DOI: <a href="https://doi.org/'+esc(d.doi)+'" target="_blank" rel="noopener">'+esc(d.doi)+'</a>':'')+'</div>';
  }
  info.innerHTML=h; info.style.display='block';
}
function hideInfo(){ info.style.display='none'; }
function esc(s){ return (s||'').replace(/[&<>"]/g,function(c){return{'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];}); }

// search
document.getElementById('search').addEventListener('input', function(e){
  var q=e.target.value.trim().toLowerCase();
  if(!q){ clearFocus(); return; }
  var match=cy.nodes().filter(function(n){ return n.data('label').toLowerCase().indexOf(q)>=0; });
  if(match.length===0){ cy.elements().addClass('faded').removeClass('hi'); hideInfo(); return; }
  var keep=match.closedNeighborhood();
  cy.elements().addClass('faded').removeClass('hi');
  keep.removeClass('faded'); match.addClass('hi');
});

document.getElementById('layout').addEventListener('change', function(e){ clearFocus(); runLayout(e.target.value); });
document.getElementById('fit').addEventListener('click', function(){ cy.fit(undefined,40); });
document.getElementById('reset').addEventListener('click', function(){ clearFocus(); document.getElementById('search').value=''; cy.fit(undefined,40); });
var labelsOn=true;
document.getElementById('labels').addEventListener('click', function(e){
  labelsOn=!labelsOn;
  cy.style().selector('node').style('text-opacity', labelsOn?1:0).update();
  e.target.textContent = labelsOn?'Hide labels':'Show labels';
});
</script>
</body>
</html>'''

HTML=HTML.replace("__ELEMENTS__", elements_js)
open("gvhd_claims_network.html","w").write(HTML)
print("written", len(HTML), "bytes")
