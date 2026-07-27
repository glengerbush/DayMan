import SwiftUI
import WidgetKit

struct DayManTimelineEntry: TimelineEntry {
    let date: Date
    let snapshot: ClockSnapshot
    let isConfigured: Bool
}

struct DayManTimelineProvider: TimelineProvider {
    private let store = SharedStateStore()

    func placeholder(in context: Context) -> DayManTimelineEntry {
        DayManTimelineEntry(
            date: Date(),
            snapshot: .preview,
            isConfigured: true
        )
    }

    func getSnapshot(
        in context: Context,
        completion: @escaping (DayManTimelineEntry) -> Void
    ) {
        completion(entry(at: Date()))
    }

    func getTimeline(
        in context: Context,
        completion: @escaping (Timeline<DayManTimelineEntry>) -> Void
    ) {
        let now = Date()
        guard let state = try? store.loadState() else {
            let retry = now.addingTimeInterval(15 * 60)
            completion(Timeline(entries: [entry(at: now)], policy: .after(retry)))
            return
        }

        // Each entry selects the matching local-date snapshot from the saved
        // queue. This allows the same timeline to cross midnight without
        // showing yesterday's geometry when the full app is not running.
        let finalDate = now.addingTimeInterval(24 * 60 * 60)
        let dates = timelineDates(from: now, through: finalDate)
        let entries = dates.map {
            entry(from: state, at: $0)
        }

        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private func entry(at date: Date) -> DayManTimelineEntry {
        if let state = try? store.loadState() {
            return entry(from: state, at: date)
        }
        return DayManTimelineEntry(date: date, snapshot: .placeholder(at: date), isConfigured: false)
    }

    private func entry(
        from state: PlatformStateEnvelope,
        at date: Date
    ) -> DayManTimelineEntry {
        guard let snapshot = store.snapshot(in: state, at: date) else {
            return DayManTimelineEntry(
                date: date,
                snapshot: .placeholder(at: date),
                isConfigured: false
            )
        }
        return DayManTimelineEntry(
            date: date,
            snapshot: snapshot,
            isConfigured: true
        )
    }

    private func timelineDates(from start: Date, through end: Date) -> [Date] {
        var dates = [start]
        var cursor = start
        while dates.count < 49,
              let next = Calendar.current.date(byAdding: .minute, value: 30, to: cursor),
              next <= end {
            dates.append(next)
            cursor = next
        }
        return dates
    }

}

struct DayManClockWidgetView: View {
    let entry: DayManTimelineEntry

    var body: some View {
        Group {
            if entry.isConfigured {
                DialSnapshotView(snapshot: entry.snapshot, date: entry.date)
                    .padding(8)
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "clock.badge.questionmark")
                        .font(.title)
                        .foregroundStyle(Color(hexValue: "#ffd166"))
                    Text("Open DayMan")
                        .font(.headline)
                    Text("Choose a location or refresh this clock in DayMan.")
                        .font(.caption)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                .padding()
            }
        }
        .containerBackground(
            LinearGradient(
                colors: [Color(hexValue: "#101a2d"), Color(hexValue: "#08101d")],
                startPoint: .top,
                endPoint: .bottom
            ),
            for: .widget
        )
        .widgetURL(DayManWidgetConstants.launchURL)
    }
}

struct DayManClockWidget: Widget {
    let kind = DayManWidgetConstants.kind

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: DayManTimelineProvider()) { entry in
            DayManClockWidgetView(entry: entry)
        }
        .configurationDisplayName("DayMan Clock")
        .description("Your 24-hour Sun, twilight, and Moon clock.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

private extension ClockSnapshot {
    static var preview: ClockSnapshot {
        .placeholder(at: Date())
    }
}

private extension Color {
    init(hexValue: String) {
        let cleaned = hexValue.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var value: UInt64 = 0
        Scanner(string: cleaned).scanHexInt64(&value)
        self.init(
            .sRGB,
            red: Double(value >> 16) / 255,
            green: Double(value >> 8 & 0xff) / 255,
            blue: Double(value & 0xff) / 255,
            opacity: 1
        )
    }
}
