# How LEVER knows what you spend

LEVER has no bank login and no server watching your accounts. Spending reaches it through channels that all run on the iPhone, each one opt-in. This is the honest map of what works today, what needs Apple's approval, and what iOS simply doesn't allow.

## Channels

| Channel | Status | What happens |
|---|---|---|
| **Camera / Photos / Share Sheet** | Live | Receipts, screenshots, PDFs, emails, web pages, text → Vision OCR + on-device parser → reviewed purchase → opportunities. |
| **Screenshot watcher** | Live (opt-in, Photos permission) | On each app open LEVER lists screenshots taken since the last check. Tap one to read it. Nothing is read automatically. |
| **Bank / card statement import** | Live | CSV or PDF (native text or OCR'd). `StatementImporter` extracts dated transactions; `RecurringChargeDetector` finds merchants charging on a weekly/monthly/quarterly/yearly rhythm (±30% amount tolerance so price rises are caught). Only the subscriptions you choose are stored — not every transaction. Price increases become negotiation opportunities immediately. |
| **Pasted statement text** | Live | Same pipeline. Paste anything with dates and amounts; LEVER detects it is a statement and switches to the recurring-charge flow. |
| **Apple Wallet transactions** | Code complete, needs entitlement | `FinanceKit` (iOS 17.4+) exposes Apple Card / Apple Cash / participating-bank transactions with user consent. Apple grants the `com.apple.developer.financekit` entitlement per app on request; until then LEVER shows "not enabled for this build" instead of failing silently. |
| **Price tracking** | Live | Paste a product link on a purchase. LEVER reads standard page metadata (Open Graph `product:price:amount`, schema.org `itemprop=price`, JSON-LD `price`) — one page, one request, honest User-Agent. A daily `BGAppRefreshTask` re-checks tracked pages and records a price observation only when the price changed. A drop ≥3% becomes a price-drop opportunity. |
| **Repeat-charge detection in the vault** | Live | Every background refresh re-runs the recurring detector across purchases already in the vault, so three scanned Airtel bills become a watched subscription without a statement. |
| **Calendar** | Live (write-only permission) | Any deadline can be added to the user's calendar with a day-before alarm. LEVER never reads calendars. |
| **Gmail import** | Live, needs your OAuth client ID | Google sign-in (PKCE, iOS client, read-only Gmail scope). A purchase-scoped search over the last 90 days (receipts, orders, renewals, bookings; promotions excluded) → each body HTML-stripped and parsed on-device → review list → import what's real. Tokens live in the Keychain; disconnect any time. Set the client ID once in Settings → Sources → Email. |
| **Family vault** | Live | Any purchase exports as a `.leverpurchase` file (receipts, warranties, subscription, return window included) and travels by AirDrop, Messages or Files. Opening it in another LEVER imports it into their vault; same id updates rather than duplicates. No account, no server. iCloud-synced households are roadmap. |
| **Resale intelligence** | Live (estimate) | Depreciation curves per device class (phone, laptop, tablet, wearable, camera, console, audio, TV, appliance) give a "worth about ₹X today / ₹Y in 6 months" estimate on electronics ≥ ₹15,000 and ≥ 10 months old. Always low confidence, always labelled a model — never a quote. |
| **SMS bank alerts** | Not possible on iOS | Apps cannot read Messages. Long-press → Share → LEVER, or screenshot it and let the watcher catch it. |

## Staying in front of the user (without nagging)

- **Reminders** deep-link to the exact purchase (2 days / 1 day before returns; 30 / 7 days before warranty end; 3 / 1 days before renewals) and show even while the app is open.
- **Live Activity**: the single most urgent deadline within 48 hours appears on the Lock Screen and in the Dynamic Island with a countdown; it ends itself when resolved or past.
- **Weekly digest**: one Monday 09:00 notification, scheduled only if the following two weeks hold a real deadline. It names the first one and splits "at stake" from "you could still save".

## Smart suggestions & tools

`InsightEngine` looks across the whole vault for patterns single-purchase rules miss — recurring total, subscriptions you marked unused, three or more streaming services, price creep, expensive electronics with no coverage or price link, unknown return windows, next-30-day outflow. Each suggestion names its evidence and deep-links to the fix.

Tools: **Subscription audit** (monthly/yearly totals, increases, unused), **Next 30 days** (renewals + deadlines, add all to Calendar), **Cost per use**, **Should I return it?** (used? faulty? cheaper elsewhere? → recommendation), **Ask LEVER** (on-device answers for warranties/renewals/returns/spending/savings; free-form questions go to Gemini with a document-free summary only when cloud is on).

## Free external services (no backend, no accounts)

| Service | Used for | What leaves the device |
|---|---|---|
| **Google Gemini API** (free tier, *your* key, opt-in) | Fills fields the on-device parser missed or read with low confidence | The recognised text of that one document — never images, PDFs, statements or the vault. Off by default. |
| **Clearbit Autocomplete** (keyless) | Merchant name → website domain for logos and support links | The merchant name only (e.g. "Croma"). Toggle in Privacy Center. |
| **Google / DuckDuckGo favicon services** (keyless) | Merchant logos | The merchant's domain. |
| **frankfurter.dev** (ECB rates, keyless) | "≈" conversion of other-currency opportunities into your home currency | Nothing personal — a currency code. Cached daily. |
| **Gmail API** (your OAuth client) | Inbox scan | Read-only, purchase-scoped search; parsed on device. |

Everything else — OCR, parsing, rules, storage, reminders, price checks — stays on the iPhone.

## Background work

`com.rakshit1998.lever.refresh` (BGAppRefresh, requested every ~12h; iOS decides actual timing):

1. re-run every opportunity rule (deadlines drift, renewals approach, things expire)
2. re-check tracked product pages
3. detect repeat charges across the vault
4. re-arm local notifications and refresh the widget snapshot

## Trust rules that don't bend

- Every amount is labelled: **potential saving** (renewals, price drops, fees, duplicates) vs **value at stake** (return windows, warranties). They are never summed together.
- Confidence and evidence kind (fact / inference / possibility / user input / unverified) travel with every opportunity.
- Nothing counts as saved until the user confirms it.
- LEVER prepares messages and opens the right app; it never sends, cancels, or pays.
- Statement text, screenshots and documents never leave the device. Cloud intelligence is off and opt-in.

## Permissions LEVER may ask for (each only when the feature is used)

Camera · Photos (screenshot watcher) · Notifications (deadline reminders) · Calendar write-only · Face ID (vault lock) · Wallet/FinanceKit (Apple approval pending) · Background App Refresh.
