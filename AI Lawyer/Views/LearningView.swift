import SwiftUI

struct LearningView: View {
    @EnvironmentObject var learningViewModel: LearningViewModel

    var body: some View {
        List {
            ForEach(LearningCategory.allCases) { category in
                if let topicList = learningViewModel.topics[category], !topicList.isEmpty {
                    Section {
                        ForEach(topicList) { topic in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(topic.title)
                                    .font(AppTypography.body)
                                    .foregroundColor(AppColors.textPrimary)
                                Text(topic.summary)
                                    .font(AppTypography.body)
                                    .foregroundColor(AppColors.textPrimary)
                            }
                            .padding(.vertical, 4)
                        }
                    } header: {
                        Text(category.rawValue)
                            .font(AppTypography.heading)
                            .foregroundColor(AppColors.textPrimary)
                    }
                    .listRowBackground(LuxuryTheme.surfaceCard)
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(LuxuryTheme.primaryBackground)
        .navigationTitle("Learning")
        .toolbarColorScheme(.light, for: .navigationBar)
    }
}
