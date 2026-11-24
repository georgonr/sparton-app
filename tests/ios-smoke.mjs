// Smoke test appky spartON na iOS simulátore (GitHub Actions, macOS). Ovláda appku cez Appium XCUITest
// (natívne dialógy, Face ID) a jej webview cez Web Inspector (debug zostavenie má isInspectable). Snímky celej
// obrazovky robí `xcrun simctl io screenshot` (rozlíšenie zariadenia, stavový riadok 9:41).
// Prostredie: UDID, APP (cesta k App.app), REVIEW_EMAIL, REVIEW_PASSWORD, voliteľne CHILD_EMAIL, CHILD_PASSWORD, OUT.
// Heslá idú len do polí formulára – nikam sa nevypisujú (Appium log sa neukladá ako artefakt).
import { remote } from 'webdriverio'
import { execFileSync } from 'node:child_process'
import { mkdirSync, writeFileSync, readFileSync, renameSync, existsSync, rmSync } from 'node:fs'
import { join } from 'node:path'
import { promises as dns } from 'node:dns'

const OUT = process.env.OUT || 'smoke-out'
const UDID = process.env.UDID
const BUNDLE = 'eu.sparton.app'
const ORIGIN = 'https://sparton.eu'
mkdirSync(join(OUT, 'screens'), { recursive: true })
const results = []
let shot = 0
const sleep = (ms) => new Promise((r) => setTimeout(r, ms))

function record(name, ok, detail = '') {
  results.push({ name, ok: ok === true, skipped: ok === null, detail })
  console.log(`${ok === null ? 'SKIP' : ok ? 'OK  ' : 'FAIL'} ${name}${detail ? ` – ${detail}` : ''}`)
}
class Skip extends Error {}
async function check(name, fn) {
  try {
    const d = await Promise.race([fn(), sleep(150_000).then(() => Promise.reject(new Error('časový limit kroku 150 s')))])
    record(name, true, typeof d === 'string' ? d : '')
  } catch (e) {
    if (e instanceof Skip) record(name, null, e.message)
    else record(name, false, String(e?.message || e).split('\n')[0].slice(0, 300))
  }
}

function screen(name) {
  shot++
  const file = join(OUT, 'screens', `${String(shot).padStart(2, '0')}-${name}.png`)
  execFileSync('xcrun', ['simctl', 'io', UDID, 'screenshot', '--type=png', file], { stdio: 'ignore' })
  return file
}

console.log('Appium: vytváram reláciu (simulátor, appka, WebDriverAgent)…')
const driver = await remote({
  hostname: '127.0.0.1',
  port: 4723,
  logLevel: 'error',
  connectionRetryTimeout: 420_000,
  connectionRetryCount: 1,
  capabilities: {
    ...(process.env.WDA_DD ? { 'appium:usePrebuiltWDA': true, 'appium:derivedDataPath': process.env.WDA_DD } : {}),
    'appium:showXcodeLog': true,
    platformName: 'iOS',
    'appium:automationName': 'XCUITest',
    'appium:udid': UDID,
    'appium:app': process.env.APP,
    'appium:bundleId': BUNDLE,
    'appium:language': process.env.SIM_LANG || 'sk',
    'appium:locale': process.env.SIM_LOCALE || 'sk_SK',
    'appium:wdaLaunchTimeout': 600_000,
    'appium:wdaConnectionTimeout': 600_000,
    'appium:newCommandTimeout': 900,
    'appium:webviewConnectTimeout': 60_000,
    'appium:includeSafariInWebviews': false,
    'appium:connectHardwareKeyboard': false,
    'appium:autoAcceptAlerts': false,
  },
})

// --- pomocníci: webview cez testovací most ladiaceho zostavenia (Documents/smoke v kontajneri appky),
// natívne dialógy a Face ID cez Appium. Web Inspector (kontext WEBVIEW) sa v simulátore iOS 26 neukázal.
const native = () => driver.switchContext('NATIVE_APP')
let seq = 0
function smokeDir() {
  const c = execFileSync('xcrun', ['simctl', 'get_app_container', UDID, BUNDLE, 'data'], { encoding: 'utf8' }).trim()
  const d = join(c, 'Documents', 'smoke')
  mkdirSync(d, { recursive: true })
  return d
}
async function js(fn, ...args) {
  const id = `${Date.now()}-${++seq}`
  const dir = smokeDir()
  const body = `const r = await (${fn.toString()})(...__a); return r === undefined ? null : r`
  const tmp = join(dir, `tmp-${id}`)
  writeFileSync(tmp, JSON.stringify({ id, body, args: { __a: args } }))
  renameSync(tmp, join(dir, `cmd-${String(seq).padStart(6, '0')}-${id}.json`))
  const res = join(dir, `res-${id}.json`)
  for (let i = 0; i < 120; i++) {
    await sleep(250)
    if (existsSync(res)) {
      const o = JSON.parse(readFileSync(res, 'utf8'))
      rmSync(res, { force: true })
      if (!o.ok) throw new Error(`JS: ${o.error}`)
      return o.value
    }
  }
  throw new Error('appka neodpovedá (testovací most)')
}
const url = () => js(() => location.href)
async function settle(ms = 1500) {
  for (let i = 0; i < 40; i++) {
    const st = await js(() => document.readyState).catch(() => '')
    if (st === 'complete') break
    await sleep(500)
  }
  await sleep(ms)
}
async function go(path, ms = 2500) {
  const target = ORIGIN + path
  const want = target.split('#')[0].replace(/\/$/, '')
  for (let attempt = 0; attempt < 2; attempt++) {
    await js((u) => {
      setTimeout(() => {
        location.href = u
      }, 0)
      return true
    }, target).catch(() => {})
    for (let i = 0; i < 40; i++) {
      await sleep(500)
      const u = await url().catch(() => '')
      if (u.split('#')[0].replace(/\/$/, '').startsWith(want) && (await js(() => document.readyState).catch(() => '')) === 'complete') {
        await settle(ms)
        return
      }
    }
    console.log(`navigácia na ${path} sa nedokončila, opakujem`)
  }
  await settle(ms)
}
async function waitUrl(re, tries = 30) {
  for (let i = 0; i < tries; i++) {
    const u = await url().catch(() => '')
    if (re.test(u)) return u
    await sleep(1500)
  }
  throw new Error(`URL ${await url().catch(() => '?')}`)
}
async function waitSel(sel, ms = 20_000) {
  const end = Date.now() + ms
  while (Date.now() < end) {
    if (await js((s) => !!document.querySelector(s), sel).catch(() => false)) return
    await sleep(700)
  }
  throw new Error(`chýba ${sel}`)
}
async function tapNative(labels, timeout = 15_000) {
  await native()
  const end = Date.now() + timeout
  while (Date.now() < end) {
    for (const l of labels) {
      const el = await driver.$(`-ios predicate string:type == "XCUIElementTypeButton" AND label == "${l}"`)
      if (await el.isExisting().catch(() => false)) {
        await el.click()
        return l
      }
    }
    await sleep(700)
  }
  return null
}
async function nativeExists(id) {
  await native()
  const el = await driver.$(`~${id}`)
  return (await el.isExisting().catch(() => false)) && (await el.isDisplayed().catch(() => false))
}
async function login(email, password) {
  await go('/login', 1500)
  await waitSel('input[name="email"]')
  // React: hodnota cez natívny setter + udalosť input; potom odoslanie formulára tlačidlom
  await js(
    (e, p) => {
      const set = Object.getOwnPropertyDescriptor(HTMLInputElement.prototype, 'value').set
      for (const [n, v] of [['email', e], ['password', p]]) {
        const el = document.querySelector(`input[name="${n}"]`)
        set.call(el, v)
        el.dispatchEvent(new Event('input', { bubbles: true }))
        el.dispatchEvent(new Event('change', { bubbles: true }))
      }
      setTimeout(() => document.querySelector('button[type="submit"]').click(), 300)
      return true
    },
    email,
    password,
  )
}
async function blur() {
  await js(() => document.activeElement && document.activeElement.blur()).catch(() => {})
  await sleep(800)
}

const ips = [...(await dns.resolve4('sparton.eu').catch(() => [])), ...(await dns.resolve6('sparton.eu').catch(() => []))]
const pf = (rules) => execFileSync('sudo', ['pfctl', '-a', 'com.apple/sparton', '-f', '-'], { input: rules, stdio: ['pipe', 'ignore', 'ignore'] })
const NOQUIC = ips.map((ip) => `block return out quick ${ip.includes(':') ? 'inet6' : 'inet'} proto udp from any to ${ip} port 443\n`).join('')
try {
  execFileSync('sudo', ['pfctl', '-E'], { stdio: 'ignore' })
  pf(NOQUIC)
  console.log('pf: UDP 443 na sparton.eu blokované (HTTP/3 → TCP)')
} catch (e) {
  console.log('pf nepodarilo sa nastaviť', e.message)
}
console.log('Appium: relácia beží')
await sleep(6000)
screen('diagnostika-start')
// --- Face ID v simulátore zapnuté (ponuka po prihlásení, zámok pri štarte)
await driver.execute('mobile: enrollBiometric', { isEnabled: true }).catch((e) => console.log('enrollBiometric', e.message))
await sleep(2000)

// --- štart
await check('štart appky a načítanie sparton.eu', async () => {
  const u = await waitUrl(/^https:\/\/sparton\.eu\//)
  await settle(2500)
  return u
})
await check('príznak appky v User-Agent a data-native', async () => {
  const ua = await js(() => navigator.userAgent)
  if (!/spartON-App\/1\.0\.0 \(ios\)/.test(ua)) throw new Error('UA bez príznaku')
  const nat = await js(() => document.documentElement.dataset.native)
  if (nat !== '1') throw new Error(`data-native=${nat}`)
  return 'spartON-App/1.0.0 (ios), data-native=1'
})
await check('neprihlásený → prihlasovacia stránka', async () => {
  const u = await waitUrl(/\/login/, 10)
  return u.replace(ORIGIN, '')
})
await check('bez cookie lišty a bez analytiky v appke', async () => {
  if (await js(() => !!document.querySelector('[data-testid="cookie-banner"]'))) throw new Error('cookie lišta je viditeľná')
  if (!(await js(() => /sparton_consent=2\.000\./.test(document.cookie)))) throw new Error('súhlas „len nevyhnutné“ nie je nastavený')
  const n = await js(() => performance.getEntriesByType('resource').filter((e) => /googletagmanager|google-analytics|facebook|doubleclick/.test(e.name)).length)
  if (n) throw new Error(`sledovacích požiadaviek: ${n}`)
  const blocked = await js(() =>
    fetch('https://www.googletagmanager.com/gtag/js?id=G-TEST', { mode: 'no-cors' }).then(
      () => false,
      () => true,
    ),
  )
  if (!blocked) throw new Error('požiadavka na googletagmanager.com nebola zablokovaná')
  return 'súhlas len nevyhnutné, 0 sledovacích požiadaviek, blokovanie overené'
})
await check('Google tlačidlo na prihlásení, Apple tlačidlo len po zapnutí v Superadmine', async () => {
  const g = await js(() => !!document.querySelector('[data-testid="google-button"]'))
  const a = await js(() => !!document.querySelector('a[href^="/auth/apple/start"]'))
  if (!g) throw new Error('chýba tlačidlo Google')
  return `Google áno, Apple ${a ? 'áno (zapnuté)' : 'nie (Sign in with Apple je na serveri vypnuté)'}`
})
await check('„Pokračovať cez Google“ zachytí appka (bez webového OAuth vo webview)', async () => {
  await js(() => document.querySelector('[data-testid="google-button"]').click())
  await sleep(3500)
  const u = await url()
  if (/accounts\.google\.com/.test(u)) throw new Error('webview otvorilo Google OAuth')
  if (!/[?&]google=off/.test(u)) throw new Error(`čakal som ?google=off (iOS klient Google ešte nie je), URL ${u.replace(ORIGIN, '')}`)
  return 'bez iOS OAuth klienta → hláška „dočasne nedostupné“ (?google=off)'
})
await blur()
screen('prihlasenie')
// prihlásenie aj v CS a EN (jazyk neprihláseného = cookie sparton_lang), potom späť
for (const lang of ['cs', 'en']) {
  await js((l) => {
    document.cookie = `sparton_lang=${l}; Path=/; Max-Age=600; Secure; SameSite=Lax`
  }, lang).catch(() => {})
  await go('/login', 2000)
  await blur()
  screen(`prihlasenie-${lang}`)
}
await js(() => {
  document.cookie = 'sparton_lang=; Path=/; Max-Age=0; Secure; SameSite=Lax'
}).catch(() => {})
await go('/login', 1500)

// --- detský účet (R238): v appke sa neprihlási
await check('detský účet sa v appke neprihlási (R238)', async () => {
  if (!process.env.CHILD_EMAIL || !process.env.CHILD_PASSWORD) throw new Skip('chýbajú CHILD_EMAIL / CHILD_PASSWORD v secrets')
  await login(process.env.CHILD_EMAIL, process.env.CHILD_PASSWORD)
  for (let i = 0; i < 20; i++) {
    await sleep(1500)
    const body = await js(() => document.body.innerText).catch(() => '')
    if (/Detský účet používaj vo webovej verzii sparton\.eu|Use a child account in the web version|Dětský účet používej/.test(body)) {
      await blur()
      screen('dieta-blokovane')
      if (/\/app(\/|$|\?)/.test(await url())) throw new Error('dieťa je v /app')
      return 'hláška „Detský účet používaj vo webovej verzii sparton.eu.“'
    }
    if (/\/app(\/|$|\?)/.test(await url())) throw new Error('detský účet sa prihlásil')
  }
  throw new Error('bez hlášky')
})

// --- prihlásenie heslom (účet pre recenziu)
await check('prihlásenie účtom pre recenziu (heslo)', async () => {
  if (!process.env.REVIEW_EMAIL || !process.env.REVIEW_PASSWORD) throw new Error('chýbajú REVIEW_EMAIL / REVIEW_PASSWORD')
  await login(process.env.REVIEW_EMAIL, process.env.REVIEW_PASSWORD)
  const u = await waitUrl(/\/app(\/|$|\?)/, 30)
  await settle(2500)
  return u.replace(ORIGIN, '')
})
const m = /\/app\/([^/?#]+)/.exec(await url().catch(() => ''))
const club = m && !['account', 'new-club', 'terms'].includes(m[1]) ? m[1] : null
record('klub pre recenziu', !!club, club ? `/app/${club}` : 'nenájdený')

// --- po prihlásení: ponuka Face ID (push bez podpisu v simulátore nejde)
await check('ponuka Face ID po prihlásení → zapnutie zámku', async () => {
  const yes = await tapNative(['Zapnúť', 'Turn on', 'Zapnout'], 20_000)
  if (!yes) throw new Error('ponuka Face ID sa nezobrazila')
  // systémový súhlas s Face ID (NSFaceIDUsageDescription) a overenie tváre
  await tapNative(['OK', 'Povoliť', 'Allow'], 6000)
  await sleep(1500)
  await driver.execute('mobile: sendBiometricMatch', { type: 'faceId', match: true })
  await sleep(2000)
  return `„${yes}“, Face ID zhoda`
})
await check('token push (FCM)', async () => {
  const has = await js(() => typeof window.__spartonPushToken === 'string' && window.__spartonPushToken.length > 20)
  if (has) return 'token získaný (hodnota sa nevypisuje)'
  throw new Skip('simulátor bez podpisu nemá APNs (aps-environment) – overí sa až na zariadení')
})

async function visit(path, name, expect) {
  await check(`obrazovka ${path}`, async () => {
    await go(path)
    if (expect) await expect()
    await blur()
    screen(name)
    return (await url()).replace(ORIGIN, '')
  })
}
const SCREENS = [
  ['', 'prehlad'],
  ['/calendar', 'kalendar'],
  ['/people', 'clenovia'],
  ['/payments', 'platby'],
  ['/messages', 'spravy'],
  ['/wall', 'nastenka'],
  ['/stats', 'statistiky'],
]
if (club) {
  for (const [p, n] of SCREENS) await visit(`/app/${club}${p}`, n)
  await visit(`/app/${club}/settings/subscription`, 'predplatne-v-appke', async () => {
    await waitSel('[data-testid="native-billing-web"]', 15_000)
    const body = await js(() => document.body.innerText)
    if (/Zaplatiť kartou|Objednať|€\s*\/\s*(mes|rok)/i.test(body)) throw new Error('na stránke predplatného je nákup')
  })
  await visit(`/app/${club}/settings/credits`, 'kredity-v-appke', async () => {
    await waitSel('[data-testid="native-billing-web"]', 15_000)
    const body = await js(() => document.body.innerText)
    if (/Dokúpiť kredity|Kúpiť kredity/i.test(body)) throw new Error('výzva na nákup kreditov')
  })

  // snímky do App Store aj v češtine a angličtine (jazyk účtu cez prepínač v appke, na konci späť SK)
  for (const [lang, idx] of [['cs', 1], ['en', 2]]) {
    await check(`snímky v jazyku ${lang}`, async () => {
      await go(`/app/${club}`)
      await js((i) => {
        const g = [...document.querySelectorAll('[role="group"]')].find((x) => x.querySelectorAll('button').length === 3)
        g.querySelectorAll('button')[i].click()
      }, idx)
      await sleep(3000)
      const lg = await js(() => document.documentElement.lang)
      if (!lg.startsWith(lang)) throw new Error(`jazyk stránky ${lg}`)
      for (const [p, n] of SCREENS) {
        await go(`/app/${club}${p}`)
        await blur()
        screen(`${n}-${lang}`)
      }
      return `${SCREENS.length} snímok`
    })
  }
  await check('jazyk účtu späť na slovenčinu', async () => {
    await go(`/app/${club}`)
    await js(() => {
      const g = [...document.querySelectorAll('[role="group"]')].find((x) => x.querySelectorAll('button').length === 3)
      g.querySelectorAll('button')[0].click()
    })
    await sleep(3000)
    const lg = await js(() => document.documentElement.lang)
    if (!lg.startsWith('sk')) throw new Error(`jazyk ${lg}`)
    return 'sk'
  })
}

// --- cenník a marketing mimo appky (Safari)
await check('cenník sa v appke neotvorí (Safari)', async () => {
  const before = await url()
  await js(() => {
    location.href = '/pricing'
  })
  await sleep(4000)
  const info = await driver.execute('mobile: activeAppInfo')
  await driver.execute('mobile: activateApp', { bundleId: BUNDLE })
  await sleep(2000)
  const now = await url()
  if (/\/pricing|cennik/.test(now)) throw new Error(`appka zobrazila ${now}`)
  if (info?.bundleId !== 'com.apple.mobilesafari') throw new Error(`v popredí ${info?.bundleId}, nie Safari`)
  return `Safari, appka ostala na ${before.replace(ORIGIN, '')}`
})

// --- hlboký odkaz eu.sparton.app://pay/return
await check('hlboký odkaz eu.sparton.app://pay/return', async () => {
  await driver.execute('mobile: deepLink', { url: 'eu.sparton.app://pay/return?to=/app&r=ok', bundleId: BUNDLE })
  await sleep(2000)
  await tapNative(['Otvoriť', 'Open', 'Otevřít'], 3000)
  const u = await waitUrl(/sparton\.eu\/app/, 15)
  return u.replace(ORIGIN, '')
})

// --- zámok Face ID po studenom štarte
await check('zámok Face ID po štarte appky', async () => {
  await native()
  await driver.execute('mobile: terminateApp', { bundleId: BUNDLE })
  await sleep(1500)
  await driver.execute('mobile: launchApp', { bundleId: BUNDLE })
  await sleep(3500)
  if (!(await nativeExists('lock-overlay')) && !(await nativeExists('lock-unlock'))) throw new Error('zámok sa nezobrazil')
  screen('zamok')
  await driver.execute('mobile: sendBiometricMatch', { type: 'faceId', match: true })
  await sleep(2500)
  if (await nativeExists('lock-unlock')) throw new Error('po zhode tváre zámok ostal')
  return 'zamknuté → Face ID → odomknuté'
})

// --- offline (pf blokuje sparton.eu, RST aj pre otvorené spojenia)
await check('obrazovka „si offline“', async () => {
  if (!ips.length) throw new Error('DNS sparton.eu')
  const rules = NOQUIC + ips.map((ip) => `block return out quick ${ip.includes(':') ? 'inet6' : 'inet'} from any to ${ip}\n`).join('')
  try {
    execFileSync('sudo', ['pfctl', '-E'], { stdio: 'ignore' })
  } catch {}
  pf(rules)
  await sleep(1000)
  await js((u) => {
    location.href = u
  }, `${ORIGIN}/app${club ? `/${club}/calendar` : ''}?offline=${Date.now()}`)
  let t = null
  for (let i = 0; i < 20 && !t; i++) {
    await sleep(1500)
    t = await js(() => document.querySelector('[data-testid="offline-title"]')?.textContent || null).catch(() => null)
  }
  if (!t) throw new Error(`bez obrazovky offline, URL ${await url().catch(() => '?')}`)
  screen('offline')
  return t
})
await check('„Skúsiť znova“ po pripojení načíta stránku', async () => {
  pf(NOQUIC)
  await sleep(1500)
  await js(() => document.getElementById('b')?.click())
  const u = await waitUrl(/^https:\/\/sparton\.eu\/app/, 20)
  return u.replace(ORIGIN, '')
})

// --- odregistrovanie zariadenia (hlavička X-Push-Token / DELETE)
await check('DELETE /api/push/devices z prihlásenej stránky', async () => {
  const status = await js(() =>
    fetch('/api/push/devices', { method: 'DELETE', credentials: 'same-origin', headers: { 'content-type': 'application/json' }, body: JSON.stringify({ token: window.__spartonPushToken || 'x' }) }).then((r) => r.status),
  )
  return `→ ${status}`
})

writeFileSync(join(OUT, 'results.json'), JSON.stringify(results, null, 2))
const failed = results.filter((r) => !r.ok && !r.skipped)
const md = [
  '### Smoke test appky spartON (iOS simulátor)',
  '',
  '| | krok | detail |',
  '|---|---|---|',
  ...results.map((r) => `| ${r.skipped ? '⏭️' : r.ok ? '✅' : '❌'} | ${r.name} | ${r.detail.replace(/\|/g, '/')} |`),
].join('\n')
writeFileSync(join(OUT, 'summary.md'), md + '\n')
await driver.deleteSession().catch(() => {})
console.log(`\n${results.filter((r) => r.ok).length}/${results.length} OK, preskočené ${results.filter((r) => r.skipped).length}`)
process.exit(failed.length ? 1 : 0)
