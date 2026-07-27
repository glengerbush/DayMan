package com.glengerbush.dayman.bridge

import android.content.Context
import android.util.Log
import android.webkit.JavascriptInterface
import com.glengerbush.dayman.widget.PlatformStateCodec
import com.glengerbush.dayman.widget.WidgetRefreshScheduler
import com.glengerbush.dayman.widget.WidgetStateRepository

/**
 * Narrow bridge expected by src/lib/platform-bridge.ts.
 *
 * DayMan only loads its bundled Capacitor origin in this WebView. If external
 * navigation is added later, it must remain outside this WebView because
 * addJavascriptInterface is available to every document loaded into it.
 */
class DayManJavascriptBridge(context: Context) {
    private val appContext = context.applicationContext

    @JavascriptInterface
    fun saveState(payload: String) {
        try {
            PlatformStateCodec.decode(payload)
            WidgetStateRepository(appContext).saveEnvelope(payload)
            WidgetRefreshScheduler.refreshNow(appContext)
            WidgetRefreshScheduler.scheduleNextMidnight(appContext)
        } catch (error: IllegalArgumentException) {
            Log.e(TAG, "Rejected invalid DayMan platform state", error)
        }
    }

    companion object {
        private const val TAG = "DayManWidgetBridge"
    }
}
