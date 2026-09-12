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
| **Email inbox import** | Roadmap | Mail → Share → LEVER works today. Automatic Gmail/IMAP import needs OAuth and a privacy review; it will be opt-in and on-device parsing only. |
| **SMS bank alerts** | Not possible on iOS | Apps cannot read Messages. Long-press → Share → LEVER, or screenshot it and let the watcher catch it. |

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
