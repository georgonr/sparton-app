// Ikony appky spartON z loga (public/icons/icon.svg v repozitári spartON):
// - legacy PNG ikony pre Android 7.x (adaptívne ikony 8+ sú vektorové v res/drawable),
// - ikona do Google Play 512×512 (celý štvorec, zaoblenie robí Google).
// Spustenie: node scripts/gen-icons.mjs <cesta k sharp>  (sharp sa neinštaluje do tohto repa)
import { createRequire } from 'node:module'
import { mkdirSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const sharpPath = process.argv[2] || process.env.SHARP_PATH
if (!sharpPath) throw new Error('chýba cesta k balíku sharp')
const sharp = createRequire(import.meta.url)(sharpPath)

const ball = `
  <circle cx="256" cy="256" r="150" fill="#fff"/>
  <path d="M256 158l55 40-21 65h-68l-21-65z" fill="#13201a"/>
  <path d="M256 106v52M369 186l-58 12M347 345l-57-82M165 345l57-82M143 186l58 12" stroke="#13201a" stroke-width="18" stroke-linecap="round"/>
  <path d="M405 120a206 206 0 0 1 40 104" stroke="#ff8137" stroke-width="30" stroke-linecap="round" fill="none"/>`

// legacy štvorcová ikona so zaoblením (ako PWA), okrúhla ikona, obchod bez zaoblenia
const square = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect x="16" y="16" width="480" height="480" rx="104" fill="#168342"/><g transform="translate(38 38) scale(.85)">${ball}</g></svg>`
const round = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><circle cx="256" cy="256" r="240" fill="#168342"/><g transform="translate(51 51) scale(.8)">${ball}</g></svg>`
const store = `<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 512 512"><rect width="512" height="512" fill="#168342"/><g transform="translate(51 51) scale(.8)">${ball}</g></svg>`

const sizes = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 }
for (const [d, px] of Object.entries(sizes)) {
  const dir = join(root, 'android/app/src/main/res', `mipmap-${d}`)
  mkdirSync(dir, { recursive: true })
  await sharp(Buffer.from(square)).resize(px, px).png().toFile(join(dir, 'ic_launcher.png'))
  await sharp(Buffer.from(round)).resize(px, px).png().toFile(join(dir, 'ic_launcher_round.png'))
}
mkdirSync(join(root, 'store'), { recursive: true })
await sharp(Buffer.from(store)).resize(512, 512).png().toFile(join(root, 'store/icon-512.png'))
// iOS: ikona aplikácie 1024×1024 bez priehľadnosti
const iosDir = join(root, 'ios/App/App/Assets.xcassets/AppIcon.appiconset')
await sharp(Buffer.from(store)).resize(1024, 1024).flatten({ background: '#168342' }).png().toFile(join(iosDir, 'AppIcon-512@2x.png'))
console.log('ikony hotové')
