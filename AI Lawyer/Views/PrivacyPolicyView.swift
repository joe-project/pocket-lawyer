import SwiftUI

struct PrivacyPolicyView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Privacy Policy")
                    .font(.title2)
                    .fontWeight(.bold)

                Group {
                    Text("Information we collect")
                        .font(.headline)
                    Text("We may collect information you provide when using the app, including messages you send, case details, and documents you create or upload. If you use cloud or account features, we may store data necessary to sync your cases and preferences.")

                    Text("How we use it")
                        .font(.headline)
                    Text("We use this information to provide and improve the AI Lawyer service, to generate responses and documents you request, and to maintain your cases and timeline within the app.")

                    Text("Data storage and security")
                        .font(.headline)
                    Text("Data may be stored on your device and, where applicable, on our servers or third‑party services. We take reasonable steps to protect your data but cannot guarantee absolute security.")

                    Text("Third parties")
                        .font(.headline)
                    Text("To provide AI features, we may send your inputs to third‑party AI providers. Their use of data is governed by their respective privacy policies.")

                    Text("Your choices")
                        .font(.headline)
                    Text("You can control what information you provide. Deleting the app may remove local data; contact us for questions about other stored data.")

                    Text("Updates")
                        .font(.headline)
                    Text("We may update this policy from time to time. Continued use of the app after changes constitutes acceptance of the updated policy.")
                }
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}
