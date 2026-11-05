# HTML/Cytoscape template v3 — rank-aware radial layout with GTDB lineage grouping.
# render_network_html_v3.py extracts the raw-string HTML template below.
# Running this file directly is not part of the pipeline.
import json
data = json.load(open("graph_data3.json"))
elements_js = json.dumps(data, separators=(",", ":"))

HTML = r'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>GVHD Microbiome Claims &amp; Evidence Network v3</title>
<script src="https://cdnjs.cloudflare.com/ajax/libs/cytoscape/3.30.2/cytoscape.min.js"></script>
<style>
  :root{
    --claim:#bfdbfe; --paper:#f59e0b; --review:#fcd34d;
    --fav:#16a34a; --unfav:#dc2626; --ctx:#64748b;
    --bg:#ffffff; --panel:#f1f5f9; --ink:#0f172a; --muted:#64748b; --line:#cbd5e1;
  }
  *{box-sizing:border-box}
  html,body{margin:0;height:100%;font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Helvetica,Arial,sans-serif;background:var(--bg);color:var(--ink)}
  #app{display:flex;flex-direction:column;height:100vh}
  header{padding:10px 16px;border-bottom:1px solid var(--line);display:flex;flex-wrap:wrap;gap:12px;align-items:center}
  header h1{font-size:16px;margin:0;font-weight:600}
  header .sub{font-size:11px;color:var(--muted)}
  .controls{display:flex;gap:8px;align-items:center;margin-left:auto;flex-wrap:wrap}
  .controls input,.controls select,.controls button,.controls label{
    background:var(--panel);color:var(--ink);border:1px solid var(--line);border-radius:7px;
    padding:5px 9px;font-size:12px;outline:none;cursor:pointer}
  .controls button:hover{border-color:#94a3b8}
  .controls label{display:flex;align-items:center;gap:5px;user-select:none}
  #main{flex:1;position:relative;min-height:0}
  #cy{position:absolute;inset:0;background:#ffffff}
  /* phylum label canvas sits on top, pointer-events off so clicks pass to Cytoscape */
  #phylumCanvas{position:absolute;inset:0;pointer-events:none}
  #legend{position:absolute;top:12px;left:12px;background:rgba(255,255,255,.96);border:1px solid var(--line);
    border-radius:10px;padding:12px 14px;font-size:12px;max-width:230px;box-shadow:0 2px 10px rgba(15,23,42,.08);z-index:10}
  #legend h3{margin:0 0 7px;font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:var(--muted)}
  .lrow{display:flex;align-items:center;gap:7px;margin:4px 0;font-size:11.5px}
  .swatch{width:14px;height:14px;border-radius:50%;flex:none;border:2px solid transparent}
  .swatch.dia{border-radius:2px;transform:rotate(45deg)}
  .ledge{width:20px;height:0;border-top:3px solid;flex:none}
  .rank-bar{display:flex;align-items:center;gap:5px;margin:3px 0;font-size:11px}
  .rank-dot{width:8px;height:8px;border-radius:50%;background:#bfdbfe;border:2px solid #6b7280;flex:none}
  #info{position:absolute;bottom:12px;left:12px;right:12px;background:rgba(255,255,255,.97);
    border:1px solid var(--line);border-radius:10px;padding:11px 13px;font-size:13px;max-width:500px;
    display:none;box-shadow:0 2px 14px rgba(15,23,42,.12);z-index:10}
  #info .tag{display:inline-block;font-size:11px;padding:2px 7px;border-radius:20px;margin-right:5px}
  #info .meta{color:var(--muted);font-size:12px;margin-top:5px;line-height:1.5}
  a{color:#2563eb}
</style>
</head>
<body>
<div id="app">
  <header>
    <div>
      <h1>GVHD Microbiome &mdash; Claims &amp; Evidence Network</h1>
      <div class="sub">Rings layout: reviews (centre) &rarr; primary papers &rarr; claims by taxonomy rank</div>
    </div>
    <div class="controls">
      <input id="search" type="text" placeholder="Search&hellip;" autocomplete="off" style="width:160px">
      <select id="layout">
        <option value="rings">Layout: Rings (rank-aware)</option>
        <option value="cose">Layout: Force (cose)</option>
        <option value="concentric">Layout: Concentric</option>
        <option value="breadthfirst">Layout: Hierarchy</option>
        <option value="circle">Layout: Circle</option>
        <option value="grid">Layout: Grid</option>
      </select>
      <label><input type="checkbox" id="taxLinks"> Show taxonomy links</label>
      <button id="fit">Fit</button>
      <button id="reset">Reset</button>
      <button id="labels">Hide labels</button>
    </div>
  </header>
  <div id="main">
    <div id="cy"></div>
    <canvas id="phylumCanvas"></canvas>
    <div id="legend">
      <h3>Nodes</h3>
      <div class="lrow"><span class="swatch" style="background:var(--claim);border-color:var(--fav)"></span> Claim (border = valence)</div>
      <div class="lrow"><span class="swatch" style="background:var(--paper)"></span> Primary paper</div>
      <div class="lrow"><span class="swatch dia" style="background:var(--review)"></span> Review paper</div>
      <h3 style="margin-top:10px">Valence</h3>
      <div class="lrow"><span class="ledge" style="border-color:var(--fav)"></span> Favourable (reduces GVHD)</div>
      <div class="lrow"><span class="ledge" style="border-color:var(--unfav)"></span> Unfavourable (exacerbates)</div>
      <div class="lrow"><span class="ledge" style="border-color:var(--ctx)"></span> Context-dependent</div>
      <h3 style="margin-top:10px">Rank (radius)</h3>
      <div class="rank-bar" style="margin-left:2px">
        <span style="font-size:10px;color:var(--muted);width:70px">inner&rarr;outer</span>
        <span style="font-size:10px">sp &rarr; gen &rarr; fam &rarr; ord &rarr; cls &rarr; phy</span>
      </div>
      <div class="lrow" style="color:var(--muted);margin-top:6px;font-size:11px">Angle = lineage group &middot; click to focus</div>
    </div>
    <div id="info"></div>
  </div>
</div>
<script>
var ELEMENTS = __ELEMENTS__;

// ── Layout constants (tune these to adjust spacing) ────────────────────────
var R_REVIEW   = 190;    // review hub ring radius
var R_PAPERS   = 960;    // primary papers ring radius
var R_SPECIES  = 1380;   // innermost claim radius (species, rank_level=1)
var RANK_STEP  = 280;    // radial step per rank level
// rank_level: species=1 genus=2 family=3 order=4 class=5 phylum=6 domain=7
// non-taxon (functional, molecular_pattern) → R_SPECIES (same as species)
var PHY_GAP    = 1.2;    // angular gap between bacterial phyla (in slot units)
var SECTOR_GAP = 2.5;    // gap between Bacteria vs other sectors (Eukaryota, Virus, functional)
var R_PHYLUM_LABEL = 200; // extra radius beyond outermost claim for phylum labels

function claimR(rl) {
  if (rl === null || rl === undefined) return R_SPECIES;
  return R_SPECIES + Math.max(0, rl - 1) * RANK_STEP;
}

// ── Sector ordering ────────────────────────────────────────────────────────
var SECTOR_ORDER = {
  'Bacteria': 0, 'Archaea': 1, 'Eukaryota': 2,
  'Virus': 3, 'functional group': 4, 'molecular pattern': 5, 'other': 6
};
function sectorKey(s) { return (SECTOR_ORDER[s] !== undefined ? SECTOR_ORDER[s] : 9); }

// ── Valence colours ────────────────────────────────────────────────────────
var valColor = {
  favourable: '#16a34a', unfavourable: '#dc2626',
  context: '#64748b', other: '#64748b'
};

var cy = cytoscape({
  container: document.getElementById('cy'),
  elements: ELEMENTS,
  wheelSensitivity: 0.25,
  style: [
    { selector: 'node', style: {
        label: 'data(label)', color: '#000000', 'font-size': '26px',
        'text-wrap': 'wrap', 'text-max-width': '220px',
        'text-valign': 'center', 'text-halign': 'center',
        width: 'data(size)', height: 'data(size)',
        'border-width': 3,
        'transition-property': 'opacity', 'transition-duration': '150ms'
    }},
    { selector: 'node[ntype="claim"]', style: {
        'background-color': '#bfdbfe', shape: 'round-rectangle',
        'font-size': '26px', color: '#000000', 'font-weight': '700',
        'border-color': function(e){ return valColor[e.data('valence')] || '#64748b'; },
        'border-width': 6
    }},
    { selector: 'node[ntype="paper"]', style: {
        'background-color': '#f59e0b', shape: 'ellipse', color: '#000000',
        'border-color': '#b45309', 'font-size': '24px', 'font-weight': '700',
        'text-wrap': 'none',
        'text-margin-x': 'data(tmx)', 'text-margin-y': 'data(tmy)',
        'text-rotation': 'data(trot)'
    }},
    { selector: 'node[role="review"]', style: {
        'background-color': '#fcd34d', shape: 'diamond', color: '#000000',
        'border-color': '#b45309', 'border-width': 5,
        'font-size': '30px', 'font-weight': 'bold',
        'text-margin-x': 0, 'text-margin-y': 0, 'text-rotation': 0
    }},
    { selector: 'edge', style: {
        'curve-style': 'bezier', width: 'data(ewidth)',
        'line-color': function(e){ return valColor[e.data('valence')] || '#64748b'; },
        'target-arrow-color': function(e){ return valColor[e.data('valence')] || '#64748b'; },
        'target-arrow-shape': 'triangle', 'arrow-scale': 1.6,
        opacity: 0.7,
        'transition-property': 'opacity', 'transition-duration': '150ms'
    }},
    { selector: 'edge[etype="CITES"]', style: { 'line-style': 'dashed' }},
    { selector: 'edge[etype="TAXONOMY"]', style: {
        'line-style': 'dashed', 'line-dash-pattern': [6, 8],
        opacity: 0.35, width: 1.5,
        'line-color': '#94a3b8', 'target-arrow-color': '#94a3b8',
        'target-arrow-shape': 'triangle', 'arrow-scale': 0.8
    }},
    { selector: '.faded', style: { opacity: 0.07, 'text-opacity': 0.07 }},
    { selector: '.hi',    style: { opacity: 1,    'text-opacity': 1    }},
    { selector: 'node.hi', style: { 'border-color': '#fde047', 'border-width': 5 }},
    { selector: 'edge.hi', style: { opacity: 1, width: 4 }}
  ]
});

// ── Rings v3 layout ────────────────────────────────────────────────────────
function ringLayout() {
  var reviews = cy.nodes('[role="review"]');
  var claims  = cy.nodes('[ntype="claim"]');
  var papers  = cy.nodes('[role="primary"]');
  var pos = {};

  // Reviews: small central cluster
  if (reviews.length === 1) {
    pos[reviews[0].id()] = { x: 0, y: 0 };
  } else {
    reviews.forEach(function(n, i) {
      var a = 2 * Math.PI * i / reviews.length - Math.PI / 2;
      pos[n.id()] = { x: R_REVIEW * Math.cos(a), y: R_REVIEW * Math.sin(a) };
    });
  }

  // Sort claims by (sector, phylum, class, order, family, genus, species, valence)
  function claimSortKey(n) {
    var d = n.data();
    var s = sectorKey(d.domain_sector);
    return [
      s,
      d.phylum   || '\uFFFF',
      d.class    || '\uFFFF',
      d.order    || '\uFFFF',
      d.family   || '\uFFFF',
      d.genus    || '\uFFFF',
      d.species  || '\uFFFF',
      d.valence  || '\uFFFF'
    ].join('\x00');
  }

  var clist = claims.toArray().sort(function(a, b) {
    var ka = claimSortKey(a), kb = claimSortKey(b);
    return ka < kb ? -1 : ka > kb ? 1 : 0;
  });

  // Build slots array: claim ids with phylum/sector gaps
  var slots = [];   // {id: string} | {gap: float, label?: string}
  var prevPhylum = null, prevSector = null;
  clist.forEach(function(n) {
    var d = n.data();
    var sector = sectorKey(d.domain_sector);
    var phylum = (d.phylum && sector <= 1) ? d.phylum : d.domain_sector;

    if (prevSector !== null) {
      if (sector !== prevSector) {
        slots.push({ gap: SECTOR_GAP, label: null });
      } else if (phylum !== prevPhylum) {
        slots.push({ gap: PHY_GAP, label: null });
      }
    }
    slots.push({ id: n.id() });
    prevPhylum = phylum;
    prevSector = sector;
  });

  // Total angular weight
  var total = 0;
  slots.forEach(function(s) { total += s.id ? 1 : s.gap; });
  // Leave a small closing gap
  total += PHY_GAP;

  // Assign base angles: each slot occupies (weight/total) * 2π
  var baseAngle = {};
  var pos_i = 0.5;   // center of first slot
  slots.forEach(function(s) {
    if (s.id) {
      baseAngle[s.id] = 2 * Math.PI * pos_i / total - Math.PI / 2;
      pos_i += 1;
    } else {
      pos_i += s.gap;
    }
  });

  // Build lineage index: for each GTDB lineage field (genus, family, …),
  // map name → [claim ids that have this name at that rank in their lineage]
  var LFIELDS = ['species', 'genus', 'family', 'order', 'class', 'phylum'];
  var linIdx = {};
  LFIELDS.forEach(function(f) { linIdx[f] = {}; });
  clist.forEach(function(n) {
    var d = n.data();
    LFIELDS.forEach(function(f) {
      var v = d[f];
      if (v) {
        if (!linIdx[f][v]) linIdx[f][v] = [];
        linIdx[f][v].push(n.id());
      }
    });
  });

  // Compute final angles: higher-rank claims centre over their lineage subtree
  // rank_level 1=species, 2=genus, …, 6=phylum
  var RANK_FIELD = ['', 'species', 'genus', 'family', 'order', 'class', 'phylum'];
  var finalAngle = {};

  clist.forEach(function(n) {
    var d = n.data();
    var rl = d.rank_level;

    // Non-taxon or species: use base angle directly
    if (rl === null || rl === undefined || rl <= 1) {
      finalAngle[n.id()] = baseAngle[n.id()];
      return;
    }

    // Find the GTDB name for this rank (e.g. genus claim → d.gtdb_name)
    var myField = RANK_FIELD[rl];       // 'genus', 'family', etc.
    var myName  = d.gtdb_name || '';    // GTDB canonical name

    var kids = myName ? (linIdx[myField][myName] || []) : [];
    // exclude self
    kids = kids.filter(function(id) { return id !== n.id(); });

    if (kids.length === 0) {
      finalAngle[n.id()] = baseAngle[n.id()];
      return;
    }

    // Circular mean of children's base angles
    var sx = 0, sy = 0;
    kids.forEach(function(id) {
      var a = baseAngle[id];
      if (a !== undefined) { sx += Math.cos(a); sy += Math.sin(a); }
    });
    finalAngle[n.id()] = (sx === 0 && sy === 0)
      ? baseAngle[n.id()]
      : Math.atan2(sy, sx);
  });

  // Position claims at rank radius + final angle
  var claimAngle = {};
  clist.forEach(function(n) {
    var d = n.data();
    var a = finalAngle[n.id()];
    var r = claimR(d.rank_level);
    claimAngle[n.id()] = a;
    pos[n.id()] = { x: r * Math.cos(a), y: r * Math.sin(a) };
  });

  // Primary papers: mean angle of their claims, evenly spaced at R_PAPERS
  var plist = papers.toArray();
  plist.forEach(function(p) {
    var sx = 0, sy = 0, c = 0;
    p.connectedEdges().connectedNodes('[ntype="claim"]').forEach(function(cn) {
      var a = claimAngle[cn.id()];
      if (a != null) { sx += Math.cos(a); sy += Math.sin(a); c++; }
    });
    p._ang = c ? Math.atan2(sy, sx) : 0;
  });
  plist.sort(function(a, b) { return a._ang - b._ang; });
  plist.forEach(function(n, i) {
    var a = 2 * Math.PI * i / plist.length - Math.PI / 2;
    pos[n.id()] = { x: R_PAPERS * Math.cos(a), y: R_PAPERS * Math.sin(a) };
    var off = n.data('size') / 2 + 10;
    var flip = Math.cos(a) < 0;
    n.data('tmx', off * Math.cos(a));
    n.data('tmy', off * Math.sin(a));
    n.data('trot', flip ? a + Math.PI : a);
  });

  cy.layout({
    name: 'preset',
    positions: function(n) { return pos[n.id()]; },
    fit: true, padding: 80, animate: true, animationDuration: 600
  }).run();
  cy.style().update();

  // After layout settles, record claim angles for phylum labels
  cy._claimAngle = claimAngle;
  cy._clist = clist;
  setTimeout(drawPhylumLabels, 700);
}

// ── Phylum sector labels (canvas overlay) ─────────────────────────────────
var canvas = document.getElementById('phylumCanvas');
var ctx2d  = canvas.getContext('2d');

function resizeCanvas() {
  var el = document.getElementById('main');
  canvas.width  = el.clientWidth;
  canvas.height = el.clientHeight;
}
window.addEventListener('resize', function() { resizeCanvas(); drawPhylumLabels(); });
resizeCanvas();

function drawPhylumLabels() {
  ctx2d.clearRect(0, 0, canvas.width, canvas.height);
  if (!cy._claimAngle || !cy._clist) return;

  // Collect phylum angle ranges from claim positions
  var phylumAngles = {};   // phylum_key -> [angles]
  cy._clist.forEach(function(n) {
    var d = n.data();
    if (d.domain_sector !== 'Bacteria' && d.domain_sector !== 'Archaea') return;
    var phy = d.phylum;
    if (!phy) return;
    if (!phylumAngles[phy]) phylumAngles[phy] = [];
    phylumAngles[phy].push(cy._claimAngle[n.id()]);
  });

  // Max claim radius in graph space
  var maxR = R_SPECIES + 6 * RANK_STEP + R_PHYLUM_LABEL;

  var zoom = cy.zoom();
  var pan  = cy.pan();

  // graph → screen
  function gx(x) { return x * zoom + pan.x + canvas.width / 2; }
  function gy(y) { return y * zoom + pan.y + canvas.height / 2; }

  ctx2d.save();
  ctx2d.font = 'bold ' + Math.max(10, 13 * zoom) + 'px system-ui,sans-serif';
  ctx2d.textAlign = 'center';
  ctx2d.textBaseline = 'middle';

  for (var phy in phylumAngles) {
    var angs = phylumAngles[phy];
    if (angs.length === 0) continue;
    // Circular mean
    var sx = 0, sy = 0;
    angs.forEach(function(a) { sx += Math.cos(a); sy += Math.sin(a); });
    var meanA = Math.atan2(sy, sx);
    var labelR = maxR;
    var lx = gx(labelR * Math.cos(meanA));
    var ly = gy(labelR * Math.sin(meanA));

    ctx2d.save();
    ctx2d.translate(lx, ly);
    // Rotate text to read outward
    var rot = meanA + Math.PI / 2;
    if (meanA > Math.PI / 2 || meanA < -Math.PI / 2) rot += Math.PI;
    ctx2d.rotate(rot);
    ctx2d.fillStyle = '#334155';
    ctx2d.fillText(phy, 0, 0);
    ctx2d.restore();
  }
  ctx2d.restore();
}

// Redraw phylum labels on pan/zoom
cy.on('render', function() { drawPhylumLabels(); });

// ── Taxonomy link toggle ──────────────────────────────────────────────────
var taxEdgesAdded = false;

document.getElementById('taxLinks').addEventListener('change', function(e) {
  if (e.target.checked) {
    if (!taxEdgesAdded) {
      var toAdd = [];
      cy.nodes('[ntype="claim"]').forEach(function(n) {
        var parent = n.data('lineage_parent');
        if (parent && cy.getElementById(parent).length > 0) {
          toAdd.push({ group: 'edges', data: {
            id: 'tax_' + n.id(),
            source: n.id(),
            target: parent,
            etype: 'TAXONOMY',
            valence: 'other',
            ewidth: 1.5
          }});
        }
      });
      if (toAdd.length) { cy.add(toAdd); taxEdgesAdded = true; }
    } else {
      cy.edges('[etype="TAXONOMY"]').style('display', 'element');
    }
  } else {
    cy.edges('[etype="TAXONOMY"]').style('display', 'none');
  }
});

// ── Other layouts ─────────────────────────────────────────────────────────
var layouts = {
  cose: { name:'cose', animate:true, padding:40, nodeRepulsion:9000,
          idealEdgeLength:110, nodeOverlap:24, gravity:0.25, numIter:1200 },
  concentric: { name:'concentric', padding:40, minNodeSpacing:30,
    concentric: function(n){ return n.data('role')==='review' ? 3 : (n.data('ntype')==='claim' ? 1 : 2); },
    levelWidth: function(){ return 1; }},
  breadthfirst: { name:'breadthfirst', directed:true, padding:40, spacingFactor:1.1 },
  circle: { name:'circle', padding:40 },
  grid:   { name:'grid',   padding:40 }
};

function resetPaperLabels() {
  cy.nodes('[ntype="paper"]').forEach(function(n){
    n.data('tmx', 0); n.data('tmy', 0); n.data('trot', 0);
  });
  cy.style().update();
}

function runLayout(name) {
  if (name === 'rings') {
    ringLayout();
  } else {
    ctx2d.clearRect(0, 0, canvas.width, canvas.height);
    resetPaperLabels();
    cy.layout(layouts[name]).run();
  }
}
runLayout('rings');

// ── Focus on click ────────────────────────────────────────────────────────
function focus(node) {
  var nb = node.closedNeighborhood();
  // also include taxonomy link neighbours if visible
  cy.edges('[etype="TAXONOMY"]').connectedNodes().forEach(function(n) {
    if (nb.has(node)) return;
  });
  cy.elements().addClass('faded').removeClass('hi');
  nb.removeClass('faded').addClass('hi');
  showInfo(node);
}
function clearFocus() { cy.elements().removeClass('faded hi'); hideInfo(); }

cy.on('tap', 'node', function(e) { focus(e.target); });
cy.on('tap', function(e) { if (e.target === cy) clearFocus(); });

// ── Info panel ────────────────────────────────────────────────────────────
var info = document.getElementById('info');
function showInfo(node) {
  var d = node.data(); var h = '';
  if (d.ntype === 'claim') {
    var c = valColor[d.valence] || '#64748b';
    var rankStr = d.rank_as_cited ? ' (' + d.rank_as_cited + ')' : '';
    var phyStr  = d.phylum ? d.phylum : (d.domain_sector || '');
    var reclStr = d.gtdb_reclassified === 'yes'
      ? ' <span class="tag" style="background:#e2e8f0;color:#334155">GTDB reclassified</span>' : '';
    h = '<span class="tag" style="background:' + c + ';color:#fff">' + esc(d.valence) + '</span>' +
        reclStr +
        '<b>' + esc(d.label) + '</b>' +
        '<div class="meta">' +
          'Rank: ' + esc(d.rank_as_cited || '—') + ' &middot; ' +
          'Phylum: ' + esc(phyStr || '—') + '<br>' +
          (d.gtdb_name && d.gtdb_name !== (d.label.split(' ')[0] + (d.label.split(' ')[1] ? ' '+d.label.split(' ')[1] : ''))
            ? 'GTDB name: ' + esc(d.gtdb_name) + '<br>' : '') +
          d.nprimary + ' primary reference(s)' +
        '</div>';
  } else {
    var role = d.role === 'review' ? 'Review' : 'Primary';
    h = '<span class="tag" style="background:' + (d.role==='review'?'#b45309':'#f59e0b') + ';color:#fff">' + role + '</span>' +
        '<b>' + esc(d.label) + '</b>' +
        '<div class="meta">' + (d.role==='review'
          ? 'Touches ' + d.ntouched + ' claim(s).'
          : 'Evidence for ' + d.ntouched + ' claim(s).') + '</div>';
  }
  info.innerHTML = h;
  info.style.display = 'block';
}
function hideInfo() { info.style.display = 'none'; }
function esc(s) {
  return (s||'').replace(/[&<>"]/g, function(c){
    return {'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;'}[c];
  });
}

// ── Search ────────────────────────────────────────────────────────────────
document.getElementById('search').addEventListener('input', function(e) {
  var q = e.target.value.trim().toLowerCase();
  if (!q) { clearFocus(); return; }
  var match = cy.nodes().filter(function(n){
    return (n.data('label')||'').toLowerCase().indexOf(q) >= 0;
  });
  if (match.length === 0) { cy.elements().addClass('faded').removeClass('hi'); hideInfo(); return; }
  var keep = match.closedNeighborhood();
  cy.elements().addClass('faded').removeClass('hi');
  keep.removeClass('faded'); match.addClass('hi');
});

// ── Controls ──────────────────────────────────────────────────────────────
document.getElementById('layout').addEventListener('change', function(e) {
  clearFocus(); runLayout(e.target.value);
});
document.getElementById('fit').addEventListener('click', function(){ cy.fit(undefined, 60); });
document.getElementById('reset').addEventListener('click', function(){
  clearFocus();
  document.getElementById('search').value = '';
  cy.fit(undefined, 60);
});
var labelsOn = true;
document.getElementById('labels').addEventListener('click', function(e) {
  labelsOn = !labelsOn;
  cy.style().selector('node').style('text-opacity', labelsOn ? 1 : 0).update();
  e.target.textContent = labelsOn ? 'Hide labels' : 'Show labels';
});
</script>
</body>
</html>'''

HTML = HTML.replace("__ELEMENTS__", elements_js)
open("gvhd_claims_network3.html", "w").write(HTML)
print("written", len(HTML), "bytes")
