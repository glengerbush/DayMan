package com.glengerbush.dayman.widget

import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.CoroutineWorker
import androidx.work.WorkerParameters

class WidgetRefreshWorker(
    appContext: Context,
    parameters: WorkerParameters,
) : CoroutineWorker(appContext, parameters) {
    override suspend fun doWork(): Result {
        DayManWidget().updateAll(applicationContext)
        WidgetRefreshScheduler.scheduleNextMidnight(applicationContext)
        return Result.success()
    }
}
