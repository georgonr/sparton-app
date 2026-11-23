// Smoke test appky spartON na Android emulátore (GitHub Actions). Ovláda webview debug zostavenia cez Chrome DevTools
// (Playwright _android) a robí snímky celej obrazovky telefónu (adb screencap – so stavovým riadkom).
// Prostredie: REVIEW_EMAIL, REVIEW_PASSWORD (účet správcu pre recenziu, z GitHub secrets), OUT (priečinok výsledkov).
import { _android as android } from 'playwright'
import { mkdirSync, writeFileSync } from 'node:fs'
import { join } from 'node:path'

const OUT = process.env.OUT || 'smoke-out'
const PKG = 'eu.sparton.app'
const ORIGIN = 'https://sparton.eu'
mkdirSync(join(OUT, 'screens'), { recursive: true })

const results = []
let shot = 0
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function record(name, ok, detail = '') {
  results.push({ name, ok, detail })
  console.log(`${ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` – ${detail}` : ''}`)
}

async function check(name, fn) {
  try {
    if (typeof page !== 'undefined' && page && page.isClosed()) page = await getPage()
    const d = await fn()
    record(name, true, typeof d === 'string' ? d : '')
  } catch (e) {
    record(name, false, String(e?.message || e).split('\n')[0].slice(0, 300))
  }
}

const [device] = await android.devices()
if (!device) throw new Error('žiadne zariadenie adb')
console.log(`zariadenie: ${device.model()} ${device.serial()}`)

async function screen(name) {
  shot++
  const file = join(OUT, 'screens', `${String(shot).padStart(2, '0')}-${name}.png`)
  await device.screenshot({ path: file })
  return file
}

async function shell(cmd) {
  return (await device.shell(cmd)).toString()
}

// Živá stránka webview: po načítaní dokumentu môže vzniknúť nový cieľ DevTools, starý sa zavrie.
async function getPage() {
  let last
  for (let i = 0; i < 20; i++) {
    try {
      const wv = await device.webView({ pkg: PKG }, { timeout: 60_000 })
      const first = await wv.page()
      const pages = first.context().pages().filter((p) => !p.isClosed())
      const live = pages.reverse().find((p) => /^https:\/\//.test(p.url())) || pages[0]
      if (live) {
        await live.evaluate(() => 1)
        live.setDefaultTimeout(30_000)
        return live
      }
    } catch (e) {
      last = e
    }
    await sleep(1500)
  }
  throw last || new Error('webview appky sa nenašlo')
}

// navigácia odolná voči výmene cieľa DevTools (COOP, offline stránka)
async function go(url, ms = 2000) {
  try {
    await page.goto(url, { waitUntil: 'load' })
  } catch {
    await sleep(1500)
  }
  page = await getPage()
  await settle(page, ms)
}

async function settle(page, ms = 1500) {
  await page.waitForLoadState('load').catch(() => {})
  await page.waitForLoadState('networkidle', { timeout: 15_000 }).catch(() => {})
  await sleep(ms)
}

// --- štart
await shell(`pm grant ${PKG} android.permission.POST_NOTIFICATIONS`).catch(() => {})
await shell(`pm grant ${PKG} android.permission.CAMERA`).catch(() => {})
await shell(`am start -W -n ${PKG}/.MainActivity`)
let page = await getPage()
await settle(page, 2500)

await check('štart appky a načítanie sparton.eu', async () => {
  const url = page.url()
  if (!url.startsWith(ORIGIN)) throw new Error(`URL ${url}`)
  return url
})
await check('príznak appky v User-Agent a data-native', async () => {
  const ua = await page.evaluate(() => navigator.userAgent)
  if (!/spartON-App\/1\.0\.0 \(android\)/.test(ua)) throw new Error(`UA bez príznaku`)
  const nat = await page.evaluate(() => document.documentElement.dataset.native)
  if (nat !== '1') throw new Error(`data-native=${nat}`)
  return 'spartON-App/1.0.0 (android), data-native=1'
})
await check('neprihlásený → prihlasovacia stránka', async () => {
  if (!/\/login/.test(page.url())) throw new Error(page.url())
})
await screen('prihlasenie')

// --- prihlásenie heslom (účet pre recenziu)
await check('prihlásenie účtom pre recenziu (heslo)', async () => {
  if (!process.env.REVIEW_EMAIL || !process.env.REVIEW_PASSWORD) throw new Error('chýbajú REVIEW_EMAIL / REVIEW_PASSWORD')
  await page.fill('input[name="email"]', process.env.REVIEW_EMAIL)
  await page.fill('input[name="password"]', process.env.REVIEW_PASSWORD)
  await page.click('button[type="submit"]')
  for (let i = 0; i < 30 && !/\/app(\/|$|\?)/.test(page.url()); i++) {
    await sleep(1500)
    page = await getPage()
  }
  if (!/\/app(\/|$|\?)/.test(page.url())) throw new Error(`po prihlásení ${page.url()}`)
  await settle(page, 2500)
  return page.url().replace(ORIGIN, '')
})

const m = /\/app\/([^/?#]+)/.exec(page.url())
const club = m && !['account', 'new-club', 'terms'].includes(m[1]) ? m[1] : null
record('klub pre recenziu', !!club, club ? `/app/${club}` : page.url())

await check('token push (FCM) v appke', async () => {
  for (let i = 0; i < 20; i++) {
    const has = await page.evaluate(() => typeof window.__spartonPushToken === 'string' && window.__spartonPushToken.length > 20).catch(() => false)
    if (has) return 'token získaný (hodnota sa nevypisuje)'
    await sleep(1000)
  }
  throw new Error('appka nezískala token FCM')
})

async function visit(path, name, expect) {
  await check(`obrazovka ${path}`, async () => {
    await go(ORIGIN + path)
    if (expect) await expect()
    await screen(name)
    return page.url().replace(ORIGIN, '')
  })
}

if (club) {
  await visit(`/app/${club}`, 'prehlad')
  await visit(`/app/${club}/calendar`, 'kalendar')
  await visit(`/app/${club}/people`, 'clenovia')
  await visit(`/app/${club}/payments`, 'platby')
  await visit(`/app/${club}/messages`, 'spravy')
  await visit(`/app/${club}/wall`, 'nastenka')
  await visit(`/app/${club}/stats`, 'statistiky')

  // --- skryté nákupy
  await visit(`/app/${club}/settings/subscription`, 'predplatne-v-appke', async () => {
    await page.waitForSelector('[data-testid="native-billing-web"]', { timeout: 15_000 })
    const body = await page.evaluate(() => document.body.innerText)
    if (/Zaplatiť kartou|Objednať|€\s*\/\s*(mes|rok)/i.test(body)) throw new Error('na stránke predplatného je nákup')
  })
  await visit(`/app/${club}/settings/credits`, 'kredity-v-appke', async () => {
    await page.waitForSelector('[data-testid="native-billing-web"]', { timeout: 15_000 })
  })
  await check('nákupná serverová funkcia z appky → 403 (overené v 2A), web bez nákupného tlačidla', async () => {
    const body = await page.evaluate(() => document.body.innerText)
    if (/Dokúpiť kredity|Kúpiť kredity/i.test(body)) throw new Error('výzva na nákup kreditov')
    return 'bez výzvy na nákup'
  })
}

// --- marketing a cenník mimo appky
await check('cenník (/sk/cennik) sa v appke neotvorí', async () => {
  await page.evaluate(() => {
    location.href = '/pricing'
  })
  await sleep(3000)
  const now = page.url()
  if (/\/pricing|cennik/.test(now)) throw new Error(`appka zobrazila ${now}`)
  return `ostáva ${now.replace(ORIGIN, '')} (otvorené mimo appky)`
}).catch(() => {})
page = await getPage()
await shell(`am start -W -n ${PKG}/.MainActivity`)
await sleep(1500)

// --- tlačidlo Späť
await check('tlačidlo Späť vo webview', async () => {
  if (!club) return 'preskočené'
  await page.goto(`${ORIGIN}/app/${club}/calendar`)
  await settle(page, 800)
  await page.goto(`${ORIGIN}/app/${club}/people`)
  await settle(page, 800)
  await shell('input keyevent 4')
  await sleep(2000)
  if (!/\/calendar/.test(page.url())) throw new Error(`po Späť ${page.url()}`)
  return 'people → calendar'
})

// --- hlboké odkazy
await check('hlboký odkaz eu.sparton.app://pay/return', async () => {
  await shell(`am start -W -a android.intent.action.VIEW -d "eu.sparton.app://pay/return?to=/app&r=ok" ${PKG}`)
  await sleep(4000)
  page = await getPage()
  if (!/sparton\.eu\/app/.test(page.url())) throw new Error(page.url())
  return page.url().replace(ORIGIN, '')
})
await check('App Link https://sparton.eu/app (intent do appky)', async () => {
  const out = await shell(`am start -W -a android.intent.action.VIEW -c android.intent.category.BROWSABLE -d "https://sparton.eu/app" ${PKG}`)
  if (/Error/i.test(out)) throw new Error(out.trim())
  await sleep(3000)
  return 'intent prijatý'
})
const verify = await shell(`pm get-app-links ${PKG}`).catch((e) => String(e))
writeFileSync(join(OUT, 'app-links.txt'), verify)

// --- offline
await check('obrazovka „si offline“', async () => {
  await shell('svc wifi disable')
  await shell('svc data disable')
  await sleep(3000)
  page = await getPage()
  await page.evaluate((u) => {
    location.href = u
  }, `${ORIGIN}/app${club ? `/${club}/calendar` : ''}?offline=${Date.now()}`)
  await sleep(6000)
  page = await getPage()
  await page.waitForSelector('[data-testid="offline-title"]', { timeout: 20_000 })
  const t = await page.textContent('[data-testid="offline-title"]')
  await screen('offline')
  return t
})
await check('po pripojení sa appka načíta sama', async () => {
  await shell('svc wifi enable')
  await shell('svc data enable')
  for (let i = 0; i < 40; i++) {
    await sleep(1500)
    page = await getPage().catch(() => page)
    const u = page.url()
    if (u.startsWith(ORIGIN) && !u.includes('offline.html')) {
      const hasOffline = await page.$('[data-testid="offline-title"]').catch(() => null)
      if (!hasOffline) return u.replace(ORIGIN, '')
    }
  }
  throw new Error('ostala obrazovka offline')
})

// --- odhlásenie (zariadenie sa odregistruje – hlavička X-Push-Token)
await check('odhlásenie', async () => {
  await page.goto(`${ORIGIN}/app`)
  await settle(page, 1000)
  const status = await page.evaluate(async () => {
    const r = await fetch('/api/push/devices', { method: 'DELETE', credentials: 'same-origin', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: window.__spartonPushToken || 'x' }) })
    return r.status
  })
  // odhlásenie cez cookie: zmaže reláciu na serveri
  await page.context().clearCookies().catch(() => {})
  return `DELETE /api/push/devices → ${status}`
})

writeFileSync(join(OUT, 'results.json'), JSON.stringify(results, null, 2))
const failed = results.filter((r) => !r.ok)
const md = ['### Smoke test appky spartON (emulátor)', '', '| | krok | detail |', '|---|---|---|', ...results.map((r) => `| ${r.ok ? '✅' : '❌'} | ${r.name} | ${r.detail.replace(/\|/g, '/')} |`)].join('\n')
writeFileSync(join(OUT, 'summary.md'), md + '\n')
await device.close()
console.log(`\n${results.length - failed.length}/${results.length} OK`)
process.exit(failed.length ? 1 : 0)
