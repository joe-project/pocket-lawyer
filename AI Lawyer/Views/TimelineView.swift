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
        .background(Color("BackgroundNavy").opacity(0.98))
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.badge.checkmark")
                .font(.system(size: 44))
                .foregroundColor(Color("GoldAccent").opacity(0.7))
            Text("No timeline events yet")
                .font(.headline)
                .foregroundColor(.white)
            Text("Tasks, filings, and AI-generated responses will appear here and update automatically.")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.8))
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
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)
                if let summary = event.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.8))
                }
                Text(event.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.6))
                Button("Revert to here") {
                    caseTreeViewModel.revertTimeline(to: event.id, caseId: caseId)
                }
                .font(.caption)
                .foregroundColor(Color("GoldAccent"))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.08))
            .cornerRadius(10)
        }
    }

    private func icon(for kind: TimelineEventKind) -> some View {
        let (name, color) = switch kind {
        case .task: ("checkmark.circle.fill", Color.blue)
        case .filing: ("doc.fill", Color.orange)
        case .response: ("text.bubble.fill", Color("GoldAccent"))
        }
        return Image(systemName: name)
            .font(.title2)
            .foregroundColor(color)
    }
}
