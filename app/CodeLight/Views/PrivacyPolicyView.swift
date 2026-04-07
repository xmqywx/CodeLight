import SwiftUI

/// In-app privacy policy — Apple requires the policy be viewable without leaving
/// the app. Content kept short and in sync with /PRIVACY.md at the repo root.
struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        Text(String(localized: "privacy_policy"))
                            .font(.title)
                            .fontWeight(.bold)
                        Text(String(localized: "privacy_last_updated"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    section(
                        title: String(localized: "privacy_overview"),
                        body: String(localized: "privacy_overview_body")
                    )

                    section(
                        title: String(localized: "privacy_data_collection"),
                        body: String(localized: "privacy_data_collection_body")
                    )

                    section(
                        title: String(localized: "privacy_data_storage"),
                        body: String(localized: "privacy_data_storage_body")
                    )

                    section(
                        title: String(localized: "privacy_encryption"),
                        body: String(localized: "privacy_encryption_body")
                    )

                    section(
                        title: String(localized: "privacy_third_party"),
                        body: String(localized: "privacy_third_party_body")
                    )

                    section(
                        title: String(localized: "privacy_camera"),
                        body: String(localized: "privacy_camera_body")
                    )

                    section(
                        title: String(localized: "privacy_push"),
                        body: String(localized: "privacy_push_body")
                    )

                    section(
                        title: String(localized: "privacy_open_source"),
                        body: String(localized: "privacy_open_source_body")
                    )
                    Link("https://github.com/xmqywx/CodeLight",
                         destination: URL(string: "https://github.com/xmqywx/CodeLight")!)
                        .font(.footnote)

                    section(
                        title: String(localized: "privacy_contact"),
                        body: String(localized: "privacy_contact_body")
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(String(localized: "privacy_policy"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "done")) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func section(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.headline)
            Text(body)
                .font(.body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
