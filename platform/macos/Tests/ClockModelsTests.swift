import XCTest
@testable import DayMan

final class ClockModelsTests: XCTestCase {
    func testEverySharedReferenceSnapshotDecodesAndValidates() throws {
        let fixtureURLs = try XCTUnwrap(
            Bundle(for: Self.self).urls(
                forResourcesWithExtension: "json",
                subdirectory: nil
            )
        )
        XCTAssertGreaterThanOrEqual(fixtureURLs.count, 7)

        for url in fixtureURLs {
            let snapshot = try DayManJSON.decoder.decode(
                ClockSnapshot.self,
                from: Data(contentsOf: url)
            )
            XCTAssertEqual(snapshot.schemaVersion, 1, url.lastPathComponent)
            XCTAssertNoThrow(try snapshot.validate(), url.lastPathComponent)
        }
    }

    func testEnvelopeRoundTripsThroughInjectedStore() throws {
        let snapshot = try decodeFixture(
            "new-york-dst-spring",
            as: ClockSnapshot.self
        )
        let location = SavedLocation(
            label: snapshot.location.label,
            latitude: snapshot.location.latitude,
            longitude: snapshot.location.longitude,
            timezone: snapshot.timezone,
            source: "map",
            postalCode: nil
        )
        let state = PlatformStateEnvelope(
            schemaVersion: 1,
            updatedAt: snapshot.calculatedAt,
            settings: PlatformSettings(location: location),
            snapshot: snapshot,
            snapshots: [snapshot]
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = AppGroupStore(baseURL: directory)

        try state.validate()
        try store.save(state)

        XCTAssertEqual(try store.loadState(), state)
        XCTAssertEqual(try store.loadSnapshot(), snapshot)
    }

    func testStoreSelectsSnapshotBySavedTimeZoneAndFallsBack() throws {
        let current = try decodeFixture(
            "new-york-dst-spring",
            as: ClockSnapshot.self
        )
        let next = try shiftedSnapshot(
            fixture: "new-york-dst-spring",
            dateKey: "2026-03-09",
            calculatedAt: "2026-03-09T12:00:00.000Z",
            expiresAt: "2026-03-10T04:00:00.000Z"
        )
        let state = PlatformStateEnvelope(
            schemaVersion: 1,
            updatedAt: current.calculatedAt,
            settings: PlatformSettings(
                location: SavedLocation(
                    label: "New York",
                    latitude: 40.7128,
                    longitude: -74.006,
                    timezone: "America/New_York",
                    source: "map",
                    postalCode: nil
                )
            ),
            snapshot: current,
            snapshots: [current, next]
        )
        let store = AppGroupStore(
            baseURL: FileManager.default.temporaryDirectory
        )

        let afterLocalMidnight = try isoDate("2026-03-09T05:05:00.000Z")
        XCTAssertEqual(
            store.snapshot(in: state, at: afterLocalMidnight)?.dateKey,
            "2026-03-09"
        )

        let outsideQueue = try isoDate("2026-04-15T16:00:00.000Z")
        XCTAssertNil(
            store.snapshot(in: state, at: outsideQueue),
            "A non-empty queue must never render stale geometry for a missing date."
        )
    }

    func testEnvelopeWithoutQueueMigratesToFallbackSnapshot() throws {
        let snapshot = try decodeFixture(
            "new-york-dst-spring",
            as: ClockSnapshot.self
        )
        let oldEnvelope: [String: Any] = [
            "schemaVersion": 1,
            "updatedAt": "2026-03-08T12:00:00.000Z",
            "settings": [
                "location": [
                    "label": "New York",
                    "latitude": 40.7128,
                    "longitude": -74.006,
                    "timezone": "America/New_York",
                    "source": "map"
                ]
            ],
            "snapshot": try JSONSerialization.jsonObject(
                with: DayManJSON.encoder.encode(snapshot)
            )
        ]
        let decoded = try DayManJSON.decoder.decode(
            PlatformStateEnvelope.self,
            from: JSONSerialization.data(withJSONObject: oldEnvelope)
        )

        XCTAssertTrue(decoded.snapshots.isEmpty)
        XCTAssertNoThrow(try decoded.validate())

        let store = AppGroupStore(
            baseURL: FileManager.default.temporaryDirectory
        )
        let sameLocalDate = try isoDate("2026-03-08T17:00:00.000Z")
        XCTAssertEqual(
            store.snapshot(in: decoded, at: sameLocalDate),
            snapshot,
            "A legacy envelope may use its singular snapshot on the matching local date."
        )
        let nextLocalDate = try isoDate("2026-03-09T17:00:00.000Z")
        XCTAssertNil(
            store.snapshot(in: decoded, at: nextLocalDate),
            "A legacy singular snapshot must not survive local midnight."
        )
    }

    func testSettingsRejectAnUnknownTimeZone() {
        let location = SavedLocation(
            label: "Somewhere",
            latitude: 1,
            longitude: 1,
            timezone: "Mars/Olympus_Mons",
            source: "coordinates",
            postalCode: nil
        )

        XCTAssertThrowsError(try location.validate())
    }

    private func decodeFixture<Value: Decodable>(
        _ name: String,
        as type: Value.Type
    ) throws -> Value {
        let bundle = Bundle(for: Self.self)
        let url = try XCTUnwrap(bundle.url(forResource: name, withExtension: "json"))
        return try DayManJSON.decoder.decode(Value.self, from: Data(contentsOf: url))
    }

    private func shiftedSnapshot(
        fixture: String,
        dateKey: String,
        calculatedAt: String,
        expiresAt: String
    ) throws -> ClockSnapshot {
        let originalURL = try XCTUnwrap(
            Bundle(for: Self.self).url(forResource: fixture, withExtension: "json")
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: originalURL))
                as? [String: Any]
        )
        object["dateKey"] = dateKey
        object["calculatedAt"] = calculatedAt
        object["expiresAt"] = expiresAt
        return try DayManJSON.decoder.decode(
            ClockSnapshot.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
    }

    private func isoDate(_ value: String) throws -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return try XCTUnwrap(formatter.date(from: value))
    }
}
