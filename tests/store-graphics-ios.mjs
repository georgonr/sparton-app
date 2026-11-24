// Snímky do App Store zo smoke testu na iOS simulátore (iPhone 6,9": 1320×2868, bez alfa kanála) v sk/cs/en.
// Každá snímka je skutočná obrazovka appky z daného jazyka; okolo nej titulok vo vizuáli spartON
// (tmavozelené pozadie, Barlow Condensed, limetkový akcent – rovnako ako grafika pre Google Play).
// Spustenie: node tests/store-graphics-ios.mjs <priečinok so snímkami> <výstup>
import { chromium } from 'playwright'
import { readdirSync, readFileSync, mkdirSync, copyFileSync } from 'node:fs'
import { join } from 'node:path'

const [src = 'smoke-out/screens', out = 'store-ios'] = process.argv.slice(2)
const files = readdirSync(src).filter((f) => f.endsWith('.png'))
const find = (key, lang) => files.find((f) => f.endsWith(lang === 'sk' ? `-${key}.png` : `-${key}-${lang}.png`))
const W = 1320
const H = 2868

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

const FONT = `<link rel="preconnect" href="https://fonts.googleapis.com"><link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@700;800&family=Inter:wght@500;700&display=swap" rel="stylesheet">`
const BALL = `<svg viewBox="0 0 40 40" width="100%" height="100%"><circle cx="20" cy="20" r="19" fill="#168342"/><circle cx="20" cy="20" r="11.5" fill="#fff"/><path d="M20 12.5l4.2 3-1.6 5h-5.2l-1.6-5z" fill="#13201a"/><path d="M20 8.5v4M28.7 14.6l-4.5 1M27 26.8l-4.4-6.3M13 26.8l4.4-6.3M11.3 14.6l4.5 1" stroke="#13201a" stroke-width="1.4" stroke-linecap="round"/><path d="M33 9.5a16 16 0 0 1 3 8" stroke="#ff8137" stroke-width="2.6" stroke-linecap="round" fill="none"/></svg>`
const dataUrl = (f) => `data:image/png;base64,${readFileSync(join(src, f)).toString('base64')}`

function html(img, title, n, total) {
  return `<!doctype html><html><head><meta charset="utf-8">${FONT}<style>
  *{box-sizing:border-box;margin:0}
  body{width:${W}px;height:${H}px;overflow:hidden;font-family:Inter,sans-serif;
    background:radial-gradient(1500px 1100px at 85% -10%,#1f9a52 0%,rgba(31,154,82,0) 60%),linear-gradient(170deg,#0b2a19 0%,#06140c 100%);color:#fff;position:relative}
  .brand{position:absolute;top:150px;left:104px;display:flex;align-items:center;gap:22px;font-weight:800;font-size:54px;letter-spacing:-.02em}
  .brand i{display:block;width:78px;height:78px}
  .brand b{color:#c8f560}
  .n{position:absolute;top:166px;right:104px;font:700 38px 'Barlow Condensed';color:rgba(200,245,96,.75);letter-spacing:.08em}
  h1{position:absolute;top:290px;left:104px;right:104px;font:800 132px/0.95 'Barlow Condensed',sans-serif;text-transform:uppercase}
  h1 span{color:#c8f560}
  .arc{position:absolute;right:-150px;top:640px;width:640px;height:640px;border-radius:50%;border:32px solid #ff8137;border-left-color:transparent;border-bottom-color:transparent;transform:rotate(18deg);opacity:.9}
  .phone{position:absolute;left:50%;bottom:-150px;transform:translateX(-50%);width:960px;height:2086px;border-radius:120px;background:#111;padding:22px;
    box-shadow:0 60px 140px rgba(0,0,0,.55),0 0 0 4px rgba(255,255,255,.08) inset}
  .phone img{width:100%;height:100%;object-fit:cover;object-position:top;border-radius:98px;display:block}
  </style></head><body>
  <div class="brand"><i>${BALL}</i><span>spart<b>ON</b></span></div>
  <div class="n">${String(n).padStart(2, '0')} / ${String(total).padStart(2, '0')}</div>
  <h1>${title.replace(/^(\S+)/, '<span>$1</span>')}</h1>
  <div class="arc"></div>
  <div class="phone"><img src="${img}"></div>
  </body></html>`
}

const browser = await chromium.launch()
const page = await browser.newPage({ deviceScaleFactor: 1, viewport: { width: W, height: H } })
let made = 0
for (const lang of LANGS) {
  const dir = join(out, 'iphone-6.9', lang)
  const raw = join(out, 'iphone-6.9-raw', lang)
  mkdirSync(dir, { recursive: true })
  mkdirSync(raw, { recursive: true })
  const avail = SHOTS.filter(([k]) => find(k, lang))
  let n = 0
  for (const [key, ...titles] of avail) {
    const f = find(key, lang)
    n++
    const name = `${String(n).padStart(2, '0')}-${key}.png`
    copyFileSync(join(src, f), join(raw, name))
    await page.setContent(html(dataUrl(f), titles[LANGS.indexOf(lang)], n, avail.length), { waitUntil: 'networkidle' })
    await page.evaluate(() => document.fonts.ready)
    // JPEG nemá alfa kanál (App Store ho nepovoľuje); PNG z Chromia môže mať alfa
    await page.screenshot({ path: join(dir, name.replace('.png', '.jpg')), type: 'jpeg', quality: 92 })
    made++
  }
  for (const [k] of SHOTS) if (!find(k, lang)) console.log(`chýba snímka ${k} (${lang})`)
}
await browser.close()
console.log(`hotovo: ${made} obrázkov ${W}×${H}`)
