package com.glengerbush.dayman.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class SystemEventReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_DATE_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED,
            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_MY_PACKAGE_REPLACED,
            -> {
                WidgetRefreshScheduler.ensureScheduled(context.applicationContext)
                WidgetRefreshScheduler.refreshNow(context.applicationContext)
            }
        }
    }
}
