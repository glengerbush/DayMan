package com.glengerbush.dayman

import android.os.Bundle
import com.getcapacitor.BridgeActivity
import com.glengerbush.dayman.bridge.DayManJavascriptBridge
import com.glengerbush.dayman.bridge.DayManWidgetPlugin

class MainActivity : BridgeActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        registerPlugin(DayManWidgetPlugin::class.java)
        super.onCreate(savedInstanceState)
        bridge.webView.addJavascriptInterface(
            DayManJavascriptBridge(applicationContext),
            "DayManAndroid",
        )
    }
}
