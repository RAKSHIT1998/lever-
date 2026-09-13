import SwiftUI

/// Real merchant logo when we can get one (directory domain or a free Clearbit lookup), monogram otherwise.
/// Respects the "Show merchant logos" privacy switch — with it off, no merchant name ever leaves the device.
struct MerchantAvatar: View {
    @Environment(AppEnvironment.self) private var env
    let name: String
    var category: MerchantCategory = .other
    var size: CGFloat = 40

    @State private var logoURL: URL?
    @State private var domain: String?
    @State private var usedFallback = false
    @State private var failed = false

    var body: some View {
        ZStack {
            MerchantMonogram(name: name, category: category, size: size)
            if let logoURL, !failed {
                AsyncImage(url: logoURL) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFit()
                            .padding(size * 0.16)
                            .background(Color.white, in: Circle())
                            .overlay(Circle().strokeBorder(LeverColor.hairline, lineWidth: 1))
                    case .failure:
                        Color.clear.onAppear {
                            // Try the second free icon service once, then settle on the monogram.
                            if let domain, !usedFallback { usedFallback = true; self.logoURL = MerchantIdentityService.fallbackLogoURL(domain: domain) } else { failed = true }
                        }
                    default:
                        Color.clear
                    }
                }
                .frame(width: size, height: size)
                .clipShape(Circle())
                .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
        .task(id: name) { await resolve() }
    }

    private func resolve() async {
        guard env.settings.showMerchantLogos else { logoURL = nil; return }
        if let known = MerchantDirectory().entry(named: name)?.domain {
            domain = known
            logoURL = MerchantIdentityService.logoURL(domain: known)
            return
        }
        if let identity = await env.merchantIdentity.identity(for: name) {
            domain = identity.domain
            logoURL = identity.logoURL
        }
    }
}
