# Miracle / Zázrak

**Give your next prompt the right setup.**

**Dej svému příštímu promptu správnou výbavu.**

A native macOS companion that recommends a model, reasoning effort and relevant skills while you write in Cursor or Codex.

Nativní aplikace pro macOS, která při psaní v Cursoru nebo Codexu doporučí model, míru uvažování a relevantní skilly.

[English](#english) · [Česky](#cesky) · [Development / Vývoj](#development) · [Documentation / Dokumentace](#documentation)

<a id="english"></a>
## English

### The decisions before you press Send

You know what you want to build. Then come the smaller decisions: which model to use, how much reasoning the task deserves, and whether a useful skill is already sitting somewhere in your tools. Finding those answers can interrupt the work before it even starts.

**Miracle brings those decisions to the prompt you are already writing.** It lives in the macOS menu bar, reads supported prompt inputs with your permission, and recommends a setup for the task. You review the advice, install the skills you choose, and send the prompt from your AI app.

A **skill** is a reusable set of instructions, sometimes with scripts and reference material, that helps an AI assistant approach a particular kind of work. Miracle finds relevant instructions in your imported library and explains why they match.

### What it helps you solve

| The problem | How Miracle helps | Why it matters |
| --- | --- | --- |
| Useful skills are scattered across local folders, plugins and public repositories. | Imports their content into a searchable library and matches it to your task. | Discover relevant guidance without knowing its name beforehand. |
| Model and reasoning settings become a habit, even when the task changes. | Estimates task complexity and maps its advice to the host app's local model catalog and supported effort levels. | Reconsider the setup for a small edit, an investigation or a complex implementation. |
| Looking up tools interrupts your train of thought. | Shows advice in the menu bar or beside a recognized prompt input. | Keep writing in the app where the work happens. |
| A follow-up like “Fix it” loses meaning in isolation. | Uses supplied active-chat context and shows when it is missing or partial. | Get recommendations that can reflect the ongoing task. |
| Choosing the next useful task takes another round of prompting. | Optionally uses Groq to propose three next-task prompts grounded in sampled project files. | Get concrete starting points to review, edit and copy. |

### From prompt to recommendation

Suppose you write:

> “Optimize this Next.js page. It is slow when rendering 500 products.”

Miracle checks the task's platform and purpose, looks for relevant performance instructions in the imported library, and recommends a model and supported reasoning effort. Eligible skills come with their source, fit score and instruction evidence. If nothing qualifies, the skill list stays empty.

1. **Write in Cursor or Codex.** Recognized prompt inputs trigger analysis after a short typing pause.
2. **Review the recommendation.** See the suggested model, effort and matching skills.
3. **Choose what to use.** Install one skill or selected skills for this Mac or an explicitly chosen project.
4. **Apply the advice in your AI app.** Model selection and sending the prompt remain in your hands.

Choose how visible Miracle should be:

- **Stealth:** a dot in the menu bar signals a new recommendation. Open it when you want the details.
- **Helpful:** a panel appears above a recognized prompt input while keyboard focus stays in your AI app.

### Why the matching is useful

The default `knowledge` mode works from imported `SKILL.md` content. It evaluates **12 criteria**, including task purpose, platform, requested operation, instruction evidence, prerequisites and host compatibility. A skill needs at least **70/100** to qualify; additional results must contribute relevant coverage.

**Best match** means the first eligible result under the ranking rules in your current imported library. Scores describe task fit. Matching uses deterministic rules, and model advice uses capability heuristics; neither is a measured guarantee of better output. Skills retain their source and `not-audited` status. See [how matching works](docs/SKILL_MATCHING.md).

Importing indexes a skill for discovery. Installing copies its complete package into the selected host's skill directory. Installation preserves existing packages and runs no skill commands; the host app still needs to load the installed skill.

### Start locally

You need **macOS 14+**, **Xcode 16+ / Swift 6**, and **Node.js 22+**. The normal app build uses an Apple Development signing identity. Core recommendations need no API key.

From the repository root:

```sh
# First setup: skip this copy if you already have a .env file.
cp .env.example .env

# Index local skills and the configured public starter sources.
npm run skills:import
npm start
```

For an import using only local skills, replace the import command with `npm run skills:import -- --local-only`.

In a second terminal, from the same repository:

```sh
npm run macos:build
open build/Miracle.app
```

The build installs to `~/Applications/Miracle.app`. Quit an existing Miracle or Preflight instance before rebuilding. If no unique signing identity is available, set `MIRACLE_CODESIGN_IDENTITY` to your certificate. A disposable build can use `MIRACLE_CODESIGN_IDENTITY=- npm run macos:build`, with Accessibility approval needed again after code changes. See [build details](macos/README.md#capture-and-build).

Allow **Miracle** in **System Settings → Privacy & Security → Accessibility**. Some macOS versions call this permission **Device Control and Data Access**. Focus a prompt in Cursor or Codex and start typing; live capture starts enabled. The captured app determines the model catalog and skill installation destination.

Open **Skill library** to browse, filter or refresh imports. Use **Settings** to configure models, installation scope and optional prompt suggestions.

### Optional next-task prompts

Add `GROQ_API_KEY` to the backend's `.env`, restart the server, and choose a project under **Your next task** or **Settings → Prompts**. Miracle samples saved project files and uses the current prompt and available chat context to suggest three tasks. Unchanged requests reuse cached results.

**Use draft** opens a suggestion for editing in Miracle and starts skill/model advice. **Copy prompt** copies it for review in your AI app. These are proposals based on a bounded sample of the project; you decide which to pursue.

This feature sends selected code and context to **Groq**. [Setup, sampling limits and data flow](docs/PROMPT_SUGGESTIONS.md) explain exactly what is included.

### Where your data goes

| Activity | Data flow |
| --- | --- |
| Skill matching in default `knowledge` mode | Prompt analysis stays on your Mac. No search or LLM request runs on this path. |
| Skill import and installation | Local packages are read or copied; public packages are fetched from configured sources. Imported snapshots persist in ignored `.preflight/`. |
| Optional Groq suggestions | Selected source excerpts, relative paths, project name, prompt and supplied chat context go to Groq. Common secrets are excluded or redacted, with no guarantee that every sensitive value is removed. |
| Local app state | Captured prompts and suggestion results stay in memory. Preferences and selected folders persist. Miracle adds no prompt/code logging or telemetry. |

The development API binds to `127.0.0.1` and rejects browser origins. Legacy `live` and `hybrid` modes can send controlled topic labels to public search; use the default `knowledge` mode for local matching.

### Use it your way

**Native app:** advice while composing in supported Cursor and Codex inputs. Capture depends on the host's Accessibility support. Automatic chat-history capture is best-effort and still needs live-host validation; a reviewable context editor is available when history is missing. See [capture support](docs/LIVE_CAPTURE.md) and [chat context](docs/CHAT_CONTEXT.md).

**Local CLI:** query the imported library without a server or network request:

```sh
npm run --silent skills:find -- "Fix Swift Sendable actor isolation." --app Codex --provenance installed
```

Use `--scope`, `--purpose`, `--source`, `--q`, `--limit` or `--json` to narrow or automate the lookup. [AGENTS.md](AGENTS.md) defines this repository's recommendation workflow.

**Claude Code:** a `UserPromptSubmit` hook adds local skill recommendations when a prompt is submitted. Generate its configuration with `npm run --silent claude:config`, then follow the [integration guide](docs/CLAUDE_CODE.md). It reads the imported library directly and can use the exact session's transcript. Live Claude Code acceptance remains to be verified.

**Demo:** enable **Settings → General → Demo mode** or choose **Try demo** from the menu bar. A bundled Shopfront website opens; type the [prepared prompts](macos/Sources/Preflight/Resources/Demo/README.md) into a supported coding app. Skill recommendations use curated local entries, and install actions change only the demo session's state. **Suggested prompts** uses Groq with the bundled Shopfront source and presentation brief, so it requires the local backend and `GROQ_API_KEY`. The demo project is selected automatically; copy a suggestion into your coding app with **Copy prompt**. Turn Demo mode off to return to real analysis. See [presentation instructions](macos/README.md#presentation-from-a-real-coding-app).

Miracle is an actively developed prototype distributed here as source. Host compatibility, matching accuracy and release distribution remain areas of ongoing work; the current app build uses development signing.

<a id="cesky"></a>
## Česky

### Rozhodnutí před odesláním promptu

Víš, co chceš vytvořit. Pak přijdou další otázky: který model použít, kolik uvažování úkol potřebuje a jestli už někde ve svých nástrojích nemáš užitečný skill. Hledání odpovědí tě může vytrhnout z práce ještě dřív, než začneš.

**Miracle přináší doporučení přímo k promptu, který právě píšeš.** Žije v řádku nabídek macOS, s tvým svolením čte podporovaná vstupní pole a doporučuje nastavení pro konkrétní úkol. Ty si doporučení projdeš, nainstaluješ vybrané skilly a prompt odešleš ze své AI aplikace.

**Skill** je opakovaně použitelná sada instrukcí, někdy doplněná o skripty a referenční materiály, která pomáhá AI asistentovi s určitým typem práce. Miracle vyhledá relevantní instrukce v importované knihovně a vysvětlí, proč se k úkolu hodí.

### Jaké problémy řeší

| Problém | Jak pomáhá Miracle | Proč na tom záleží |
| --- | --- | --- |
| Užitečné skilly jsou roztroušené po lokálních složkách, pluginech a veřejných repozitářích. | Importuje jejich obsah do prohledávatelné knihovny a páruje ho s úkolem. | Relevantní postup najdeš, i když předem neznáš jeho název. |
| Model a míru uvažování volíš ze zvyku, přestože se úkoly mění. | Odhadne náročnost úkolu a doporučení přiřadí k lokálnímu katalogu modelů a podporovaným úrovním uvažování. | Získáš podklad pro vhodnější nastavení u drobné úpravy, hledání chyby i složité implementace. |
| Hledání nástrojů přerušuje soustředění. | Zobrazí doporučení v řádku nabídek nebo vedle rozpoznaného pole pro prompt. | Můžeš dál psát v aplikaci, ve které pracuješ. |
| Krátké „Oprav to“ bez předchozí konverzace ztrácí význam. | Využije dodaný kontext aktivního chatu a ukáže, když je neúplný nebo chybí. | Doporučení může navázat na rozpracovaný úkol. |
| Vymýšlení dalšího užitečného kroku vyžaduje další promptování. | Volitelně přes Groq navrhne tři prompty pro další úkoly podle vybraných souborů projektu. | Získáš konkrétní návrhy, které můžeš posoudit, upravit a zkopírovat. |

### Od promptu k doporučení

Představ si, že napíšeš:

> „Optimalizuj tuto stránku v Next.js. Vykreslování 500 produktů je pomalé.“

Miracle vyhodnotí platformu a účel úkolu, v importované knihovně vyhledá relevantní instrukce pro výkon a doporučí model i podporovanou míru uvažování. U vhodných skillů ukáže zdroj, skóre shody a odkazy na konkrétní instrukce. Pokud žádný nevyhovuje, seznam zůstane prázdný.

1. **Piš v Cursoru nebo Codexu.** U rozpoznaných vstupních polí se analýza spustí po krátké pauze v psaní.
2. **Prohlédni si doporučení.** Uvidíš navržený model, míru uvažování a odpovídající skilly.
3. **Vyber, co chceš použít.** Nainstaluj jeden skill nebo vybrané skilly pro tento Mac či výslovně zvolený projekt.
4. **Nastavení uprav ve své AI aplikaci.** Výběr modelu i odeslání promptu zůstávají v tvých rukou.

Vyber si, jak výrazně se má Miracle ozývat:

- **Stealth:** tečka v řádku nabídek upozorní na nové doporučení. Podrobnosti otevřeš, až budeš chtít.
- **Helpful:** panel se zobrazí nad rozpoznaným polem pro prompt. Klávesnice dál ovládá tvoji AI aplikaci.

### Proč má párování smysl

Výchozí režim `knowledge` pracuje s importovaným obsahem `SKILL.md`. Vyhodnocuje **12 kritérií**, například účel úkolu, platformu, požadovanou činnost, oporu v instrukcích, předpoklady použití a kompatibilitu s aplikací. Skill musí dosáhnout alespoň **70 ze 100 bodů**. Další doporučení musí přidávat relevantní pokrytí úkolu.

**Best match** označuje první vyhovující výsledek podle pravidel řazení v aktuálně importované knihovně. Skóre vyjadřuje shodu s úkolem. Párování používá deterministická pravidla a doporučení modelů heuristický odhad schopností; nejde o změřenou záruku lepšího výstupu. U skillů zůstává uvedený zdroj a stav `not-audited`. Podrobnosti najdeš v [popisu párování](docs/SKILL_MATCHING.md).

Import zařadí skill do knihovny pro vyhledávání. Instalace zkopíruje celý balíček do složky skillů zvolené aplikace. Zachová existující balíčky a nespouští příkazy skillu; samotná AI aplikace musí nainstalovaný skill ještě načíst.

### Spuštění na Macu

Potřebuješ **macOS 14+**, **Xcode 16+ / Swift 6** a **Node.js 22+**. Běžné sestavení aplikace používá podpisovou identitu Apple Development. Základní doporučení fungují bez API klíče.

V kořenové složce repozitáře spusť:

```sh
# První nastavení: pokud už soubor .env máš, kopírování přeskoč.
cp .env.example .env

# Import lokálních skillů a přednastavených veřejných zdrojů.
npm run skills:import
npm start
```

Pokud chceš importovat pouze lokální skilly, nahraď příkaz pro import za `npm run skills:import -- --local-only`.

Ve druhém terminálu, ve stejné složce:

```sh
npm run macos:build
open build/Miracle.app
```

Sestavení nainstaluje aplikaci do `~/Applications/Miracle.app`. Před dalším sestavením ukonči běžící Miracle nebo původní Preflight. Pokud není dostupná jednoznačná podpisová identita, nastav `MIRACLE_CODESIGN_IDENTITY` na svůj certifikát. Pro dočasné sestavení můžeš použít `MIRACLE_CODESIGN_IDENTITY=- npm run macos:build`; po změnách kódu bude potřeba znovu schválit oprávnění ke zpřístupnění. Viz [podrobnosti sestavení](macos/README.md#capture-and-build).

Povol **Miracle** v **Nastavení systému → Soukromí a zabezpečení → Zpřístupnění**. V některých verzích macOS se oprávnění označuje **Device Control and Data Access**. Klikni do promptu v Cursoru nebo Codexu a začni psát; průběžné čtení je zapnuté od začátku. Podle zachycené aplikace se vybere katalog modelů i cílové umístění skillů.

V **Skill library** můžeš skilly procházet, filtrovat a obnovovat importy. V **Settings** nastavíš modely, umístění instalace a volitelné návrhy dalších promptů.

### Volitelné návrhy dalších úkolů

Do backendového `.env` přidej `GROQ_API_KEY`, restartuj server a vyber projekt v **Your next task** nebo **Settings → Prompts**. Miracle načte vzorek uložených souborů a společně s aktuálním promptem a dostupným kontextem chatu navrhne tři úkoly. Pro nezměněné požadavky znovu použije výsledky z mezipaměti.

**Use draft** otevře návrh k úpravě v Miracle a spustí doporučení skillů a modelu. **Copy prompt** ho zkopíruje pro kontrolu ve tvé AI aplikaci. Návrhy vycházejí z omezeného vzorku projektu; ty rozhoduješ, kterému se věnovat.

Tato funkce odesílá vybraný kód a kontext do **Groqu**. Přesný rozsah popisuje [nastavení, limity a tok dat](docs/PROMPT_SUGGESTIONS.md).

### Kam putují tvoje data

| Činnost | Tok dat |
| --- | --- |
| Párování skillů ve výchozím režimu `knowledge` | Analýza promptu probíhá na tvém Macu, bez síťového vyhledávání a bez volání jazykového modelu. |
| Import a instalace skillů | Lokální balíčky se čtou nebo kopírují; veřejné se stahují z nastavených zdrojů. Importované kopie se ukládají do ignorované složky `.preflight/`. |
| Volitelné návrhy přes Groq | Do Groqu odcházejí vybrané úryvky kódu, relativní cesty, název projektu, prompt a dodaný kontext chatu. Běžné citlivé soubory a přihlašovací údaje se vynechávají nebo maskují; odstranění všech citlivých hodnot není zaručeno. |
| Lokální stav aplikace | Zachycené prompty a výsledky návrhů zůstávají v paměti. Ukládají se preference a vybrané složky. Miracle nezavádí logování promptů či kódu ani telemetrii. |

Vývojové API naslouchá na `127.0.0.1` a odmítá požadavky s původem v prohlížeči. Starší režimy `live` a `hybrid` mohou posílat řízené tematické dotazy do veřejného vyhledávání; pro lokální párování používej výchozí `knowledge`.

### Používej ho po svém

**Nativní aplikace:** doporučení při psaní do podporovaných polí Cursoru a Codexu. Čtení závisí na tom, co aplikace zpřístupní přes rozhraní Accessibility. Automatické získávání historie chatu je omezené a stále vyžaduje ověření v běžících aplikacích; chybějící kontext lze zkontrolovat a doplnit v editoru. Viz [podpora čtení promptů](docs/LIVE_CAPTURE.md) a [kontext chatu](docs/CHAT_CONTEXT.md).

**Lokální CLI:** prohledání importované knihovny bez spuštěného serveru a bez síťového požadavku:

```sh
npm run --silent skills:find -- "Fix Swift Sendable actor isolation." --app Codex --provenance installed
```

Parametry `--scope`, `--purpose`, `--source`, `--q`, `--limit` a `--json` slouží k upřesnění nebo automatizaci hledání. [AGENTS.md](AGENTS.md) určuje postup doporučování skillů v tomto repozitáři.

**Claude Code:** hook `UserPromptSubmit` doplní při odeslání promptu lokální doporučení skillů. Konfiguraci vygeneruješ příkazem `npm run --silent claude:config`; dál postupuj podle [integračního návodu](docs/CLAUDE_CODE.md). Hook čte přímo importovanou knihovnu a může využít přepis konkrétní relace. Ověření v živé relaci Claude Code ještě zbývá.

**Demo:** zapni **Settings → General → Demo mode** nebo zvol **Try demo** v řádku nabídek. Otevře se přibalený web Shopfront. Napiš [připravené prompty](macos/Sources/Preflight/Resources/Demo/README.md) do podporované aplikace. Demo používá předem připravené lokální skilly a instalace mění pouze stav ukázkové relace. **Suggested prompts** generuje Groq podle přibaleného zdrojového kódu Shopfrontu a prezentačního zadání, proto potřebuje spuštěný backend a `GROQ_API_KEY`. Demo projekt se vybere automaticky; návrh zkopíruješ do své AI aplikace přes **Copy prompt**. Vypnutím Demo mode se vrátíš ke skutečné analýze. Viz [návod k prezentaci](macos/README.md#presentation-from-a-real-coding-app).

Miracle je aktivně vyvíjený prototyp, který je zde dostupný jako zdrojový kód. Kompatibilita aplikací, přesnost párování a distribuce vydání se dál rozvíjejí; současné sestavení používá vývojový podpis.

<a id="development"></a>
## Development / Vývoj

The native SwiftUI app talks to a local Node.js API. Shared JSON schemas define the integration boundary. Internal module and data names retain `Preflight` for compatibility.

Nativní aplikace ve SwiftUI komunikuje s lokálním API v Node.js. Rozhraní definují sdílená JSON schémata. Interní názvy modulů a dat zachovávají `Preflight` kvůli kompatibilitě.

| Path / Cesta | Contents / Obsah |
| --- | --- |
| `macos/` | Native app, capture, recommendations, installation / Nativní aplikace, čtení promptů, doporučení, instalace |
| `api/src/` | Local API, matching, project context, suggestions / Lokální API, párování, kontext projektu, návrhy |
| `api/test/`, `api/eval/` | Tests and evaluation scenarios / Testy a vyhodnocovací scénáře |
| `contracts/` | Shared schemas and fixtures / Sdílená schémata a testovací data |
| `scripts/` | Build, import, CLI, hooks and smoke checks / Sestavení, import, CLI, hooky a provozní kontroly |
| `docs/` | Detailed guides and implementation notes / Podrobné návody a poznámky k implementaci |

```sh
npm test                  # Backend, HTTP and contracts / Backend, HTTP a kontrakty
npm run macos:test        # Swift client tests / Testy Swift klienta
npm run eval:knowledge    # Matching regressions and latency / Regrese párování a latence
npm run smoke             # Requires a running API / Vyžaduje spuštěné API
```

API example / Příklad API:

```sh
curl -s http://127.0.0.1:8787/analyze \
  -H 'Content-Type: application/json' \
  --data @contracts/fixtures/analyze-request.json
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [the API guide](docs/API.md) for endpoints and contracts.

Postup vývoje popisuje [CONTRIBUTING.md](CONTRIBUTING.md); endpointy a kontrakty najdeš v [návodu k API](docs/API.md).

<a id="documentation"></a>
## Documentation / Dokumentace

Most technical guides are in English; the architecture proposal is in Czech. / Většina technických návodů je anglicky; návrh architektury je česky.

| Guide / Návod | What you will find / Co v něm najdeš |
| --- | --- |
| [macOS app](macos/README.md) | Interface, models, installation and signing / Rozhraní, modely, instalace a podepisování |
| [Skill matching](docs/SKILL_MATCHING.md) | Imports, 12 criteria, filters and public discovery / Importy, 12 kritérií, filtry a veřejné zdroje |
| [Prompt suggestions](docs/PROMPT_SUGGESTIONS.md) | Groq setup, sampling, caching and data flow / Nastavení Groqu, výběr souborů, mezipaměť a tok dat |
| [Live capture](docs/LIVE_CAPTURE.md) | Accessibility support and verification / Podpora Accessibility a ověření funkčnosti |
| [Chat context](docs/CHAT_CONTEXT.md) | Follow-ups, context boundaries and limitations / Navazující zprávy, rozsah kontextu a omezení |
| [Claude Code](docs/CLAUDE_CODE.md) | Submit hook and session context / Hook při odeslání a kontext relace |
| [Architecture proposal / Návrh architektury](docs/SKILL_INTELLIGENCE_PROPOSAL.cs.md) | Design direction and evaluation targets / Směřování návrhu a cíle vyhodnocování |
