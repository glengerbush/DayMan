package com.glengerbush.dayman.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import androidx.compose.runtime.Composable
import androidx.glance.GlanceId
import androidx.glance.GlanceModifier
import androidx.glance.Image
import androidx.glance.ImageProvider
import androidx.glance.action.clickable
import androidx.glance.action.actionStartActivity
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.provideContent
import androidx.glance.layout.Box
import androidx.glance.layout.ContentScale
import androidx.glance.layout.fillMaxSize
import com.glengerbush.dayman.MainActivity
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.time.Instant

class DayManWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val renderedAt = Instant.now()
        val snapshot = WidgetStateRepository(context).load(renderedAt)
        val moonTexture = withContext(Dispatchers.IO) {
            runCatching {
                context.assets.open("public/moon-nearside.webp").use(BitmapFactory::decodeStream)
            }.getOrNull()
        }
        val bitmap = withContext(Dispatchers.Default) {
            DialRenderer.render(
                snapshot,
                moonTexture = moonTexture,
                instant = renderedAt,
            )
        }
        provideContent {
            WidgetImage(
                bitmap = bitmap,
                description = snapshot?.accessibilityText
                    ?: "DayMan dial. Tap to open DayMan and choose a location.",
            )
        }
    }
}

@Composable
private fun WidgetImage(bitmap: Bitmap, description: String) {
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .clickable(actionStartActivity<MainActivity>()),
    ) {
        Image(
            provider = ImageProvider(bitmap),
            contentDescription = description,
            modifier = GlanceModifier.fillMaxSize(),
            contentScale = ContentScale.Fit,
        )
    }
}

class DayManWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = DayManWidget()

    override fun onEnabled(context: Context) {
        super.onEnabled(context)
        WidgetRefreshScheduler.ensureScheduled(context)
        WidgetRefreshScheduler.refreshNow(context)
    }

    override fun onDisabled(context: Context) {
        super.onDisabled(context)
        WidgetRefreshScheduler.cancelScheduled(context)
    }
}
