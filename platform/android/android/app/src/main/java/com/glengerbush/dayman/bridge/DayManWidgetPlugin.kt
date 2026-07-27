package com.glengerbush.dayman.bridge

import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import com.glengerbush.dayman.widget.PlatformStateCodec
import com.glengerbush.dayman.widget.WidgetRefreshScheduler
import com.glengerbush.dayman.widget.WidgetStateRepository

@CapacitorPlugin(name = "DayManWidget")
class DayManWidgetPlugin : Plugin() {
    @PluginMethod
    fun saveState(call: PluginCall) {
        val value = call.getObject("state")
        if (value == null) {
            call.reject("state must be a PlatformStateEnvelope JSON object")
            return
        }

        val raw = value.toString()
        try {
            PlatformStateCodec.decode(raw)
        } catch (error: IllegalArgumentException) {
            call.reject(error.message ?: "Invalid PlatformStateEnvelope")
            return
        }

        WidgetStateRepository(context).saveEnvelope(raw)
        WidgetRefreshScheduler.refreshNow(context)
        WidgetRefreshScheduler.scheduleNextMidnight(context)
        call.resolve(JSObject().put("saved", true))
    }

    @PluginMethod
    fun refreshWidget(call: PluginCall) {
        WidgetRefreshScheduler.refreshNow(context)
        call.resolve(JSObject().put("queued", true))
    }

    @PluginMethod
    fun getWidgetState(call: PluginCall) {
        val raw = WidgetStateRepository(context).loadEnvelopeRaw()
        val result = JSObject().put("configured", raw != null)
        if (raw != null) result.put("state", JSObject(raw))
        call.resolve(result)
    }
}
