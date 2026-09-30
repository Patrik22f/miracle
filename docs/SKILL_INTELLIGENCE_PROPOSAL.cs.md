# Preflight: přesný výběr skillů a Claude Code

## Doporučení

Oddělit **studium skillů při synchronizaci** od **výběru při psaní promptu**. Skills API je zdroj katalogu a obsahu, nikoli závislost každého doporučení. Prompt se vyhodnocuje nad připravenou místní knihovnou. Neznámý skill bez instrukcí nedostane doporučení jen díky podobnému názvu nebo počtu instalací.

První implementace je v `api/src/skill-knowledge.js`. Je to deterministický obsahový index, nikoli model, který prokazatelně chápe libovolné instrukce. Další doporučená fáze je modelová extrakce ověřovaných profilů při importu, popsaná níže. Toto rozlišení je zásadní: další regexy samy nezajistí obecné porozumění.

## Tři varianty

| Varianta | Rychlost při promptu | Přesnost a omezení | Doporučení |
| --- | --- | --- | --- |
| Ručně ověřené profily a deterministický index | Nejrychlejší, bez sítě | Výborná kontrola známých oblastí; ruční údržba a menší pokrytí | Vhodná pro úzký podnikový katalog |
| Model prostuduje obsah při importu, validátor ověří doklady; lokální index vybírá | Velmi rychlá; dražší je jen změna skillu | Širší pokrytí, ale modelová extrakce potřebuje testy a kontrolu | **Doporučená cílová architektura** |
| Vyhledávání a LLM reranking při každém promptu | Síťová latence, proměnlivé náklady | Může řešit nejasné zadání, ale zpomaluje běžné použití | Pouze volitelný režim pro nejasné případy |

Současný kód pokládá základy první a druhé varianty: plný SKILL.md, verzovaný profil, hash obsahu, doklady s čísly řádků, oddělený import a lokální index. Modelová extrakce, embeddings, kalibrace a podniková správa zatím implementované nejsou.

## 12 hodnoticích kritérií

Součet vah je 100. Výsledné číslo znamená míru shody podle pravidel, ne pravděpodobnost správnosti. Základní podmínky mají přednost před skóre.

| # | Kritérium | Váha | Co skutečně ověřujeme |
| --- | --- | ---: | --- |
| 1 | Účel úkolu | 18 | Potřebuje prompt právě tuto specializaci: výkon, přístupnost, testy, souběžnost…? |
| 2 | Framework a platforma | 15 | SwiftUI versus UIKit, React versus React Native, GRDB versus obecná Apple aplikace. Konkrétní kompatibilní framework má při výběru přednost. |
| 3 | Požadovaná operace | 10 | Vytvořit, upravit, číst, auditovat nebo optimalizovat. Operace se porovnávají s popisem a instrukcemi. |
| 4 | Výstupní artefakt | 7 | PDF, DOCX, spreadsheet a prezentace mají odlišné workflow. Když prompt formát nepožaduje, přiděluje se neutrálních 5 bodů. |
| 5 | Spouštěcí podmínky z popisu | 10 | Konkrétní společné významové termíny v popisu a promptu, bez běžných obecných slov. |
| 6 | Podklady v instrukcích | 12 | Odpovídající výrazy ve skutečném těle SKILL.md, doložené řádky. Opakování stejného výrazu nezvyšuje skóre. |
| 7 | Předpoklady workflow | 5 | Známe požadovaný kontext služby a dostupnost odkazovaných souborů? Například live Excel vyžaduje otevřený workbook, Stripe Connect odpovídající workflow. |
| 8 | Zákazy a omezení | 5 | Respektuje prompt zákaz skillu/frameworku? Obsah může deklarovat nepoužitelnost pro konkrétní oblast. Rozpor znamená vyřazení. |
| 9 | Kompatibilita agenta | 5 | Claude-only rozšíření a konkrétní Codex nástroje. Známý kompatibilní host dostane 5, neznámý 2. Není to důkaz, že jsou připojené všechny požadované nástroje. |
| 10 | Dostupnost instrukcí | 5 | Lokálně instalovaný skill dostane 5; importovaný veřejný obsah 3. Pouhá metadata nestačí. |
| 11 | Stáří snapshotu | 3 | Import do 7 dnů: 3; do 30 dnů: 1; starší nebo neznámý: 0. Čerstvý import neprokazuje správnost ani údržbu upstream projektu. |
| 12 | Specializace | 5 | Jedna až dvě odpovídající specializace dostanou 5; široký profil 2. |

Vyřazujeme chybějící obsah, změněný hash, nekompatibilního agenta, explicitní zákazy, známý nesplněný předpoklad a neúplný API balíček s chybějícím odkazovaným souborem. U běžného doporučení musí existovat i podklad v těle instrukcí. Práh je **70/100**, nejvýše tři komplementární skilly. Explicitní požadavek má prioritu, ale neobchází tyto podmínky. Žádné doporučení je platný výsledek.

Současné rozpoznávání předpokladů a zákazů je omezené: několik kontrolovaných workflow a jednoduchá formulace omezení. Obecné verze frameworků, licence, dostupnost všech CLI/MCP nástrojů a komplexní podmínkové věty ještě nejsou ověřené. Nesmějí dostat označení „splněno“ bez důkazu v budoucím profilu.

## Jak se správný skill najde

1. **Synchronizace:** použít oficiální skills.sh v1 detail pro konkrétní ID. Volitelně načíst curated katalog, filtrovat povolené zdroje, duplicity a omezit import na 30 položek. Synchronizace používá nejvýše čtyři souběžné požadavky.
2. **Příjem dat:** ověřit velikost, identitu, relativní cesty a přítomnost SKILL.md. Uložit obsah i podpůrné soubory do privátního snapshotu. Obsah se nespouští.
3. **Studium:** sestavit profil účelu, rozsahu, operací, vyloučení, agentních omezení a odkazů. Profil uložit s verzí extraktoru a SHA-256 původního SKILL.md. Starší importy se dopočítají při prvním načtení.
4. **Index:** připravit mapy framework → kandidáti, účel → kandidáti, přesný název → kandidát a výraz → řádky instrukcí. Není potřeba při každém promptu znovu číst všechny soubory.
5. **Prompt a aktivní chat:** nejprve vyřešit odkaz na rozpracovaný úkol z dodaného kontextu, jeho stack a omezení; teprve pak určit potřebné schopnosti, effort a skilly. Krátké „Pokračuj“ není samostatně jednoduchý úkol. [Implementovaný kontext a omezení](CHAT_CONTEXT.md). Rozpoznat pozitivní požadavky, zákazy a explicitní invokace. Běžné české formulace mají kontrolovaný slovník; nejde o obecný překladač.
6. **Podmínky:** vyřadit neslučitelné kandidáty ještě před výpočtem skóre.
7. **Pořadí:** explicitní požadavek, přesnost platformy, potom vážená shoda a dostupnost lokální instalace. Popularita nemění relevanci.
8. **Sestava:** doporučit jen skilly, které přidají další potřebnou schopnost. Tři téměř totožné auditní skilly nezaberou tři místa.
9. **Vysvětlení:** vrátit důvod, 12 bodových složek, hash a řádky podkladů. Nedoporučovat nerozpoznanou oblast jen proto, aby výsledek nebyl prázdný.

Příklad: „Zrychli pomalé SwiftUI scrollování“ vybírá specialistu na SwiftUI výkon. GRDB performance audit se vyřadí, protože chybí GRDB. Obecný Apple performance skill zůstane až za použitelným specialistou. „Implement Stripe checkout“ samo neopravňuje doporučení Stripe Connect. „React Native FlatList“ nepatří browserovým React optimalizacím.

## Co znamená skutečně nastudovaný profil v další fázi

Každý profil musí obsahovat `skillId`, hash **celého balíčku**, verzi extraktoru, podporované úkoly a operace, frameworky a rozsahy verzí, výstupy, povinné nástroje, předpoklady, vyloučení, agentní rozšíření, příklady použití i protipříklady a závislosti na dalších skillech. Každé tvrzení musí odkazovat na soubor, řádek a přesný úsek obsahu.

Model při synchronizaci pročte SKILL.md a relevantní podpůrné dokumenty. Vrátí pouze strukturovaná data. Validátor ověří, že citované úseky skutečně existují a patří danému hashi; neověřená tvrzení označí jako neznámá. Profil bez opory se nezařadí do automatického výběru. Citace sama nezaručuje správný výklad, proto profily rizikových workflow potřebují i lidské posouzení.

Příklady a protipříklady poslouží pro lokální lexikální a vektorové hledání kandidátů. Výsledný výběr stále projde podmínkami a vahami výše. Dražší model se použije jen pro nejasnost mezi několika kandidáty a s omezeným časem. Při nízké jistotě aplikace zobrazí, co chybí, například „Je to samostatný XLSX, nebo otevřený Excel workbook?“

Začít přibližně 100–300 ověřenými skilly pro skutečné pracovní oblasti. Plošně stáhnout statisíce položek a považovat je za nastudované by přesnost nezaručilo. Nové oblasti se rozšíří přes katalogový proces; soukromé prompty se nepoužijí jako vyhledávací dotazy.

## Claude Code

Implementováno: import `~/.claude/skills`, volitelné projektové kořeny pomocí `--root`, přímé `/skill-name`, respektování `disable-model-invocation` a `user-invocable`, generátor konfigurace a lokální `UserPromptSubmit` hook. Hook doplní doporučení při odeslání promptu, před zpracováním modelem; nesnímá rozepsaný terminálový řádek. Nepotřebuje běžící HTTP server ani API token.

`npm run --silent claude:config` vypíše konfiguraci s absolutní cestou Node a hooku. Její `UserPromptSubmit` položku lze sloučit do projektového `.claude/settings.local.json`. Existující nastavení se automaticky nepřepisuje. Hook nepřiděluje oprávnění, neinstaluje skilly a neposílá jejich těla do kontextu; předá identitu, cestu, skóre a řádky podkladů. Při chybě vynechá doporučení a neblokuje prompt.

Samostatně zbývá ověřit chování ve skutečné Claude Code relaci a podle potřeby implementovat podporu rozepsaných promptů v konkrétních terminálech. Testy protokolu nejsou totožné s ověřením živé aplikace.

## Měření a podmínky pro enterprise nasazení

Tyto cíle nejsou tvrzení o již dosažené kvalitě:

| Metrika | Navrhovaný cíl |
| --- | --- |
| Precision@1 | ≥95 % na odděleném lidsky označeném testovacím souboru |
| Recall@3 | ≥90 % u úloh s existujícím vhodným skillem |
| Chybná doporučení u „žádný skill“ | ≤2 % |
| Neslučitelný framework nebo host | 0 ve vyhrazeném kritickém testovacím souboru |
| Ignorování explicitního zákazu | 0 v kritickém testovacím souboru |
| P95 teplého lokálního výběru | <20 ms pro cílový katalog |
| P95 celé odpovědi místního API | <50 ms na definovaném zařízení |
| P95 Claude hooku včetně startu | <250 ms pro cílový katalog |
| Přenos surového promptu mimo zařízení | 0 ve standardním režimu |
| Pokrytí tvrzení v profilu podklady | 100 % automaticky použitých tvrzení |
| Reprodukovatelnost | Stejný prompt + snapshot + pravidla + časové pásmo freshness → stejný výběr |
| Výpadek synchronizace | Zachování posledního platného snapshotu; analýza dál funguje |
| Regrese při nové verzi skillu | Žádná automatická propagace bez porovnání s předchozí verzí |
| Šíře testovacího souboru | Min. 500 nezávislých CZ/EN úloh; podobné skilly, nejasnosti, negace a kombinace |

Dále: přesné verze a revokace balíčků, per-team povolené zdroje, oddělené pracovní prostory, správa krátkodobých tokenů na synchronizačním serveru, audit změn bez promptů, kalibrované odmítnutí, aktualizace profilů mimo cestu promptu. Lokální neautentizované API se nesmí prezentovat jako síťová víceuživatelská enterprise služba.

## Ověřené zdroje

- [Oficiální skills.sh API](https://skills.sh/docs/api): autentizace Vercel OIDC, detail s kompletním souborovým stromem, curated katalog. Přihlášené v1 volání zde nebylo živě ověřeno; adaptér je testován proti dokumentovaným odpovědím.
- [Claude Code skills](https://code.claude.com/docs/en/skills): lokální umístění, slash invokace a řízení automatického použití.
- [Claude Code hooks](https://code.claude.com/docs/en/hooks#userpromptsubmit): předání promptu při odeslání a `hookSpecificOutput.additionalContext`.
