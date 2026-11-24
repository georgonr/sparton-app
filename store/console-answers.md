# spartON (eu.sparton.app) – odpovede pre Play Console, ktoré sa nedajú nastaviť cez API

Podklad pre vyplnenie v Play Console (Policy → App content / Obsah aplikácie). Store listing, grafika, kontakty, AAB v internom teste a Data safety sú nahraté cez Google Play Developer API.
Prihlasovacie údaje sem nepatria – sú výhradne v poli **Credentials** v sekcii App access.

## 1. Privacy policy / Zásady ochrany súkromia
- URL: **https://sparton.eu/sk/privacy**

## 2. App access / Prístup k aplikácii
- Voľba: **All or some functionality in my app is restricted** (Všetky alebo niektoré funkcie sú obmedzené).
- Add instructions → Name: **Club admin (demo club)**.
- Polia Username a Password vyplní majiteľ v časti **Credentials** (účet správcu pre recenziu). Do tohto súboru ani do iných polí sa nepíšu.
- „Any other information required to access your app“ (EN, presne):

> Sign in with the email and password from the Credentials field (do not use "Continue with Google"). You land on the dashboard of the demo club "FK Zelená Lúka" with fictitious data. Try: Calendar (trainings, attendance), People (members and groups), Payments (membership fee records), Messages and Wall. The account is a protected review account: password, email and account deletion are locked and no real payments, emails or SMS are sent. The app is for users aged 18+; child accounts are blocked in the app and use the web version. Account deletion for normal users: menu → My account → Delete account, or https://sparton.eu/zmazanie-uctu.

- „Is any other information required?“ → nie (žiadne 2FA, žiadna poloha, žiadny kód z SMS).

## 3. Ads / Reklamy
- **No, my app does not contain ads** (Nie, aplikácia neobsahuje reklamy). AD_ID je z manifestu odstránené.

## 4. Content rating / Hodnotenie obsahu (dotazník IARC)
- E-mail pre IARC: **info@sparton.eu**
- Category / Kategória: **All Other App Types** (Všetky ostatné typy aplikácií) – nie hra, nie sociálna sieť, nie referenčná/vzdelávacia, nie zábavná.
- Odpovede (formulácie otázok sa môžu mierne líšiť – princíp: obsah nič, interakcia používateľov áno):

| otázka (skrátene) | odpoveď |
|---|---|
| Násilie (realistické, fantasy, krv, ublíženie) | **No** |
| Strach / hororový obsah | **No** |
| Sexualita, nahota, sexuálne narážky | **No** |
| Vulgárny alebo hrubý jazyk | **No** |
| Drogy, alkohol, tabak (zobrazenie, propagácia, predaj) | **No** |
| Hrubý humor | **No** |
| Hazard (skutočný alebo simulovaný), lootboxy | **No** |
| Diskriminácia, nenávistné symboly | **No** |
| **Users can interact or exchange content** (správy, príspevky) | **Yes** – členovia toho istého klubu si posielajú správy a píšu na nástenku klubu; obsah moderuje správca klubu, verejný chat ani komunikácia s cudzími ľuďmi nie je |
| Shares user's current physical location with other users | **No** |
| Allows users to purchase digital goods | **No** (v appke sa nič nekupuje; členské klubu je platba za službu v reálnom svete, predplatné a kredity len na webe) |
| Unrestricted internet access / web browser or search engine | **No** (appka zobrazuje len sparton.eu, cudzie odkazy otvára v systémovom prehliadači) |
| Is the app a news app / contains news | **No** |
| Promotes or sells age-restricted products | **No** |

- Očakávaný výsledok: PEGI 3 / USK 0 / ESRB Everyone + deskriptor „Users Interact“.

## 5. Target audience and content / Cieľová skupina a obsah
- Target age groups: **18 and over** (len táto skupina).
- „Could your app unintentionally appeal to children?“ / Môže lákať deti: **No**.
- Store listing nemá prvky cielené na deti. Účty detí sa v appke neprihlásia (server ich odmietne hláškou „Detský účet používaj vo webovej verzii sparton.eu.“).

## 6. Store settings / Nastavenia obchodu
- App category: **Sports** (Šport). Tags (ak sú ponúknuté): Sports, Organization, Communication.
- Contact: e-mail **info@sparton.eu**, web **https://sparton.eu**, telefón nevypĺňať (kontakty sú už nastavené cez API).

## 7. Ostatné vyhlásenia (podľa pravdy)
| vyhlásenie | odpoveď |
|---|---|
| News app | **No** |
| COVID-19 contact tracing / status app | **No** (ak sa ešte zobrazuje) |
| Government app | **No** |
| Financial features | **My app doesn't provide any financial features** (klub vyberá členské cez Stripe na webe; spartON nie je banka, peňaženka ani platobná služba) |
| Health apps | **My app does not have any health features** |
| Advertising ID | **No** (nepoužíva reklamné ID) |
| Data safety | nahraté cez API (CSV); skontrolovať, že sekcia ukazuje „Complete“ a URL zmazania účtu https://sparton.eu/zmazanie-uctu |

## 8. Čo sa NErobí
- Produkčný track sa nezakladá, nič sa neodosiela na kontrolu („Send for review“ / „Odoslať na kontrolu“ stlačí majiteľ).
