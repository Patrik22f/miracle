# Shopfront

A small static storefront for presenting Miracle from a real coding app. Open this folder in Cursor. Enable Demo mode in Miracle Settings to view the website, then type the prompts below into Cursor's chat input without sending them. Miracle uses its normal Accessibility capture and presentation modes. The site itself has no database or AI chat.

Miracle's **Suggested prompts** section uses Groq to generate three next tasks from this source and the project's database, design/copy and iOS goals. Start the local backend with `GROQ_API_KEY` configured. The demo project is selected automatically. Use **Copy prompt** and paste a generated suggestion into Cursor; the exact presentation prompts below remain available for the two skill scenarios.

## 1. Database

Chceme do tohoto webu integrovat databázi pro produkty, zákazníky a objednávky. Navrhni vhodné řešení a připrav propojení.

Expected skill: `supabase-postgres-best-practices`.

## 2. Design, copy and iOS

Předělej design tohoto webu ve stylu Apple.com. Přepiš nadpisy a texty podle marketingových copywriting zásad a připrav nativní iOS aplikaci ve SwiftUI.

Expected skills: `frontend-design`, `copywriting`, `swiftui-expert-skill`.

The website only increments a local bag counter. Skill matching and installation state are offline and local to Miracle's demo session. Suggested prompts use the real Groq service. Turn off Demo mode to return to the normal backend.
