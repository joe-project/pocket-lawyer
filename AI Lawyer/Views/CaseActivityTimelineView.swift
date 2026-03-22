import SwiftUI

/// Displays chronological case activity. Each row shows an icon, activity title, and timestamp.
struct CaseActivityTimelineView: View {
    /// Activities to display; shown newest first.
    let activities: [CaseActivity]

    private var sortedActivities: [CaseActivity] {
        activities.sorted { $0.timestamp > $1.timestamp }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WorkspaceCardHeader(icon: "📅", title: "Timeline")

            if sortedActivities.isEmpty {
                Text("No activity yet.")
                    .pocketSecondaryMonospaced(size: 14)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(sortedActivities.enumerated()), id: \.element.id) { index, activity in
                        activityRow(activity)
                        if index < sortedActivities.count - 1 {
                            Divider()
                                .background(LuxuryTheme.cardBorder)
                                .padding(.leading, 40)
                        }
                    }
                }
            }
        }
        .padding(LuxuryTheme.workspaceCardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .luxuryCard()
    }

    private func activityRow(_ activity: CaseActivity) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName(for: activity.type))
                .font(.title3)
                .foregroundStyle(AppColors.primary)
                .frame(width: 28, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                Text(activity.title)
                    .pocketSecondaryMonospaced(size: 14)

                Text(activity.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .pocketSecondaryMonospaced(size: 12)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private func iconName(for type: String) -> String {
        switch type {
        case "story_recorded": return "mic.fill"
        case "message_added": return "message.fill"
        case "evidence_uploaded": return "folder.fill.badge.plus"
        case "document_generated": return "doc.text.fill"
        case "deadline_detected": return "calendar.badge.clock"
        case "email_draft_created": return "envelope.fill"
        default: return "circle.fill"
        }
    }
}
