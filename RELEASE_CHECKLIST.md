# LEVER — Release Checklist

## Build health
- [x] `xcodebuild build` succeeds with zero compiler warnings (Xcode 16.2, Swift 5 mode, Swift 6 compiler)
- [x] No force unwraps / `try!` in production targets (only `preconditionFailure` in the preview/test container path)
- [x] Unit tests pass (parsing, deadlines, subscriptions, savings, ranking, warranties, confidence, persistence, StoreKit logic, notification planning, inbox, analytics, observation)
- [x] UI tests pass (onboarding, capture → review → magic moment, home cards, opportunity → savings confirmation, paywall, settings/privacy)

## Before first App Store submission
- [x] `DEVELOPMENT_TEAM` (48TGY734WW) set in `project.yml`; bundle IDs use the `com.rakshit1998.lever` prefix
- [ ] Register App Group `group.com.rakshit1998.lever` and enable it on all three bundle IDs (`com.rakshit1998.lever`, `.share`, `.widgets`)
- [ ] Create in-app purchases in App Store Connect with the exact IDs `lever_pro_monthly`, `lever_pro_yearly`, `lever_pro_lifetime`; prices are never hardcoded — localised pricing (incl. India) comes from StoreKit
- [ ] Add a 1024×1024 app icon to `Assets.xcassets/AppIcon`
- [ ] Add real privacy policy + terms URLs (paywall currently links Apple's standard EULA)
- [ ] App Privacy nutrition label: Data Not Collected (analytics are local-only); update if a network analytics backend is added
- [ ] Review `NSCameraUsageDescription` / `NSFaceIDUsageDescription` copy
- [ ] Confirm Share Extension activation rules on device (Photos, Safari screenshot, Files PDF, Mail attachment, text)
- [ ] Test notifications on device (time-sensitive interruption level requires the entitlement or downgrade to `.active`)
- [ ] Run the app with `-onboarding` cleared on a fresh install; verify empty states on Home, Vault, Savings
- [ ] Verify Face ID lock on a device (simulator uses the passcode fallback)
- [ ] Localise strings if shipping outside English markets
- [ ] Request the FinanceKit entitlement (`com.apple.developer.financekit`) from Apple; until granted, Wallet shows "not enabled for this build"
- [ ] Enable Background Modes → Background fetch on the app target in App Store Connect capabilities (Info.plist already declares `BGTaskSchedulerPermittedIdentifiers`)
- [ ] Verify Photos (screenshot watcher) and Calendar (write-only) prompts on device; both are opt-in and only requested when used
- [ ] Create a Google Cloud OAuth client (iOS, bundle `com.rakshit1998.lever`, Gmail API enabled) and paste the client ID in Settings → Sources → Email; Google's OAuth verification is required before public release with the gmail.readonly scope
- [ ] Verify `.leverpurchase` files open in LEVER from Files, Messages and AirDrop on device (document type declared in Info.plist)
- [ ] Test statement import with real CSV/PDF exports from 2–3 Indian banks (HDFC, ICICI, SBI) and one card issuer

## Product / trust
- [x] No claims of guaranteed savings anywhere in copy; potential amounts are labelled "potential"
- [x] Savings only counted after explicit user confirmation
- [x] Return-policy table entries carry a source note and medium confidence; unknown merchants get no deadline
- [x] No autonomous sends, cancellations or purchases
- [x] No documents leave the device; cloud provider disabled and opt-in only
- [x] Notifications only about money deadlines — no re-engagement nags

## Security
- [x] SwiftData store + document files under `NSFileProtectionComplete`
- [x] Keychain items `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`
- [x] Delete-everything clears store, files, inbox, Keychain, notifications and widget snapshot
- [x] No secrets in source control (`.gitignore` excludes `Secrets.swift`, `.env`)

## Secrets
- `Config/Secrets.xcconfig` holds the Gemini key (and optionally a Gmail client ID). It is gitignored — copy it to any new machine by hand. For App Store builds, prefer leaving the key out of the shipped binary (a client-side key can be extracted); users then paste their own key in Privacy Center.

## External services to disclose in App Privacy
- Gemini (opt-in, user key): document text → Google. Declare "Other Usage Data" only if enabled; default off.
- Clearbit / Google / DuckDuckGo favicons: merchant names/domains. Not linked to identity.
- frankfurter.dev: currency codes only.

## Known limitations (v1)
- Price tracking reads public page metadata only; pages without Open Graph/schema.org price tags fall back to manual entry
- Apple Wallet import compiles but is inert until Apple grants the FinanceKit entitlement
- Remote intelligence is a fallback stub — `RemoteIntelligenceProvider` needs an endpoint + consent flow
- Family vault is data-model-ready only (`householdID`)
- Live Activities not implemented; lock-screen accessory widgets cover urgent deadlines
