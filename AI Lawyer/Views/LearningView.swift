import SwiftUI

struct LearningView: View {
    @EnvironmentObject var learningViewModel: LearningViewModel

    var body: some View {
        List {
            ForEach(LearningCategory.allCases) { category in
                if let topicList = learningViewModel.topics[category], !topicList.isEmpty {
                    Section(category.rawValue) {
                        ForEach(topicList) { topic in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(topic.title)
                                    .font(.headline)
                                Text(topic.summary)
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .navigationTitle("Learning")
    }
}
