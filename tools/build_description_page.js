// Builds the page that holds the CurseForge description, ready to copy with one click.
//   node tools/build_description_page.js
// Reads docs/curseforge-description.html (the text), docs/description-revisions.json (what each
// revision of the description changed), docs/description-images.json (state of every image) and
// docs/screenshots/*.png, and writes the page and its images to the OUT folder, from where it is
// published as an artifact. It also refreshes the Desktop copies (descripcion.html / .txt).
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const OUT = process.argv[2] || path.join(process.env.USERPROFILE || '', 'Desktop', 'VoidcoreAdvertiser-Reborn', 'pagina-descripcion');
const DESK = path.join(process.env.USERPROFILE || '', 'Desktop', 'VoidcoreAdvertiser-Reborn');
const RAW = 'https://raw.githubusercontent.com/KingKhaax/VoidcoreAdvisorReborn/master/docs/screenshots/';

const description = fs.readFileSync(path.join(ROOT, 'docs', 'curseforge-description.html'), 'utf8').replace(/\r\n/g, '\n').trim();
const revisions = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'description-revisions.json'), 'utf8'));
const images = JSON.parse(fs.readFileSync(path.join(ROOT, 'docs', 'description-images.json'), 'utf8'));
const toc = fs.readFileSync(path.join(ROOT, 'VoidcoreAdvisorReborn.toc'), 'utf8');
const version = (toc.match(/^## Version:\s*(.+)$/m) || [])[1] || '?';
const summary = fs.existsSync(path.join(DESK, 'resumen.txt')) ? fs.readFileSync(path.join(DESK, 'resumen.txt'), 'utf8').trim() : '';

fs.mkdirSync(path.join(OUT, 'img'), { recursive: true });
const shots = fs.readdirSync(path.join(ROOT, 'docs', 'screenshots')).filter(f => /\.(png|jpg)$/i.test(f));
for (const f of shots) fs.copyFileSync(path.join(ROOT, 'docs', 'screenshots', f), path.join(OUT, 'img', f));

const data = {
  version, description, summary, revisions, raw: RAW,
  images: shots.map(f => {
    const meta = images[f] || {};
    return { file: f, status: meta.status || 'ok', note: meta.note || '', used: description.includes(RAW + f) };
  })
};
const json = JSON.stringify(data).replace(/</g, '\\u003c');

const page = `<!DOCTYPE html>
<html lang="es">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<title>Descripción de CurseForge</title>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Cinzel:wght@500;600&family=Source+Sans+3:wght@400;600;700&display=swap">
<style>
/* Concept: a working desk for the CurseForge description: copy buttons on top, then what changed, the page as it will look, and every image. Dark green like the addon. */
:root {
  --bg: #0d1210; --ink: #e9efe8; --mute: #8fa597; --gold: #e8c874; --panel: #111c16; --line: #1d4a35;
  --ok: #4fe36b; --warn: #ffb347; --accent: #2f8a3f; --accent-l: #4fc15f;
  --font-display: "Cinzel", Georgia, serif; --font-body: "Source Sans 3", "Segoe UI", system-ui, sans-serif;
  color-scheme: dark;
}
* { box-sizing: border-box; }
body { margin: 0; background: var(--bg); color: var(--ink); font-family: var(--font-body); font-size: 15px; line-height: 1.5;
  padding-block: 24px 64px; padding-left: max(16px, env(safe-area-inset-left, 0px)); padding-right: max(16px, env(safe-area-inset-right, 0px)); }
.wrap { max-width: 980px; margin: 0 auto; }
h1 { font-family: var(--font-display); font-weight: 600; font-size: 28px; margin: 0 0 4px; color: var(--gold); text-wrap: balance; }
h2 { font-family: var(--font-display); font-weight: 600; font-size: 19px; margin: 36px 0 8px; color: var(--gold); }
.sub { color: var(--mute); margin: 0 0 18px; max-width: 74ch; }
.bar { position: sticky; top: env(safe-area-inset-top, 0px); z-index: 5; display: flex; flex-wrap: wrap; gap: 10px; align-items: center; background: #0d1210ee; backdrop-filter: blur(6px); padding: 10px 0; border-bottom: 1px solid var(--line); }
button, .btn { font: inherit; font-weight: 700; cursor: pointer; border: 1px solid #000; color: #fff; padding: 9px 16px; background: linear-gradient(#3da24d, #1f6a2c); box-shadow: inset 0 1px 0 #fff5; border-radius: 3px; }
button.alt { background: linear-gradient(#2a3a31, #18241d); box-shadow: inset 0 1px 0 #fff2; border-color: #1d4a35; }
button:focus-visible { outline: 2px solid var(--gold); outline-offset: 2px; }
button:hover { filter: brightness(1.12); }
.status { color: var(--ok); font-weight: 600; min-height: 1.4em; }
.steps { background: var(--panel); border: 1px solid var(--line); padding: 12px 16px; margin: 14px 0 0; }
.steps ol { margin: 6px 0 0; padding-left: 20px; } .steps li { margin: 3px 0; }
.rev { background: var(--panel); border: 1px solid var(--line); padding: 10px 16px; margin: 0 0 10px; }
.rev b { color: var(--gold); } .rev ul { margin: 6px 0 2px; padding-left: 20px; }
.preview { background: #fff; color: #1b1b1b; padding: 22px 26px; border-radius: 3px; font-family: "Segoe UI", system-ui, sans-serif; font-size: 15px; line-height: 1.55; overflow-wrap: anywhere; }
.preview h2 { color: #111; font-family: "Segoe UI", system-ui, sans-serif; font-size: 22px; margin: 26px 0 8px; border: 0; }
.preview h2:first-child { margin-top: 0; }
.preview a { color: #0a58ca; } .preview code { background: #eef0f2; padding: 1px 5px; border-radius: 3px; font-size: .92em; }
.preview img { max-width: 100%; height: auto; }
.imgs { display: grid; gap: 12px; grid-template-columns: repeat(auto-fill, minmax(min(100%, 280px), 1fr)); }
.card { background: var(--panel); border: 1px solid var(--line); padding: 10px; display: flex; flex-direction: column; gap: 6px; min-width: 0; }
.card img { width: 100%; height: 150px; object-fit: contain; background: #080d0a; }
.card .name { font-weight: 700; overflow-wrap: anywhere; }
.pill { display: inline-block; font-size: 12px; font-weight: 700; padding: 1px 8px; border-radius: 999px; }
.pill.ok { background: #14361f; color: var(--ok); } .pill.old { background: #3b2a0c; color: var(--warn); } .pill.unused { background: #232a26; color: var(--mute); }
.card small { color: var(--mute); }
textarea { width: 100%; min-height: 260px; background: #080d0a; color: #cfe3d4; border: 1px solid var(--line); padding: 10px; font: 13px/1.45 Consolas, monospace; }
details summary { cursor: pointer; color: var(--gold); font-weight: 600; }
</style>
</head>
<body>
<div class="wrap">
  <h1>Descripción de CurseForge</h1>
  <p class="sub">Al día con la versión <b id="ver"></b> del addon. Pulsa el botón verde y pega el resultado en CurseForge.</p>

  <div class="bar">
    <button id="copyDesc">Copiar descripción (HTML)</button>
    <button id="copySum" class="alt">Copiar resumen</button>
    <span class="status" id="status" role="status"></span>
  </div>

  <div class="steps">
    <b>Cómo ponerla en CurseForge</b>
    <ol>
      <li>Abre la edición del proyecto, pestaña <b>Description</b>.</li>
      <li>Pulsa el botón <b>&lt;/&gt;</b> (modo código) para cambiar del editor visual al HTML.</li>
      <li>Selecciona todo (Ctrl+A), pega (Ctrl+V) y vuelve a pulsar <b>&lt;/&gt;</b>. Revisa que se vea bien y guarda.</li>
    </ol>
  </div>

  <h2>Qué ha cambiado en la descripción</h2>
  <div id="revs"></div>

  <h2>Así se verá</h2>
  <p class="sub">Vista previa con las imágenes del repositorio. En CurseForge las imágenes se cargan desde GitHub.</p>
  <div class="preview" id="preview"></div>

  <h2>Imágenes</h2>
  <p class="sub">Las que usa la descripción y las que están en el repositorio. Si me das imágenes nuevas, aparecerán aquí y en el HTML.</p>
  <div class="imgs" id="imgs"></div>

  <h2>Resumen (campo corto)</h2>
  <p class="sub" id="sum"></p>

  <h2>Código HTML</h2>
  <details><summary>Ver el HTML que se copia</summary><textarea id="src" readonly></textarea></details>
</div>
<script>
var D = ${json};
function esc(t) { return String(t).replace(/&/g, '&amp;').replace(/</g, '&lt;'); }
document.getElementById('ver').textContent = D.version;
document.getElementById('sum').textContent = D.summary;
document.getElementById('src').value = D.description;
document.getElementById('preview').innerHTML = D.description.split(D.raw).join('img/');
document.getElementById('revs').innerHTML = D.revisions.map(function (r) {
  return '<div class="rev"><b>' + esc(r.date) + ' · versión ' + esc(r.version) + '</b><ul>' + r.notes.map(function (n) { return '<li>' + esc(n) + '</li>'; }).join('') + '</ul></div>';
}).join('');
document.getElementById('imgs').innerHTML = D.images.map(function (i) {
  var pill = i.status === 'old' ? '<span class="pill old">Hay que renovarla</span>' : (i.used ? '<span class="pill ok">En uso</span>' : '<span class="pill unused">Sin usar</span>');
  return '<div class="card"><img src="img/' + esc(i.file) + '" alt="' + esc(i.file) + '"><div class="name">' + esc(i.file) + '</div><div>' + pill + '</div>' + (i.note ? '<small>' + esc(i.note) + '</small>' : '') + '</div>';
}).join('');

var statusEl = document.getElementById('status'), timer;
function say(msg) { statusEl.textContent = msg; clearTimeout(timer); timer = setTimeout(function () { statusEl.textContent = ''; }, 3500); }
function copy(text, okMsg) {
  function fallback() {
    var ta = document.createElement('textarea'); ta.value = text; ta.style.position = 'fixed'; ta.style.opacity = '0';
    document.body.appendChild(ta); ta.select();
    var ok = false; try { ok = document.execCommand('copy'); } catch (e) {}
    document.body.removeChild(ta);
    if (ok) say(okMsg); else { var d = document.querySelector('details'); d.open = true; document.getElementById('src').select(); say('Selecciónalo y pulsa Ctrl+C'); }
  }
  if (navigator.clipboard && navigator.clipboard.writeText) navigator.clipboard.writeText(text).then(function () { say(okMsg); }, fallback);
  else fallback();
}
document.getElementById('copyDesc').onclick = function () { copy(D.description, 'Descripción copiada. Pégala en el modo código de CurseForge.'); };
document.getElementById('copySum').onclick = function () { copy(D.summary, 'Resumen copiado.'); };
</script>
</body>
</html>
`;
fs.writeFileSync(path.join(OUT, 'index.html'), page);

// Desktop copies of the text
if (fs.existsSync(DESK)) {
  fs.writeFileSync(path.join(DESK, 'descripcion.html'), description + '\n');
  fs.writeFileSync(path.join(DESK, 'descripcion.txt'), description + '\n');
}
console.log('page: ' + path.join(OUT, 'index.html') + ' (' + shots.length + ' images, version ' + version + ')');
