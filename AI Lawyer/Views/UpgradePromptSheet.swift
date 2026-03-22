import SwiftUI

/// Sheet shown when the user tries to access a premium feature without access. Displays the prompt message and a button to open subscription options.
struct UpgradePromptSheet: View {
    let prompt: UpgradePrompt
    let onDismiss: () -> Void
    var onUpgrade: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                Image(systemName: "lock.circle.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(AppColors.primary)

                Text(prompt.title)
                    .font(LuxuryTheme.sectionFont(size: 20))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)

                Text(prompt.message)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Button("See subscription options") {
                    onUpgrade?()
                    onDismiss()
                }
                .buttonStyle(AppButtonStyle())
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()
            }
            .padding(.top, 32)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(LuxuryTheme.primaryBackground)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onDismiss() }
                }
            }
            .toolbarColorScheme(.light, for: .navigationBar)
        }
    }
}
