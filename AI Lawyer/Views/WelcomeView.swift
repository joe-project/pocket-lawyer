import SwiftUI

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool
    @State private var currentStep = 0
    private let pageCount = 2

    private var isLastStep: Bool { currentStep == pageCount - 1 }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.blue.opacity(0.3)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 18) {
                TabView(selection: $currentStep) {
                    firstScreen.tag(0)
                    secondScreen.tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.2), value: currentStep)

                pagerIndicator
                    .padding(.bottom, 4)

                Button(action: {
                    if isLastStep {
                        hasSeenWelcome = true
                    } else {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentStep += 1
                        }
                    }
                }) {
                    Text(isLastStep ? "Get Started" : "Continue")
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            LinearGradient(
                                colors: [Color.blue, Color.blue.opacity(0.7)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .cornerRadius(14)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
        }
    }

    private var pagerIndicator: some View {
        HStack(spacing: 8) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(i == currentStep ? Color.white : Color.white.opacity(0.25))
                    .frame(width: i == currentStep ? 8 : 6, height: i == currentStep ? 8 : 6)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var firstScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            AppLogo(size: 140)
            Text("Your Legal System. In Your Pocket.")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Organize cases. Generate documents. Get answers instantly.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var secondScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            AppLogo(size: 140)
            Text("Start your first case in seconds")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("Everything you need. Nothing you don't.")
                .font(.subheadline)
                .foregroundColor(.gray)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .padding(.horizontal, 24)
    }
}
