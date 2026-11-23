// Kontrola obsahu verejného repa pred pushom: súbory sledované Gitom (git ls-files + pripravené na commit)
// nesmú obsahovať tajomstvá ani interné údaje. Vypisuje len cestu a typ nálezu, nikdy nájdenú hodnotu.
// Spustenie: node scripts/check-public.mjs  → exit 1 pri náleze.
import { execFileSync } from 'node:child_process'
import { readFileSync, statSync } from 'node:fs'

const files = execFileSync('git', ['ls-files', '--cached', '--others', '--exclude-standard'], { encoding: 'utf8' })
  .split('\n')
  .filter(Boolean)

const FORBIDDEN_NAMES = [/\.jks$/i, /\.keystore$/i, /\.p12$/i, /\.p8$/i, /\.pem$/i, /google-services\.json$/i, /GoogleService-Info\.plist$/i, /(^|\/)secrets\//i, /(^|\/)\.env/i]

const RULES = [
  ['súkromný kľúč', /-----BEGIN [A-Z ]*PRIVATE KEY-----/],
  ['servisný účet Google', /"type"\s*:\s*"service_account"/],
  ['API kľúč Google', /AIza[0-9A-Za-z_-]{30,}/],
  ['token GitHub', /\bgh[pousr]_[0-9A-Za-z]{30,}/],
  ['token Slack/Stripe', /\b(xox[abpr]-[0-9A-Za-z-]{10,}|sk_(live|test)_[0-9A-Za-z]{10,}|rk_live_[0-9A-Za-z]{10,})/],
  ['heslo v texte', /\b(heslo|password|passwd|pwd)\b\s*[:=]\s*["']?[^\s"'$<{]{6,}/i],
  ['IP servera', /167\.233\.159\.78/],
  ['interný server', /\bskoroz\b|ubuntu-skoroz|\/home\/skoroz/i],
  ['účet pre recenziu', /recenzia-(spravca|trener|rodic)@/i],
  ['súkromný e-mail', /muckajur@|janeviemheslo@/i],
  ['interná cesta', /C:\\\\?(dev|zalohy|Users)\\\\?/i],
]

let bad = 0
for (const f of files) {
  if (FORBIDDEN_NAMES.some((r) => r.test(f))) {
    console.log(`ZAKÁZANÝ SÚBOR  ${f}`)
    bad++
    continue
  }
  let st
  try {
    st = statSync(f)
  } catch {
    continue
  }
  if (!st.isFile() || st.size > 2_000_000) continue
  const buf = readFileSync(f)
  if (buf.includes(0)) continue // binárny súbor
  const text = buf.toString('utf8')
  for (const [name, re] of RULES) {
    if (f === 'scripts/check-public.mjs') continue
    if (re.test(text)) {
      console.log(`NÁLEZ  ${f}  (${name})`)
      bad++
    }
  }
}
console.log(bad ? `\n${bad} nálezov – oprav pred pushom.` : `OK – ${files.length} súborov bez tajomstiev a interných údajov.`)
process.exit(bad ? 1 : 0)
