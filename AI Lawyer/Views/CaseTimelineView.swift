import SwiftUI

/// Displays the reconstructed case timeline. Events appear chronologically with date (e.g. "Jan 3") and description.
struct CaseTimelineView: View {
    /// Reconstructed timeline events. Sorted chronologically (oldest first); events without a date appear after dated events.
    let events: [ReconstructedTimelineEvent]

    private static let shortDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        f.timeZone = TimeZone.current
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    private var sortedEvents: [ReconstructedTimelineEvent] {
        events.sorted { e1, e2 in
            let d1 = e1.date ?? .distantFuture
            let d2 = e2.date ?? .distantFuture
            return d1 < d2
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if sortedEvents.isEmpty {
                emptyView
            } else {
                timelineList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var header: some View {
        Text("Timeline")
            .font(LuxuryTheme.sectionFont(size: 18))
            .foregroundColor(AppColors.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
    }

    private var emptyView: some View {
        VStack(spacing: 12) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(AppColors.primary)
            Text("No timeline events yet")
                .font(LuxuryTheme.sectionFont(size: 17))
                .foregroundColor(AppColors.textPrimary)
            Text("Reconstruct the timeline from your messages and evidence to see events here.")
                .font(LuxuryTheme.bodyFont(size: 14))
                .foregroundColor(AppColors.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var timelineList: some View {
        ScrollView(.vertical, showsIndicators: true) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(sortedEvents) { event in
                    timelineRow(event: event)
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
    }

    private func timelineRow(event: ReconstructedTimelineEvent) -> some View {
        HStack(alignment: .top, spacing: 16) {
            dateColumn(event.date)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.description)
                    .font(LuxuryTheme.bodyFont(size: 15))
                    .foregroundColor(AppColors.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 12)
        .background(LuxuryTheme.surfaceCard)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(LuxuryTheme.cardBorder, lineWidth: 1)
        )
        .cornerRadius(10)
        .padding(.vertical, 4)
    }

    private func dateColumn(_ date: Date?) -> some View {
        Text(dateLabel(date))
            .font(LuxuryTheme.sectionFont(size: 14))
            .foregroundColor(AppColors.textPrimary)
            .frame(width: 56, alignment: .leading)
    }

    private func dateLabel(_ date: Date?) -> String {
        guard let d = date else { return "—" }
        return Self.shortDateFormatter.string(from: d)
    }
}
