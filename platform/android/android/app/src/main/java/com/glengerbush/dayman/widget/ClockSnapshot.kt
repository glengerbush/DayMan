package com.glengerbush.dayman.widget

import org.json.JSONArray
import org.json.JSONObject
import java.time.Instant
import java.time.ZoneId

data class MinuteRange(val startMinute: Double, val endMinute: Double)

data class ClockArc(
    val kind: String,
    val color: String,
    val ranges: List<MinuteRange>,
)

data class ClockEvent(
    val kind: String,
    val minute: Double,
    val timeLabel: String,
    val visibleOnDial: Boolean,
)

data class NextSolarEvent(
    val kind: String,
    val timeLabel: String,
    val relativeLabel: String,
)

data class ClockSnapshot(
    val schemaVersion: Int,
    val calculatedAt: String,
    val expiresAt: String,
    val dateKey: String,
    val timezone: String,
    val locationLabel: String,
    val arcs: List<ClockArc>,
    val events: List<ClockEvent>,
    val nextSolarEvent: NextSolarEvent?,
    val moonIllumination: Double,
    val moonPhaseAngle: Double,
    val moonPhaseName: String,
    val accessibilityText: String,
) {
    fun ranges(kind: String): List<MinuteRange> =
        arcs.firstOrNull { it.kind == kind }?.ranges.orEmpty()

    fun event(kind: String): ClockEvent? = events.firstOrNull { it.kind == kind }

    fun currentMinuteAt(instant: Instant): Double {
        val localTime = instant.atZone(ZoneId.of(timezone)).toLocalTime()
        return localTime.hour * 60.0 +
            localTime.minute +
            localTime.second / 60.0
    }
}

data class PlatformStateEnvelope(
    val schemaVersion: Int,
    val updatedAt: String,
    val timezone: String,
    val snapshot: ClockSnapshot,
    val snapshots: List<ClockSnapshot>,
) {
    fun snapshotFor(instant: Instant = Instant.now()): ClockSnapshot? {
        val zone = ZoneId.of(timezone)
        val currentDateKey = instant.atZone(zone).toLocalDate().toString()
        val queued = snapshots.firstOrNull { it.dateKey == currentDateKey }
        if (queued != null) return queued
        if (snapshots.isNotEmpty()) return null
        return snapshot.takeIf { it.dateKey == currentDateKey }
    }
}

object ClockSnapshotCodec {
    const val SUPPORTED_VERSION = 1

    fun decode(raw: String): ClockSnapshot {
        val root = try {
            JSONObject(raw)
        } catch (error: Exception) {
            throw IllegalArgumentException("ClockSnapshot must be valid JSON", error)
        }
        return decode(root)
    }

    fun decode(root: JSONObject): ClockSnapshot {
        val version = root.optInt("schemaVersion", -1)
        require(version == SUPPORTED_VERSION) {
            "Unsupported ClockSnapshot schemaVersion $version; expected $SUPPORTED_VERSION"
        }

        val timezone = root.requiredString("timezone")
        val date = root.requiredString("dateKey")
        val location = root.optJSONObject("location") ?: JSONObject()
        val moon = root.optJSONObject("moon") ?: JSONObject()
        val arcs = root.optJSONArray("arcs").objects().mapNotNull { arc ->
            val kind = arc.optString("kind")
            if (kind.isBlank()) return@mapNotNull null
            ClockArc(
                kind = kind,
                color = arc.optString("color", defaultArcColor(kind)),
                ranges = arc.optJSONArray("ranges").ranges(),
            )
        }
        val events = root.optJSONArray("events").objects().mapNotNull { event ->
            val kind = event.optString("kind")
            val minute = event.optDouble("minute", Double.NaN)
            if (kind.isBlank() || !minute.isFinite() || minute !in 0.0..1440.0) {
                return@mapNotNull null
            }
            ClockEvent(
                kind = kind,
                minute = minute,
                timeLabel = event.optString("timeLabel", formatMinute(minute)),
                visibleOnDial = event.optBoolean("visibleOnDial", false),
            )
        }
        val next = root.optJSONObject("nextSolarEvent")?.let {
            NextSolarEvent(
                kind = it.optString("kind"),
                timeLabel = it.optString("timeLabel"),
                relativeLabel = it.optString("relativeLabel"),
            )
        }

        return ClockSnapshot(
            schemaVersion = version,
            calculatedAt = root.optString("calculatedAt"),
            expiresAt = root.optString("expiresAt"),
            dateKey = date,
            timezone = timezone,
            locationLabel = location.optString("label", "Saved location"),
            arcs = arcs,
            events = events,
            nextSolarEvent = next,
            moonIllumination = moon.optDouble("illumination", 0.5).coerceIn(0.0, 1.0),
            moonPhaseAngle = moon.optDouble("phaseAngle", 180.0)
                .let { ((it % 360.0) + 360.0) % 360.0 },
            moonPhaseName = moon.optString("phaseName", "Moon"),
            accessibilityText = root.optString(
                "accessibilityText",
                "DayMan dial for ${location.optString("label", "saved location")} on $date",
            ),
        )
    }

    private fun JSONObject.requiredString(key: String): String {
        val value = optString(key)
        require(value.isNotBlank()) { "ClockSnapshot.$key is required" }
        return value
    }

    private fun JSONArray?.objects(): List<JSONObject> {
        if (this == null) return emptyList()
        return buildList {
            for (index in 0 until length()) optJSONObject(index)?.let(::add)
        }
    }

    private fun JSONArray?.ranges(): List<MinuteRange> {
        if (this == null) return emptyList()
        return objects().mapNotNull { value ->
            val start = value.optDouble("startMinute", Double.NaN)
            val end = value.optDouble("endMinute", Double.NaN)
            if (
                start.isFinite() &&
                end.isFinite() &&
                start in 0.0..1440.0 &&
                end in 0.0..1440.0 &&
                start != end
            ) {
                MinuteRange(start, end)
            } else {
                null
            }
        }
    }

    private fun defaultArcColor(kind: String): String = when (kind) {
        "astronomical" -> "#2d405d"
        "nautical" -> "#435e7a"
        "civil" -> "#718ba3"
        "daylight" -> "#ffb552"
        "moon" -> "#d9e5ea"
        else -> "#334b68"
    }

    private fun formatMinute(minute: Double): String {
        val rounded = minute.toInt().coerceIn(0, 1439)
        return "%02d:%02d".format((rounded / 60) % 24, rounded % 60)
    }
}

object PlatformStateCodec {
    const val SUPPORTED_VERSION = 1

    fun decode(raw: String): PlatformStateEnvelope {
        val root = try {
            JSONObject(raw)
        } catch (error: Exception) {
            throw IllegalArgumentException("PlatformStateEnvelope must be valid JSON", error)
        }
        val version = root.optInt("schemaVersion", -1)
        require(version == SUPPORTED_VERSION) {
            "Unsupported PlatformStateEnvelope schemaVersion $version; expected $SUPPORTED_VERSION"
        }
        val savedLocation = root.optJSONObject("settings")?.optJSONObject("location")
        require(savedLocation != null) {
            "PlatformStateEnvelope.settings.location is required"
        }
        val snapshotObject = root.optJSONObject("snapshot")
            ?: throw IllegalArgumentException("PlatformStateEnvelope.snapshot is required")
        val fallback = ClockSnapshotCodec.decode(snapshotObject)
        val savedTimezone = savedLocation.optString("timezone", fallback.timezone)
        require(savedTimezone.isNotBlank()) {
            "PlatformStateEnvelope.settings.location.timezone is required"
        }
        require(runCatching { ZoneId.of(savedTimezone) }.isSuccess) {
            "PlatformStateEnvelope.settings.location.timezone must be a valid IANA timezone"
        }
        val snapshots = root.optJSONArray("snapshots")
            ?.let { values ->
                require(values.length() <= 32) {
                    "PlatformStateEnvelope.snapshots cannot contain more than 32 entries"
                }
                buildList {
                    for (index in 0 until values.length()) {
                        val value = values.optJSONObject(index)
                            ?: throw IllegalArgumentException(
                                "PlatformStateEnvelope.snapshots[$index] must be an object",
                            )
                        add(ClockSnapshotCodec.decode(value))
                    }
                }
            }
            .orEmpty()
        return PlatformStateEnvelope(
            schemaVersion = version,
            updatedAt = root.optString("updatedAt"),
            timezone = savedTimezone,
            snapshot = fallback,
            snapshots = snapshots,
        )
    }
}
