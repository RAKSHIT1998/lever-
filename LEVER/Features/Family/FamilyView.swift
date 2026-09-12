import SwiftUI
import SwiftData

/// Household settings: a name, the people in it, and what's been shared. Sharing itself is per purchase.
struct FamilyView: View {
    @Environment(AppEnvironment.self) private var env
    @Query private var purchases: [Purchase]
    @State private var newMember = ""

    private var profile: UserProfile { env.repository.profile() }
    private var shared: [Purchase] { purchases.filter { $0.householdID != nil || $0.sharedBy != nil } }

    var body: some View {
        List {
            Section {
                TextField("Household name (e.g. The Bargotras)", text: Binding(get: { profile.householdName ?? "" }, set: { profile.householdName = $0.isEmpty ? nil : $0; try? env.container.mainContext.save() }))
                TextField("Your name (shown to family)", text: Binding(get: { profile.displayName ?? "" }, set: { profile.displayName = $0.isEmpty ? nil : $0; try? env.container.mainContext.save() }))
            } header: { Text("Household") } footer: {
                Text("Share any purchase from its detail page. It arrives as a file the other person opens in LEVER — receipts, warranties and deadlines included. No account, no server.")
            }

            Section("Members") {
                ForEach(profile.householdMembers, id: \.self) { member in
                    Label(member, systemImage: "person.fill")
                }
                .onDelete { offsets in
                    var members = profile.householdMembers
                    members.remove(atOffsets: offsets)
                    profile.householdMembers = members
                    try? env.container.mainContext.save()
                }
                HStack {
                    TextField("Add a member", text: $newMember)
                    Button("Add") {
                        let name = newMember.trimmingCharacters(in: .whitespaces)
                        guard !name.isEmpty else { return }
                        profile.householdMembers.append(name)
                        newMember = ""
                        try? env.container.mainContext.save()
                    }
                    .disabled(newMember.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Shared records") {
                if shared.isEmpty {
                    Text("Nothing shared yet.").foregroundStyle(LeverColor.inkSecondary)
                } else {
                    ForEach(shared) { p in
                        NavigationLink { PurchaseDetailView(purchase: p) } label: {
                            HStack {
                                MerchantMonogram(name: p.merchantName, category: p.merchantCategory, size: 32)
                                VStack(alignment: .leading) {
                                    Text(p.title).font(LeverFont.callout)
                                    Text(p.sharedBy.map { "From \($0)" } ?? "Shared by you").font(LeverFont.caption).foregroundStyle(LeverColor.inkSecondary)
                                }
                            }
                        }
                    }
                }
            }

            Section {
                Text("iCloud-synced household vaults are on the roadmap. File sharing works today and keeps everything on your devices.")
                    .font(.caption2).foregroundStyle(LeverColor.inkTertiary)
            }
        }
        .scrollContentBackground(.hidden)
        .leverScreenBackground()
        .navigationTitle("Family vault")
        .navigationBarTitleDisplayMode(.inline)
    }
}
