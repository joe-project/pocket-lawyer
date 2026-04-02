import SwiftUI

struct WelcomeView: View {
    @Binding var hasSeenWelcome: Bool
    @State private var currentStep = 0
    @State private var pointerPulse = false
    private let pageCount = 3

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
                    thirdScreen.tag(2)
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
        .onAppear {
            withAnimation(.easeInOut(duration: 1.15).repeatForever(autoreverses: true)) {
                pointerPulse = true
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
            Text("Why Pocket Lawyer Is Different")
                .font(.system(size: 34, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)
            Text("One conversation turns into real legal work. We reason through facts, build timelines, track evidence, and organize the case as you chat.")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(title: "Smarter legal logic", description: "It follows the facts, surfaces missing details, and keeps the case organized in the background.")
                featureRow(title: "Built for real work", description: "Timelines, evidence, documents, notes, and next steps stay connected to the right folder.")
                featureRow(title: "Better privacy model", description: "Your case files stay on your device while the assistant helps you think clearly and move faster.")
            }
            .padding(18)
            .background(Color.white.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var secondScreen: some View {
        VStack(spacing: 22) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                Text("Ask anything. Build as you go.")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.white)

                Text("Use chat naturally. Pocket Lawyer can turn the conversation into a timeline, evidence list, documents needed, and next-step instructions without making you fill out a form.")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(.white.opacity(0.8))
                    .lineSpacing(5)

                VStack(alignment: .leading, spacing: 14) {
                    tutorialCard(icon: "message.fill", title: "Ask any legal question", description: "Start broad or specific. The assistant follows up and keeps the thread grounded in the facts.")
                    tutorialCard(icon: "calendar", title: "Build timelines", description: "Important dates, missing gaps, and deadlines can be built out as the story becomes clearer.")
                    tutorialCard(icon: "checklist", title: "Track evidence and documents", description: "Photos, messages, filings, and missing paperwork can be separated into what you have and what you still need.")
                }
            }
            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private var thirdScreen: some View {
        VStack(spacing: 20) {
            Spacer()

            Text("Organize folders in seconds")
                .font(.system(size: 32, weight: .bold))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            Text("Add folders, rename them, and keep each case or document set clean without leaving the sidebar.")
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
                .multilineTextAlignment(.center)
                .lineSpacing(5)

            folderTutorialMock

            Spacer()
        }
        .padding(.horizontal, 24)
    }

    private func featureRow(title: String, description: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(.white)
            Text(description)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func tutorialCard(icon: String, title: String, description: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 17, weight: .semibold))
                .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.65))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(.white)
                Text(description)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private var folderTutorialMock: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))

            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Cases & Research")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "plus")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundColor(Color(red: 1.0, green: 0.35, blue: 0.65))
                }

                folderRow(title: "General Law Questions", isHighlighted: false)
                folderRow(title: "Jones vs. Smith (Example Case)", isHighlighted: true)
                folderRow(title: "Trust Law", isHighlighted: false)

                HStack {
                    Text("Tap + to add folders")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 1.0, green: 0.72, blue: 0.84))
                    Spacer()
                }
                .padding(.top, 6)

                HStack {
                    Text("Long-press a folder to rename it")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(red: 0.72, green: 0.78, blue: 1.0))
                    Spacer()
                }
            }
            .padding(20)

            VStack {
                HStack {
                    Spacer()
                    animatedPointer(color: Color(red: 1.0, green: 0.35, blue: 0.65))
                        .offset(x: -4, y: 20)
                }
                Spacer()
            }

            VStack {
                Spacer()
                HStack {
                    animatedPointer(color: Color(red: 0.45, green: 0.55, blue: 1.0))
                        .rotationEffect(.degrees(-28))
                        .offset(x: 66, y: -112)
                    Spacer()
                }
            }
        }
        .frame(height: 320)
    }

    private func folderRow(title: String, isHighlighted: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundColor(Color(red: 0.67, green: 0.51, blue: 1.0))

            Text(title)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.white)
                .lineLimit(1)

            Spacer()

            Image(systemName: "ellipsis")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.white.opacity(0.45))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(isHighlighted ? Color.white.opacity(0.09) : Color.white.opacity(0.04))
        )
    }

    private func animatedPointer(color: Color) -> some View {
        Image(systemName: "hand.point.up.left.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundColor(color)
            .shadow(color: color.opacity(0.45), radius: 12, x: 0, y: 0)
            .scaleEffect(pointerPulse ? 1.08 : 0.92)
            .opacity(pointerPulse ? 1.0 : 0.72)
    }
}
