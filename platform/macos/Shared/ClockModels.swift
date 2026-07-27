import Foundation

enum DayManWidgetConstants {
    static let kind = "DayManClockWidget"
    static let launchURL = URL(string: "dayman://open")!
}

enum DayManJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = fractionalISO8601.date(from: value) ?? basicISO8601.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 date, received \(value)"
            )
        }
        return decoder
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(fractionalISO8601.string(from: date))
        }
        return encoder
    }

    private static let fractionalISO8601: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    private static let basicISO8601 = ISO8601DateFormatter()
}

struct WidgetLocation: Codable, Equatable {
    let label: String
    let latitude: Double
    let longitude: Double
}

struct SavedLocation: Codable, Equatable {
    let label: String
    let latitude: Double
    let longitude: Double
    let timezone: String
    let source: String
    let postalCode: String?

    func validate() throws {
        guard !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ModelValidationError.emptyLocation
        }
        guard (-90 ... 90).contains(latitude) else {
            throw ModelValidationError.invalidLatitude
        }
        guard (-180 ... 180).contains(longitude) else {
            throw ModelValidationError.invalidLongitude
        }
        guard TimeZone(identifier: timezone) != nil else {
            throw ModelValidationError.invalidTimeZone(timezone)
        }
        guard ["default", "gps", "postal", "map", "coordinates"].contains(source) else {
            throw ModelValidationError.invalidLocationSource(source)
        }
    }
}

struct PlatformSettings: Codable, Equatable {
    let location: SavedLocation
}

struct PlatformStateEnvelope: Codable, Equatable {
    let schemaVersion: Int
    let updatedAt: Date
    let settings: PlatformSettings
    let snapshot: ClockSnapshot
    let snapshots: [ClockSnapshot]

    private enum CodingKeys: String, CodingKey {
        case schemaVersion
        case updatedAt
        case settings
        case snapshot
        case snapshots
    }

    init(
        schemaVersion: Int,
        updatedAt: Date,
        settings: PlatformSettings,
        snapshot: ClockSnapshot,
        snapshots: [ClockSnapshot]
    ) {
        self.schemaVersion = schemaVersion
        self.updatedAt = updatedAt
        self.settings = settings
        self.snapshot = snapshot
        self.snapshots = snapshots
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try container.decode(Int.self, forKey: .schemaVersion)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
        settings = try container.decode(PlatformSettings.self, forKey: .settings)
        snapshot = try container.decode(ClockSnapshot.self, forKey: .snapshot)
        // Version 1 originally carried only `snapshot`. Keep existing App Group
        // data readable while all newly encoded envelopes include the queue.
        snapshots = try container.decodeIfPresent(
            [ClockSnapshot].self,
            forKey: .snapshots
        ) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(schemaVersion, forKey: .schemaVersion)
        try container.encode(updatedAt, forKey: .updatedAt)
        try container.encode(settings, forKey: .settings)
        try container.encode(snapshot, forKey: .snapshot)
        try container.encode(snapshots, forKey: .snapshots)
    }

    func validate() throws {
        guard schemaVersion == 1 else {
            throw ModelValidationError.unsupportedVersion(schemaVersion)
        }
        try settings.location.validate()
        try snapshot.validate()
        guard snapshots.count <= 32 else {
            throw ModelValidationError.invalidSnapshotQueue
        }
        try snapshots.forEach { try $0.validate() }

        guard stateLocationMatches(snapshot),
              snapshots.allSatisfy({ stateLocationMatches($0) })
        else {
            throw ModelValidationError.inconsistentEnvelope
        }

        let dateKeys = snapshots.map(\.dateKey)
        guard Set(dateKeys).count == dateKeys.count,
              dateKeys == dateKeys.sorted()
        else {
            throw ModelValidationError.invalidSnapshotQueue
        }
    }

    private func stateLocationMatches(_ candidate: ClockSnapshot) -> Bool {
        settings.location.latitude == candidate.location.latitude
            && settings.location.longitude == candidate.location.longitude
            && settings.location.timezone == candidate.timezone
            && settings.location.label == candidate.location.label
    }
}

struct MinuteRange: Codable, Equatable, Identifiable {
    var id: String { "\(startMinute)-\(endMinute)" }
    let startMinute: Double
    let endMinute: Double

    func validate() throws {
        guard startMinute.isFinite, endMinute.isFinite,
              (0 ... 1_440).contains(startMinute),
              (0 ... 2_880).contains(endMinute),
              endMinute >= startMinute
        else {
            throw ModelValidationError.invalidMinuteRange
        }
    }
}

enum ClockArcKind: String, Codable, CaseIterable {
    case astronomical
    case nautical
    case civil
    case daylight
    case moon
}

struct ClockSnapshotSize: Codable, Equatable {
    let width: Double
    let height: Double
    let density: Double?
}

struct ClockGeometry: Codable, Equatable {
    let viewBox: Double
    let center: Double
    let outerRadius: Double
    let sunRadius: Double
    let moonRadius: Double
    let hourLabelRadius: Double
    let handStartRadius: Double
    let handEndRadius: Double
}

struct ClockPalette: Codable, Equatable {
    let background: String
    let face: String
    let track: String
    let text: String
    let mutedText: String
    let currentHand: String
}

struct ClockHourLabel: Codable, Equatable, Identifiable {
    var id: Int { hour }
    let hour: Int
    let label: String
    let minute: Double
}

struct ClockArc: Codable, Equatable, Identifiable {
    var id: String { kind.rawValue }
    let kind: ClockArcKind
    let label: String
    let detail: String
    let color: String
    let radius: Double
    let strokeWidth: Double
    let ranges: [MinuteRange]
}

enum ClockEventKind: String, Codable {
    case astronomicalDawn = "astronomical-dawn"
    case nauticalDawn = "nautical-dawn"
    case civilDawn = "civil-dawn"
    case sunrise
    case solarNoon = "solar-noon"
    case sunset
    case civilDusk = "civil-dusk"
    case nauticalDusk = "nautical-dusk"
    case astronomicalDusk = "astronomical-dusk"
    case moonrise
    case lunarNoon = "lunar-noon"
    case moonset
}

enum ClockBody: String, Codable {
    case sun
    case moon
    case twilight
}

enum ClockMarkerKind: String, Codable {
    case rising
    case setting
    case peak
}

struct ClockEvent: Codable, Equatable, Identifiable {
    var id: String { "\(kind.rawValue)-\(time)" }
    let kind: ClockEventKind
    let body: ClockBody
    let marker: ClockMarkerKind
    let label: String
    let time: Date
    let timeLabel: String
    let minute: Double
    let radius: Double
    let visibleOnDial: Bool
}

struct NextClockEvent: Codable, Equatable {
    let kind: String
    let time: Date
    let timeLabel: String
    let relativeLabel: String
}

struct MoonState: Codable, Equatable {
    let illumination: Double
    let phaseAngle: Double
    let phaseName: String
    let markerMinute: Double
}

/// Exact Codable counterpart to `src/lib/clock-snapshot.ts`.
///
/// Native renderers consume this model and never redo astronomy.
struct ClockSnapshot: Codable, Equatable {
    let schemaVersion: Int
    let calculatedAt: Date
    let expiresAt: Date
    let dateKey: String
    let timezone: String
    let location: WidgetLocation
    let size: ClockSnapshotSize
    let geometry: ClockGeometry
    let palette: ClockPalette
    let hourLabels: [ClockHourLabel]
    let arcs: [ClockArc]
    let events: [ClockEvent]
    let referenceMinute: Double
    let currentTimeLabel: String
    let nextSolarEvent: NextClockEvent?
    let moon: MoonState
    let accessibilityText: String

    func validate() throws {
        guard schemaVersion == 1 else {
            throw ModelValidationError.unsupportedVersion(schemaVersion)
        }
        guard TimeZone(identifier: timezone) != nil else {
            throw ModelValidationError.invalidTimeZone(timezone)
        }
        guard expiresAt > calculatedAt else {
            throw ModelValidationError.invalidExpiry
        }
        guard !dateKey.isEmpty, !accessibilityText.isEmpty else {
            throw ModelValidationError.missingDisplayText
        }
        guard
            !location.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            (-90 ... 90).contains(location.latitude),
            (-180 ... 180).contains(location.longitude)
        else {
            throw ModelValidationError.invalidSnapshotLocation
        }
        guard size.width > 0, size.height > 0,
              geometry.viewBox > 0, geometry.outerRadius > 0 else {
            throw ModelValidationError.invalidGeometry
        }
        guard (0 ... 1).contains(moon.illumination),
              moon.phaseAngle.isFinite,
              (0 ... 1_440).contains(moon.markerMinute) else {
            throw ModelValidationError.invalidMoon
        }
        try arcs.flatMap(\.ranges).forEach { try $0.validate() }
        guard events.allSatisfy({
            $0.minute.isFinite && (0 ... 1_440).contains($0.minute) && $0.radius >= 0
        }) else {
            throw ModelValidationError.invalidEventMinute
        }
    }

    static func placeholder(at date: Date = Date()) -> ClockSnapshot {
        ClockSnapshot(
            schemaVersion: 1,
            calculatedAt: date,
            expiresAt: date.addingTimeInterval(30 * 60),
            dateKey: "—",
            timezone: TimeZone.current.identifier,
            location: WidgetLocation(
                label: "Open DayMan to choose a location",
                latitude: 0,
                longitude: 0
            ),
            size: ClockSnapshotSize(width: 420, height: 420, density: 1),
            geometry: ClockGeometry(
                viewBox: 420,
                center: 210,
                outerRadius: 190,
                sunRadius: 138,
                moonRadius: 112,
                hourLabelRadius: 170,
                handStartRadius: 64,
                handEndRadius: 181
            ),
            palette: ClockPalette(
                background: "#0c1424",
                face: "#111b2e",
                track: "#222a39",
                text: "#f2f7fc",
                mutedText: "#b8cbe0",
                currentHand: "#f2f7fc"
            ),
            hourLabels: stride(from: 0, to: 24, by: 3).map {
                ClockHourLabel(
                    hour: $0,
                    label: String(format: "%02d", $0),
                    minute: Double($0 * 60)
                )
            },
            arcs: [
                ClockArc(
                    kind: .astronomical,
                    label: "Astronomical twilight",
                    detail: "Sun 12–18° below the horizon",
                    color: "#2d405d",
                    radius: 138,
                    strokeWidth: 15,
                    ranges: [MinuteRange(startMinute: 300, endMinute: 1_260)]
                ),
                ClockArc(
                    kind: .nautical,
                    label: "Nautical twilight",
                    detail: "Sun 6–12° below the horizon",
                    color: "#435e7a",
                    radius: 138,
                    strokeWidth: 15,
                    ranges: [MinuteRange(startMinute: 330, endMinute: 1_230)]
                ),
                ClockArc(
                    kind: .civil,
                    label: "Civil twilight",
                    detail: "Sun 0–6° below the horizon",
                    color: "#718ba3",
                    radius: 138,
                    strokeWidth: 15,
                    ranges: [MinuteRange(startMinute: 360, endMinute: 1_200)]
                ),
                ClockArc(
                    kind: .daylight,
                    label: "Daylight",
                    detail: "Sun above the horizon",
                    color: "#ffb552",
                    radius: 138,
                    strokeWidth: 15,
                    ranges: [MinuteRange(startMinute: 390, endMinute: 1_170)]
                ),
                ClockArc(
                    kind: .moon,
                    label: "Moon above horizon",
                    detail: "Moon above the geometric horizon",
                    color: "#d9e5ea",
                    radius: 112,
                    strokeWidth: 10,
                    ranges: [
                        MinuteRange(startMinute: 0, endMinute: 320),
                        MinuteRange(startMinute: 1_100, endMinute: 1_440)
                    ]
                )
            ],
            events: [
                ClockEvent(
                    kind: .solarNoon,
                    body: .sun,
                    marker: .peak,
                    label: "Solar noon",
                    time: date,
                    timeLabel: "12:54",
                    minute: 774,
                    radius: 138,
                    visibleOnDial: true
                )
            ],
            referenceMinute: 0,
            currentTimeLabel: "--:--",
            nextSolarEvent: nil,
            moon: MoonState(
                illumination: 0.5,
                phaseAngle: 90,
                phaseName: "Moon",
                markerMinute: 0
            ),
            accessibilityText: "Open DayMan to configure the clock widget."
        )
    }
}

enum ModelValidationError: LocalizedError {
    case unsupportedVersion(Int)
    case emptyLocation
    case invalidLatitude
    case invalidLongitude
    case invalidTimeZone(String)
    case invalidLocationSource(String)
    case invalidMinuteRange
    case invalidEventMinute
    case invalidExpiry
    case invalidMoon
    case invalidGeometry
    case missingDisplayText
    case inconsistentEnvelope
    case invalidSnapshotLocation
    case invalidSnapshotQueue

    var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version): "Unsupported model version \(version)."
        case .emptyLocation: "The location label cannot be empty."
        case .invalidLatitude: "Latitude must be between -90 and 90."
        case .invalidLongitude: "Longitude must be between -180 and 180."
        case .invalidTimeZone(let value): "\(value) is not an IANA timezone."
        case .invalidLocationSource(let value): "\(value) is not a supported location source."
        case .invalidMinuteRange: "An arc contains an invalid minute range."
        case .invalidEventMinute: "An event must be between 00:00 and 24:00."
        case .invalidExpiry: "The snapshot expiry must be after its calculation time."
        case .invalidMoon: "The Moon state is invalid."
        case .invalidGeometry: "The dial geometry is invalid."
        case .missingDisplayText: "The snapshot is missing display text."
        case .inconsistentEnvelope:
            "The saved location and clock snapshot describe different locations."
        case .invalidSnapshotLocation: "The snapshot contains an invalid location."
        case .invalidSnapshotQueue:
            "The snapshot queue must contain no more than 32 unique, ordered local dates."
        }
    }
}
