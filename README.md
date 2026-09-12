# LEVER

**Don't leave money on the table.**

LEVER is an iOS app that finds money you are about to lose — and helps you recover it. Give it a receipt, screenshot, renewal email, booking or warranty document and it extracts what matters, finds deadlines and opportunities, prepares the message, and tracks what you actually saved.

## Build

Requirements: Xcode 16.2+, iOS 17 deployment target, [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```sh
xcodegen generate
open LEVER.xcodeproj
```

The `LEVER` scheme includes the `Products.storekit` configuration so the paywall works in the simulator without App Store Connect. Debug builds seed realistic sample data on first launch (Settings → Debug → *Load sample data* to re-seed).

```sh
# Unit + UI tests
xcodebuild -project LEVER.xcodeproj -scheme LEVER -destination 'platform=iOS Simulator,name=iPhone 16 Pro' test
```

UI-test launch arguments: `-ui-testing` (in-memory store, biometrics auto-pass), `-onboarding`, `-sample-data`, `-pro`.

## Architecture

```
LEVER/
  App/          Entry point, DI container (AppEnvironment), router, root shell
  Core/         Design system (Theme, components), utilities (DateMath, Money, Haptics)
  Models/       SwiftData entities + PurchaseDocument / OpportunityDraft value types
  Services/     Protocols + implementations: storage, notifications, StoreKit 2, security,
                analytics, price monitoring, share-extension inbox
  AI/           IntelligenceProvider (Local / Remote), Vision OCR, rule-based DocumentParser,
                OpportunityEngine + rules, ActionPlan / Claim / Negotiation generators
  Features/     Onboarding, Home, Capture, Vault, Purchase, Opportunity, Negotiation,
                Savings, Settings (Privacy Center), Paywall
  Intents/      App Intents + App Shortcuts
  SampleData/   DEBUG seeder
Shared/         App-group inbox and widget snapshot (app + extensions)
ShareExtension/ Share Sheet → app-group inbox
Widgets/        Potential savings & Money-at-risk widgets (home + lock screen)
Tests/          Unit tests (parsing, rules, ranking, calculations, persistence, StoreKit
                logic, notifications) and UI tests (onboarding, capture, home, savings, paywall, settings)
```

### Core loop
CAPTURE → `IntelligenceProvider.extractDocument` → `DocumentReviewView` (user confirms/edits) → `PurchaseRepository.save` builds the purchase graph (items, documents, subscription, warranties, return window) → `OpportunityEngine` rules → `Opportunity` + `Evidence` → `ActionPlan` → user acts (copy/share/mail/open) → `SavingsConfirmationSheet` → confirmed `SavingsEvent`.

### Trust rules baked into the code
- Every opportunity carries `Evidence` typed as fact / inference / possibility / user input / unverified, plus confidence and last-checked time.
- Return windows come only from the document or a curated, source-labelled merchant table (medium confidence, "verify"). Unknown merchants get **no** deadline.
- Savings count only after the user confirms them.
- Nothing is sent, cancelled or purchased on the user's behalf — LEVER prepares, the user acts.
- All processing is on-device (Vision + PDFKit + NaturalLanguage). `RemoteIntelligenceProvider` exists behind the same protocol and is off; cloud is opt-in and disabled until configured.

## Privacy
Local-first SwiftData store under `NSFileProtectionComplete`; originals stored with complete file protection; Keychain for the installation ID; optional Face ID lock; Privacy Center with export (JSON) and *Delete everything*. Analytics are event names only, logged locally.

## Roadmap (architected, not built)
Automated price monitoring via approved APIs, email/Gmail import, bank import, family vault (`householdID` on models), Apple Watch, Siri/Apple Intelligence, browser extension.
