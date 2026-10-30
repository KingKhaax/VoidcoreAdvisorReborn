// Replaces a screenshot of the CurseForge description with a new one, safely.
//   node tools/replace_description_image.js <current file in docs/screenshots> <path of the new image>
// CurseForge (and GitHub) cache an image by its address, so the new image gets a new name (-v4, -v5...),
// every reference in docs/curseforge-description.html is pointed at it, and the old image is kept
// but marked as unused. After that: commit and push (the new image must be on GitHub before the
// description is pasted), then run tools/build_description_page.js and publish the page.
const fs = require('fs');
const path = require('path');

const ROOT = path.resolve(__dirname, '..');
const SHOTS = path.join(ROOT, 'docs', 'screenshots');
const RAW = 'https://raw.githubusercontent.com/KingKhaax/VoidcoreAdvisorReborn/master/docs/screenshots/';
const [oldName, newPath] = process.argv.slice(2);
if (!oldName || !newPath) {
  console.error('Usage: node tools/replace_description_image.js <current file name> <new image path>');
  process.exit(1);
}
if (!fs.existsSync(path.join(SHOTS, oldName))) throw new Error('No such screenshot: ' + oldName);
if (!fs.existsSync(newPath)) throw new Error('No such file: ' + newPath);
const ext = path.extname(newPath).toLowerCase();
if (!['.png', '.jpg', '.jpeg'].includes(ext)) throw new Error('Use a .png or .jpg image');

// base name without extension and without a -vN suffix, then the next free version
const m = path.basename(oldName, path.extname(oldName)).match(/^(.*?)(?:-v(\d+))?$/);
let n = (m[2] ? parseInt(m[2], 10) : 1) + 1;
let newName;
do {
  newName = `${m[1]}-v${n++}${ext}`;
} while (fs.existsSync(path.join(SHOTS, newName)));
fs.copyFileSync(newPath, path.join(SHOTS, newName));

const dpath = path.join(ROOT, 'docs', 'curseforge-description.html');
const raw = fs.readFileSync(dpath, 'utf8');
const crlf = raw.includes('\r\n');
const text = raw.replace(/\r\n/g, '\n');
const refs = text.split(RAW + oldName).length - 1;
const updated = text.split(RAW + oldName).join(RAW + newName);
fs.writeFileSync(dpath, crlf ? updated.replace(/\n/g, '\r\n') : updated);

const ipath = path.join(ROOT, 'docs', 'description-images.json');
const images = JSON.parse(fs.readFileSync(ipath, 'utf8'));
delete images[newName];
images[oldName] = {status: 'unused', note: 'Sustituida por ' + newName};
images[newName] = {status: 'ok', note: ''};
fs.writeFileSync(ipath, JSON.stringify(images, null, 2) + '\n');

console.log(`${oldName} -> ${newName} (${refs} reference${refs === 1 ? '' : 's'} updated in the description)`);
console.log('Next: git add docs && git commit && git push, then node tools/build_description_page.js and publish the page.');
