package com.glengerbush.dayman.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
import org.junit.Test
import java.time.Instant

class ClockSnapshotCodecTest {
    @Test
    fun decodesSharedDstFixture() {
        val snapshot = ClockSnapshotCodec.decode(resource("new-york-dst-spring.json"))

        assertEquals(1, snapshot.schemaVersion)
        assertEquals("America/New_York", snapshot.timezone)
        assertEquals("New York", snapshot.locationLabel)
        assertEquals(438.866, snapshot.ranges("daylight").single().startMinute, 0.001)
        assertEquals(0.7628, snapshot.moonIllumination, 0.001)
    }

    @Test
    fun decodesSharedPolarFixtures() {
        val day = ClockSnapshotCodec.decode(resource("tromso-polar-day.json"))
        val night = ClockSnapshotCodec.decode(resource("tromso-polar-night.json"))

        assertEquals(MinuteRange(0.0, 1440.0), day.ranges("daylight").single())
        assertEquals(emptyList<MinuteRange>(), night.ranges("daylight"))
    }

    @Test
    fun decodesPlatformEnvelope() {
        val fallback = resource("new-york-dst-spring.json")
        val queued = resource("new-york-dst-fall.json")
        val envelope = """
            {
              "schemaVersion": 1,
              "updatedAt": "2026-11-01T17:00:00.000Z",
              "settings": {
                "location": {
                  "label": "New York",
                  "latitude": 40.7128,
                  "longitude": -74.006,
                  "timezone": "America/New_York"
                }
              },
              "snapshot": $fallback,
              "snapshots": [$fallback, $queued]
            }
        """.trimIndent()

        val decoded = PlatformStateCodec.decode(envelope)
        assertEquals(2, decoded.snapshots.size)
        assertEquals(
            "2026-11-01",
            decoded.snapshotFor(Instant.parse("2026-11-01T17:00:00Z"))?.dateKey,
        )
        assertNull(decoded.snapshotFor(Instant.parse("2027-01-01T17:00:00Z")))
    }

    @Test
    fun legacyEnvelopeWithoutQueueUsesFallbackSnapshot() {
        val fallback = resource("new-york-dst-spring.json")
        val envelope = """
            {
              "schemaVersion": 1,
              "updatedAt": "2026-03-08T12:00:00.000Z",
              "settings": {
                "location": {
                  "label": "New York",
                  "latitude": 40.7128,
                  "longitude": -74.006,
                  "timezone": "America/New_York"
                }
              },
              "snapshot": $fallback
            }
        """.trimIndent()

        val decoded = PlatformStateCodec.decode(envelope)
        assertEquals(emptyList<ClockSnapshot>(), decoded.snapshots)
        assertEquals(
            decoded.snapshot,
            decoded.snapshotFor(Instant.parse("2026-03-08T17:00:00Z")),
        )
        assertNull(decoded.snapshotFor(Instant.parse("2026-03-09T17:00:00Z")))
    }

    @Test
    fun rejectsUnknownVersions() {
        val invalid = resource("new-york-dst-spring.json")
            .replace("\"schemaVersion\": 1", "\"schemaVersion\": 2")
        assertThrows(IllegalArgumentException::class.java) {
            ClockSnapshotCodec.decode(invalid)
        }
    }

    private fun resource(name: String): String =
        requireNotNull(javaClass.classLoader?.getResource(name)) { "Missing fixture $name" }
            .readText()
}
