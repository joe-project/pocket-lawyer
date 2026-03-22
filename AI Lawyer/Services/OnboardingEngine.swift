import Combine
import Foundation

// MARK: - Model

/// A single step in the first-case onboarding flow.
struct OnboardingStep: Identifiable, Equatable {
    let id: Int
    let title: String
    let description: String

    init(id: Int, title: String, description: String) {
        self.id = id
        self.title = title
        self.description = description
    }
}

// MARK: - Engine

/// Guides new users through the first case creation process: record/type story → upload evidence → generate initial case analysis. Tracks which step the user is currently on.
final class OnboardingEngine: ObservableObject {

    /// Ordered steps for first case creation.
    static let steps: [OnboardingStep] = [
        OnboardingStep(
            id: 0,
            title: "Record or type the story",
            description: "Tell us what happened in your own words. You can type in Chat or record a voice story so we can build your case."
        ),
        OnboardingStep(
            id: 1,
            title: "Upload evidence",
            description: "Add photos, documents, messages, or other evidence to your case. Everything is organized by category."
        ),
        OnboardingStep(
            id: 2,
            title: "Generate initial case analysis",
            description: "We’ll analyze your story and evidence to identify claims, timeline, and next steps."
        ),
    ]

    /// Index of the current step (0-based). Can be steps.count when complete. Persisted so onboarding state survives app restarts.
    @Published var currentStepIndex: Int

    private static let currentStepKey = "OnboardingEngine.currentStepIndex"

    private func persistStepIndex() {
        UserDefaults.standard.set(currentStepIndex, forKey: Self.currentStepKey)
    }

    init() {
        let raw = UserDefaults.standard.object(forKey: Self.currentStepKey) as? Int ?? 0
        self.currentStepIndex = min(max(0, raw), Self.steps.count)
    }

    /// The step the user is currently on. When complete, returns the last step.
    var currentStep: OnboardingStep {
        let idx = min(currentStepIndex, Self.steps.count - 1)
        return Self.steps[idx]
    }

    /// Whether the user is on the last step.
    var isOnLastStep: Bool {
        currentStepIndex >= Self.steps.count - 1
    }

    /// Whether onboarding is complete (user has passed the last step).
    var isComplete: Bool {
        currentStepIndex >= Self.steps.count
    }

    /// Advances to the next step. Does nothing if already on the last step unless `allowFinish` is true, in which case completing the last step marks onboarding complete.
    func advance() {
        if currentStepIndex < Self.steps.count - 1 {
            currentStepIndex += 1
            persistStepIndex()
        }
    }

    /// Moves to the previous step. Does nothing if already on the first step.
    func goBack() {
        if currentStepIndex > 0 {
            currentStepIndex -= 1
            persistStepIndex()
        }
    }

    /// Jumps to a specific step by index (0-based). Clamped to valid range.
    func go(to stepIndex: Int) {
        currentStepIndex = min(max(0, stepIndex), Self.steps.count)
        persistStepIndex()
    }

    /// Marks onboarding as complete and resets current step to the end (e.g. after user generates initial case analysis).
    func complete() {
        currentStepIndex = Self.steps.count
        persistStepIndex()
    }

    /// Resets onboarding to the first step (e.g. for testing or “start over”).
    func reset() {
        currentStepIndex = 0
        persistStepIndex()
    }
}
