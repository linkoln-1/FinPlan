import Foundation
import WidgetKit

struct WidgetSnapshot: Codable, Sendable {
    let primaryGoalTitle: String?
    let fundedMinor: Int64
    let targetMinor: Int64
    let currencyCode: String
    let currencyExponent: Int
    let percentBasisPoints: Int
    let safeToSpendMinor: Int64
    let monthIncomeMinor: Int64
    let monthExpensesMinor: Int64
    let monthSavedMinor: Int64
    let generatedAt: Date
}

extension WidgetSnapshot {
    private static let fullScaleBasisPoints = 10_000

    var remainingMinor: Int64 { max(0, targetMinor - fundedMinor) }

    var progressFraction: Double {
        min(1.0, max(0.0, Double(percentBasisPoints) / Double(Self.fullScaleBasisPoints)))
    }

    var percentWhole: Int { percentBasisPoints / 100 }

    static var placeholder: WidgetSnapshot {
        WidgetSnapshot(
            primaryGoalTitle: String(localized: "widget.placeholder.goal"),
            fundedMinor: 45_000_00,
            targetMinor: 120_000_00,
            currencyCode: "RUB",
            currencyExponent: 2,
            percentBasisPoints: 3_750,
            safeToSpendMinor: 18_500_00,
            monthIncomeMinor: 150_000_00,
            monthExpensesMinor: 92_400_00,
            monthSavedMinor: 25_000_00,
            generatedAt: Date()
        )
    }
}

enum WidgetSnapshotLoader {
    static let appGroupIdentifier = "group.com.alinashkhoev.finplan"
    static let snapshotFileName = "widget-snapshot.json"

    static func load(fileManager: FileManager = .default) -> WidgetSnapshot? {
        guard
            let container = fileManager.containerURL(
                forSecurityApplicationGroupIdentifier: appGroupIdentifier
            )
        else { return nil }
        let url = container.appendingPathComponent(snapshotFileName)
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(WidgetSnapshot.self, from: data)
    }
}

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct SnapshotProvider: TimelineProvider {
    private static let refreshInterval: TimeInterval = 4 * 60 * 60

    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: Date(), snapshot: .placeholder)
    }

    func getSnapshot(in context: Context, completion: @escaping @Sendable (SnapshotEntry) -> Void) {
        let snapshot = WidgetSnapshotLoader.load() ?? (context.isPreview ? .placeholder : nil)
        completion(SnapshotEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping @Sendable (Timeline<SnapshotEntry>) -> Void) {
        let now = Date()
        let entry = SnapshotEntry(date: now, snapshot: WidgetSnapshotLoader.load())
        completion(Timeline(entries: [entry], policy: .after(now.addingTimeInterval(Self.refreshInterval))))
    }
}
