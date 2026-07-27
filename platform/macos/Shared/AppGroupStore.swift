import Foundation

struct AppGroupStore {
    enum StoreError: LocalizedError {
        case appGroupUnavailable(String)

        var errorDescription: String? {
            switch self {
            case .appGroupUnavailable(let identifier):
                "The App Group \(identifier) is unavailable. Check signing and entitlements."
            }
        }
    }

    private enum Filename {
        static let state = "platform-state-v1.json"
    }

    let baseURL: URL?
    let appGroupIdentifier: String

    init(
        baseURL: URL? = nil,
        appGroupIdentifier: String = Bundle.main.object(
            forInfoDictionaryKey: "DayManAppGroupIdentifier"
        ) as? String ?? "group.com.glengerbush.DayMan"
    ) {
        self.baseURL = baseURL
        self.appGroupIdentifier = appGroupIdentifier
    }

    func loadState() throws -> PlatformStateEnvelope? {
        let url = try resolvedDirectory().appendingPathComponent(Filename.state)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try DayManJSON.decoder.decode(
            PlatformStateEnvelope.self,
            from: Data(contentsOf: url)
        )
    }

    func loadSnapshot() throws -> ClockSnapshot? {
        try loadState()?.snapshot
    }

    func loadSnapshot(at date: Date) throws -> ClockSnapshot? {
        guard let state = try loadState() else { return nil }
        return snapshot(in: state, at: date)
    }

    func snapshot(
        in state: PlatformStateEnvelope,
        at date: Date
    ) -> ClockSnapshot? {
        let dateKey = localDateKey(
            for: date,
            timeZoneIdentifier: state.settings.location.timezone
        )
        if state.snapshots.isEmpty {
            return state.snapshot.dateKey == dateKey ? state.snapshot : nil
        }
        return state.snapshots.first { $0.dateKey == dateKey }
    }

    func save(_ state: PlatformStateEnvelope) throws {
        let directory = try resolvedDirectory()
        try createDirectoryIfNeeded(directory)
        try DayManJSON.encoder.encode(state).write(
            to: directory.appendingPathComponent(Filename.state),
            options: .atomic
        )
    }

    private func resolvedDirectory() throws -> URL {
        if let baseURL { return baseURL }
        guard let url = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            throw StoreError.appGroupUnavailable(appGroupIdentifier)
        }
        return url
    }

    private func createDirectoryIfNeeded(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
    }

    private func localDateKey(
        for date: Date,
        timeZoneIdentifier: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier) ?? .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
