import Foundation
import Darwin

struct SharedStateStore {
    enum StoreError: LocalizedError {
        case homeDirectoryUnavailable

        var errorDescription: String? {
            switch self {
            case .homeDirectoryUnavailable:
                "DayMan could not resolve the current user's home directory."
            }
        }
    }

    private enum Filename {
        static let state = "platform-state-v1.json"
    }

    let baseURL: URL?

    init(baseURL: URL? = nil) {
        self.baseURL = baseURL
    }

    func loadState() throws -> PlatformStateEnvelope? {
        let url = try stateURL()
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
        let url = directory.appendingPathComponent(Filename.state)
        try DayManJSON.encoder.encode(state).write(
            to: url,
            options: .atomic
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
    }

    static func sharedDirectory(in homeDirectory: URL) -> URL {
        homeDirectory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("DayMan", isDirectory: true)
    }

    private func resolvedDirectory() throws -> URL {
        if let baseURL { return baseURL }
        return Self.sharedDirectory(in: try currentUserHomeDirectory())
    }

    private func stateURL() throws -> URL {
        try resolvedDirectory().appendingPathComponent(Filename.state)
    }

    private func currentUserHomeDirectory() throws -> URL {
        guard
            let passwordEntry = getpwuid(getuid()),
            let path = passwordEntry.pointee.pw_dir
        else {
            throw StoreError.homeDirectoryUnavailable
        }
        return URL(
            fileURLWithFileSystemRepresentation: path,
            isDirectory: true,
            relativeTo: nil
        )
    }

    private func createDirectoryIfNeeded(_ directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
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
