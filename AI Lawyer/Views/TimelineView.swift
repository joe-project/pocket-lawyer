import SwiftUI

struct TimelineView: View {
    @EnvironmentObject var caseTreeViewModel: CaseTreeViewModel

    var body: some View {
        Group {
            if let caseFolder = caseTreeViewModel.selectedCase {
                let events = caseTreeViewModel.events(for: caseFolder.id)
                if events.isEmpty {
                    emptyView
                } else {
                    timelineList(events: events, caseId: caseFolder.id)
                }
            } else {
                emptyView
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("No timeline events yet")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Tasks, filings, and AI-generated responses will appear here and update automatically.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func timelineList(events: [TimelineEvent], caseId: UUID) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 12) {
                ForEach(events) { event in
                    timelineRow(event: event, caseId: caseId)
                }
            }
            .padding()
        }
    }

    private func timelineRow(event: TimelineEvent, caseId: UUID) -> some View {
        HStack(alignment: .top, spacing: 12) {
            icon(for: event.kind)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .fontWeight(.semibold)
                    .foregroundColor(AppColors.textPrimary)
                if let summary = event.summary, !summary.isEmpty {
                    Text(summary)
                        .font(LuxuryTheme.bodyFont(size: 12))
                        .foregroundColor(AppColors.textPrimary)
                }
                Text(event.createdAt, style: .date)
                    .font(LuxuryTheme.bodyFont(size: 11))
                    .foregroundColor(AppColors.textPrimary)
                Button("Revert to here") {
                    caseTreeViewModel.revertTimeline(to: event.id, caseId: caseId)
                }
                .font(LuxuryTheme.bodyFont(size: 12))
                .foregroundColor(AppColors.textPrimary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(LuxuryTheme.surfaceCard)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
            )
            .cornerRadius(10)
        }
    }

    private func icon(for kind: TimelineEventKind) -> some View {
        let (name, color) = switch kind {
        case .task: ("checkmark.circle.fill", Color.blue)
        case .filing: ("doc.fill", Color.orange)
        case .response: ("text.bubble.fill", AppColors.primary)
        }
        return Image(systemName: name)
            .font(.title2)
            .foregroundColor(color)
    }
}
