import Foundation
import WebKit
import WidgetKit

/// The only JavaScript-to-native entry point exposed by the macOS host.
///
/// JavaScript posts the shared envelope to
/// `window.webkit.messageHandlers.daymanState`.
/// Arbitrary method invocation, filesystem paths, URLs, and script callbacks are
/// deliberately not accepted.
final class NativeBridge {
    static let channelName = "daymanState"

    private let store: AppGroupStore
    private let decoder: JSONDecoder
    private var lastTimelineReloadAt: Date?

    init(store: AppGroupStore = AppGroupStore()) {
        self.store = store
        self.decoder = DayManJSON.decoder
    }

    func receive(_ body: Any) throws {
        guard JSONSerialization.isValidJSONObject(body) else {
            throw NativeBridgeError.invalidJSON
        }

        let data = try JSONSerialization.data(withJSONObject: body)
        let envelope = try decoder.decode(PlatformStateEnvelope.self, from: data)
        try envelope.validate()
        let previous = try? store.loadState()
        try store.save(envelope)

        if shouldReloadWidget(previous: previous, next: envelope) {
            lastTimelineReloadAt = Date()
            WidgetCenter.shared.reloadTimelines(ofKind: DayManWidgetConstants.kind)
        }
    }

    private func shouldReloadWidget(
        previous: PlatformStateEnvelope?,
        next: PlatformStateEnvelope
    ) -> Bool {
        guard let previous else { return true }
        if previous.settings.location != next.settings.location { return true }
        if previous.snapshot.dateKey != next.snapshot.dateKey { return true }
        if previous.snapshot.schemaVersion != next.snapshot.schemaVersion { return true }
        if previous.snapshots.map(\.dateKey) != next.snapshots.map(\.dateKey) { return true }
        guard let lastTimelineReloadAt else { return true }
        return Date().timeIntervalSince(lastTimelineReloadAt) >= 25 * 60
    }
}

enum NativeBridgeError: LocalizedError {
    case invalidJSON

    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            "The native bridge accepts JSON objects only."
        }
    }
}
