package com.glengerbush.dayman.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import androidx.glance.appwidget.updateAll
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import java.time.Duration
import java.time.ZonedDateTime
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

object WidgetRefreshScheduler {
    private const val PERIODIC_WORK = "dayman-widget-periodic-v1"
    private const val IMMEDIATE_WORK = "dayman-widget-immediate-v1"
    private const val MIDNIGHT_WORK = "dayman-widget-midnight-v1"
    private val immediateScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    fun ensureScheduled(context: Context) {
        if (!hasWidgets(context)) return
        val request = PeriodicWorkRequestBuilder<WidgetRefreshWorker>(30, TimeUnit.MINUTES)
            .addTag(PERIODIC_WORK)
            .build()
        WorkManager.getInstance(context).enqueueUniquePeriodicWork(
            PERIODIC_WORK,
            ExistingPeriodicWorkPolicy.UPDATE,
            request,
        )
        scheduleNextMidnight(context)
    }

    fun refreshNow(context: Context) {
        if (!hasWidgets(context)) return
        val appContext = context.applicationContext
        immediateScope.launch {
            runCatching {
                DayManWidget().updateAll(appContext)
            }
        }
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .addTag(IMMEDIATE_WORK)
            .build()
        WorkManager.getInstance(appContext).enqueueUniqueWork(
            IMMEDIATE_WORK,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun scheduleNextMidnight(context: Context) {
        if (!hasWidgets(context)) return
        val zone = WidgetStateRepository(context)
            .loadTimezone()
            ?.let { runCatching { java.time.ZoneId.of(it) }.getOrNull() }
            ?: java.time.ZoneId.systemDefault()
        val now = ZonedDateTime.now(zone)
        val next = now.toLocalDate().plusDays(1).atStartOfDay(zone).plusMinutes(2)
        val delay = Duration.between(now, next).toMillis().coerceAtLeast(0L)
        val request = OneTimeWorkRequestBuilder<WidgetRefreshWorker>()
            .setInitialDelay(delay, TimeUnit.MILLISECONDS)
            .addTag(MIDNIGHT_WORK)
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(
            MIDNIGHT_WORK,
            ExistingWorkPolicy.REPLACE,
            request,
        )
    }

    fun cancelScheduled(context: Context) {
        WorkManager.getInstance(context).apply {
            cancelUniqueWork(PERIODIC_WORK)
            cancelUniqueWork(IMMEDIATE_WORK)
            cancelUniqueWork(MIDNIGHT_WORK)
        }
    }

    private fun hasWidgets(context: Context): Boolean =
        AppWidgetManager.getInstance(context)
            .getAppWidgetIds(ComponentName(context, DayManWidgetReceiver::class.java))
            .isNotEmpty()
}
