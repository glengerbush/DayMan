package com.glengerbush.dayman.widget

import android.content.Context
import java.time.Instant

class WidgetStateRepository(context: Context) {
    private val preferences = context.applicationContext.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun saveEnvelope(rawEnvelope: String) {
        preferences.edit()
            .putString(KEY_ENVELOPE, rawEnvelope)
            .putLong(KEY_SAVED_AT, System.currentTimeMillis())
            .apply()
    }

    fun loadEnvelopeRaw(): String? = preferences.getString(KEY_ENVELOPE, null)

    fun load(at: Instant = Instant.now()): ClockSnapshot? =
        loadEnvelope()?.snapshotFor(at)

    fun loadTimezone(): String? = loadEnvelope()?.timezone

    private fun loadEnvelope(): PlatformStateEnvelope? = loadEnvelopeRaw()?.let {
        runCatching { PlatformStateCodec.decode(it) }.getOrNull()
    }

    companion object {
        const val PREFERENCES_NAME = "dayman_widget_state_v1"
        const val KEY_ENVELOPE = "platform_state_envelope"
        const val KEY_SAVED_AT = "saved_at_epoch_ms"
    }
}
