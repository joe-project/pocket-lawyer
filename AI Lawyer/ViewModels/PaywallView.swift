import SwiftUI

struct PaywallView: View {
    var body: some View {
        ZStack {
            LuxuryTheme.primaryBackground.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 8) {
                    Image(systemName: "doc.text.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(AppColors.primary)

                    Text("AI Lawyer")
                        .font(LuxuryTheme.titleFont(size: 28))
                        .foregroundColor(AppColors.textPrimary)

                    Text("3 days free, then choose your plan.")
                        .font(LuxuryTheme.bodyFont(size: 15))
                        .foregroundColor(AppColors.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Free trial")
                        .font(LuxuryTheme.sectionFont(size: 17))
                        .foregroundColor(AppColors.textPrimary)
                    Text("Use every feature with unlimited chats and documents for 3 days. After that you can upgrade for more control over your case files.")
                        .font(LuxuryTheme.bodyFont(size: 13))
                        .foregroundColor(AppColors.textPrimary)
                }
                .padding()
                .luxuryCard()
                .padding(.horizontal)

                VStack(spacing: 12) {
                    Button {
                        // Next: we’ll send unpaid users to the full app shell here
                    } label: {
                        Text("Continue in Free Mode")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppSecondaryButtonStyle())

                    Button {
                        // Next: StoreKit paywall will go here
                    } label: {
                        Text("See Subscription Options")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(AppButtonStyle())
                }
                .padding(.horizontal)

                Spacer()

                Text("This AI provides informational assistance and is not a licensed attorney. Always consult a lawyer before taking legal action.")
                    .font(LuxuryTheme.bodyFont(size: 12))
                    .foregroundColor(AppColors.textPrimary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal)

                Spacer().frame(height: 12)
            }
        }
    }
}
