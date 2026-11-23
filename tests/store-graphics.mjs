// Grafika do Google Play zo snímok emulátora (smoke test): 8 snímok telefónu 1080×1920 v sk/cs/en
// a grafika funkcie 1024×500. Vizuál spartON: tmavozelené pozadie, Barlow Condensed, limetkový akcent.
// Spustenie: node tests/store-graphics.mjs <priečinok so snímkami> <výstup>
import { chromium } from 'playwright'
import { readdirSync, readFileSync, mkdirSync } from 'node:fs'
import { join } from 'node:path'

const [src = 'smoke-out/screens', out = 'store-out'] = process.argv.slice(2)
const files = readdirSync(src).filter((f) => f.endsWith('.png'))
const find = (key) => files.find((f) => f.includes(`-${key}.png`))

const SHOTS = [
  ['prehlad', 'Celý klub na jednom mieste', 'Celý klub na jednom místě', 'Your whole club in one place'],
  ['kalendar', 'Tréningy a zápasy v jednom kalendári', 'Tréninky a zápasy v jednom kalendáři', 'Trainings and matches in one calendar'],
  ['clenovia', 'Členovia, tímy a rodičia', 'Členové, týmy a rodiče', 'Members, teams and parents'],
  ['platby', 'Členské príspevky pod kontrolou', 'Členské příspěvky pod kontrolou', 'Membership fees under control'],
  ['spravy', 'Správy pre celý tím naraz', 'Zprávy pro celý tým najednou', 'Message the whole team at once'],
  ['nastenka', 'Nástenka a fotky z klubu', 'Nástěnka a fotky z klubu', 'Club wall and photos'],
  ['statistiky', 'Dochádzka a štatistiky', 'Docházka a statistiky', 'Attendance and stats'],
  ['prihlasenie', 'Prihlás sa e-mailom alebo cez Google', 'Přihlas se e-mailem nebo přes Google', 'Sign in with email or Google'],
]
const LANGS = ['sk', 'cs', 'en']
const TAG = { sk: 'Tvoj klub v mobile', cs: 'Tvůj klub v mobilu', en: 'Your club in your pocket' }

const FONT = `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@700;800&family=Inter:wght@500;700&display=swap" rel="stylesheet">`

const BALL = `<svg viewBox="0 0 40 40" width="100%" height="100%"><circle cx="20" cy="20" r="19" fill="#168342"/><circle cx="20" cy="20" r="11.5" fill="#fff"/><path d="M20 12.5l4.2 3-1.6 5h-5.2l-1.6-5z" fill="#13201a"/><path d="M20 8.5v4M28.7 14.6l-4.5 1M27 26.8l-4.4-6.3M13 26.8l4.4-6.3M11.3 14.6l4.5 1" stroke="#13201a" stroke-width="1.4" stroke-linecap="round"/><path d="M33 9.5a16 16 0 0 1 3 8" stroke="#ff8137" stroke-width="2.6" stroke-linecap="round" fill="none"/></svg>`

const dataUrl = (f) => `data:image/png;base64,${readFileSync(join(src, f)).toString('base64')}`

function phoneHtml(img, title, n) {
  return `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{box-sizing:border-box;margin:0}
  body{width:1080px;height:1920px;overflow:hidden;font-family:Inter,sans-serif;
    background:radial-gradient(1200px 900px at 85% -10%,#1f9a52 0%,rgba(31,154,82,0) 60%),linear-gradient(170deg,#0b2a19 0%,#06140c 100%);color:#fff;position:relative}
  .brand{position:absolute;top:84px;left:84px;display:flex;align-items:center;gap:18px;font-weight:800;font-size:44px;letter-spacing:-.02em}
  .brand i{display:block;width:64px;height:64px}
  .brand b{color:#c8f560}
  .n{position:absolute;top:96px;right:84px;font:700 30px 'Barlow Condensed';color:rgba(200,245,96,.75);letter-spacing:.08em}
  h1{position:absolute;top:196px;left:84px;right:84px;font:800 104px/0.95 'Barlow Condensed',sans-serif;text-transform:uppercase;letter-spacing:-.005em}
  h1 span{color:#c8f560}
  .arc{position:absolute;right:-120px;top:420px;width:520px;height:520px;border-radius:50%;border:26px solid #ff8137;border-left-color:transparent;border-bottom-color:transparent;transform:rotate(18deg);opacity:.9}
  .phone{position:absolute;left:50%;bottom:-120px;transform:translateX(-50%);width:760px;height:1520px;border-radius:72px;background:#111;padding:18px;
    box-shadow:0 50px 120px rgba(0,0,0,.55),0 0 0 3px rgba(255,255,255,.08) inset}
  .phone img{width:100%;height:100%;object-fit:cover;object-position:top;border-radius:56px;display:block}
  </style></head><body>
  <div class="brand"><i>${BALL}</i><span>spart<b>ON</b></span></div>
  <div class="n">${String(n).padStart(2, '0')} / 08</div>
  <h1>${title.replace(/^(\S+)/, '<span>$1</span>')}</h1>
  <div class="arc"></div>
  <div class="phone"><img src="${img}"></div>
  </body></html>`
}

function featureHtml(img, tag) {
  return `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{box-sizing:border-box;margin:0}
  body{width:1024px;height:500px;overflow:hidden;font-family:Inter,sans-serif;position:relative;color:#fff;
    background:radial-gradient(700px 500px at 90% 10%,#1f9a52 0%,rgba(31,154,82,0) 65%),linear-gradient(160deg,#0b2a19,#06140c)}
  .logo{position:absolute;left:72px;top:150px;display:flex;align-items:center;gap:22px}
  .logo i{width:104px;height:104px;display:block}
  .logo span{font-weight:800;font-size:84px;letter-spacing:-.03em}
  .logo b{color:#c8f560}
  p{position:absolute;left:76px;top:282px;font:800 58px/1 'Barlow Condensed',sans-serif;text-transform:uppercase;color:#e8f2ea}
  .arc{position:absolute;left:330px;top:40px;width:120px;height:120px;border-radius:50%;border:12px solid #ff8137;border-left-color:transparent;border-bottom-color:transparent;transform:rotate(10deg)}
  .phone{position:absolute;right:70px;top:40px;width:300px;height:600px;border-radius:40px;background:#111;padding:10px;transform:rotate(6deg);box-shadow:0 30px 70px rgba(0,0,0,.5)}
  .phone img{width:100%;height:100%;object-fit:cover;object-position:top;border-radius:31px}
  </style></head><body>
  <div class="arc"></div>
  <div class="logo"><i>${BALL}</i><span>spart<b>ON</b></span></div>
  <p>${tag}</p>
  <div class="phone"><img src="${img}"></div>
  </body></html>`
}

const browser = await chromium.launch()
const page = await browser.newPage({ deviceScaleFactor: 1 })
let made = 0
for (const lang of LANGS) {
  const dir = join(out, 'screens', lang)
  mkdirSync(dir, { recursive: true })
  let n = 0
  for (const [key, ...titles] of SHOTS) {
    const f = find(key)
    if (!f) {
      console.log(`chýba snímka ${key}`)
      continue
    }
    n++
    await page.setViewportSize({ width: 1080, height: 1920 })
    await page.setContent(phoneHtml(dataUrl(f), titles[LANGS.indexOf(lang)], n), { waitUntil: 'networkidle' })
    await page.evaluate(() => document.fonts.ready)
    await page.screenshot({ path: join(dir, `${String(n).padStart(2, '0')}-${key}.png`) })
    made++
  }
}
const dash = find('prehlad') || files[0]
if (dash) {
  for (const lang of LANGS) {
    await page.setViewportSize({ width: 1024, height: 500 })
    await page.setContent(featureHtml(dataUrl(dash), TAG[lang]), { waitUntil: 'networkidle' })
    await page.evaluate(() => document.fonts.ready)
    await page.screenshot({ path: join(out, `feature-1024x500-${lang}.png`) })
    made++
  }
}
await browser.close()
console.log(`hotovo: ${made} obrázkov`)
