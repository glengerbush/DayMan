package com.glengerbush.dayman.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.DashPathEffect
import android.graphics.Paint
import android.graphics.Path
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import java.time.Instant
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

object DialRenderer {
    private const val NIGHT = "#101A2D"
    private const val TRACK = "#334B68"
    private const val ASTRONOMICAL = "#536084"
    private const val NAUTICAL = "#75668E"
    private const val CIVIL = "#C88667"
    private const val DAYLIGHT = "#FFBD63"
    private const val MOON = "#DDE7EA"
    private const val TEXT = "#F4F0E8"
    private const val MUTED = "#93A4B8"

    fun render(
        snapshot: ClockSnapshot?,
        sizePx: Int = 720,
        moonTexture: Bitmap? = null,
        instant: Instant = Instant.now(),
    ): Bitmap {
        val bitmap = Bitmap.createBitmap(sizePx, sizePx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        val center = sizePx / 2f
        val radius = sizePx * 0.39f
        val ringWidth = sizePx * 0.047f
        val paint = Paint(Paint.ANTI_ALIAS_FLAG)

        canvas.drawColor(Color.TRANSPARENT)
        paint.color = Color.parseColor(NIGHT)
        canvas.drawRoundRect(
            RectF(0f, 0f, sizePx.toFloat(), sizePx.toFloat()),
            sizePx * 0.09f,
            sizePx * 0.09f,
            paint,
        )

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = ringWidth
        paint.strokeCap = Paint.Cap.ROUND
        paint.color = Color.parseColor(TRACK)
        canvas.drawCircle(center, center, radius, paint)
        canvas.drawCircle(center, center, radius * 0.76f, paint.apply { strokeWidth = ringWidth * 0.56f })

        if (snapshot == null) {
            drawUnconfigured(canvas, center, sizePx, paint)
            return bitmap
        }

        drawRanges(canvas, center, radius, ringWidth, snapshot.ranges("astronomical"), arcColor(snapshot, "astronomical", ASTRONOMICAL), paint)
        drawRanges(canvas, center, radius, ringWidth, snapshot.ranges("nautical"), arcColor(snapshot, "nautical", NAUTICAL), paint)
        drawRanges(canvas, center, radius, ringWidth, snapshot.ranges("civil"), arcColor(snapshot, "civil", CIVIL), paint)
        drawRanges(canvas, center, radius, ringWidth, snapshot.ranges("daylight"), arcColor(snapshot, "daylight", DAYLIGHT), paint)
        drawRanges(
            canvas,
            center,
            radius * 0.76f,
            ringWidth * 0.56f,
            snapshot.ranges("moon"),
            arcColor(snapshot, "moon", MOON),
            paint,
        )

        drawCurrentTimeHand(
            canvas,
            center,
            radius,
            snapshot.currentMinuteAt(instant),
            sizePx,
            paint,
        )
        drawHourTicksAndLabels(canvas, center, radius, sizePx, paint)
        snapshot.event("solar-noon")?.let {
            drawEventDot(canvas, center, radius, it.minute, DAYLIGHT, sizePx, paint)
        }
        snapshot.event("lunar-noon")?.let {
            drawEventDot(canvas, center, radius * 0.76f, it.minute, MOON, sizePx, paint)
        }
        drawMoon(
            canvas,
            center,
            center - sizePx * 0.07f,
            sizePx * 0.055f,
            snapshot.moonPhaseAngle,
            moonTexture,
            paint,
        )
        drawCenterText(canvas, snapshot, center, sizePx, paint)
        return bitmap
    }

    private fun drawCurrentTimeHand(
        canvas: Canvas,
        center: Float,
        radius: Float,
        minute: Double,
        size: Int,
        paint: Paint,
    ) {
        val angle = minute * 2.0 * PI / 1440.0 - PI / 2.0
        val startRadius = radius * 0.45f
        val endRadius = radius + size * 0.068f

        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        paint.strokeWidth = size * 0.006f
        paint.color = Color.parseColor(TEXT)
        paint.alpha = 230
        paint.pathEffect = DashPathEffect(
            floatArrayOf(size * 0.011f, size * 0.009f),
            0f,
        )
        canvas.drawLine(
            center + cos(angle).toFloat() * startRadius,
            center + sin(angle).toFloat() * startRadius,
            center + cos(angle).toFloat() * endRadius,
            center + sin(angle).toFloat() * endRadius,
            paint,
        )
        paint.pathEffect = null
        paint.alpha = 255
    }

    private fun drawRanges(
        canvas: Canvas,
        center: Float,
        radius: Float,
        width: Float,
        ranges: List<MinuteRange>,
        color: String,
        paint: Paint,
    ) {
        paint.style = Paint.Style.STROKE
        paint.strokeWidth = width
        paint.strokeCap = Paint.Cap.BUTT
        paint.color = Color.parseColor(color)
        val bounds = RectF(center - radius, center - radius, center + radius, center + radius)
        ranges.forEach { range ->
            val start = range.startMinute.toFloat() * 360f / 1440f - 90f
            val length = if (range.endMinute > range.startMinute) {
                range.endMinute - range.startMinute
            } else {
                1440 - range.startMinute + range.endMinute
            }
            canvas.drawArc(bounds, start, length.toFloat() * 360f / 1440f, false, paint)
        }
    }

    private fun drawHourTicksAndLabels(
        canvas: Canvas,
        center: Float,
        radius: Float,
        size: Int,
        paint: Paint,
    ) {
        paint.style = Paint.Style.STROKE
        paint.strokeCap = Paint.Cap.ROUND
        for (hour in 0 until 24) {
            val angle = hour * 2.0 * PI / 24.0 - PI / 2.0
            val outer = radius + size * 0.052f
            val inner = outer - if (hour % 6 == 0) size * 0.027f else size * 0.015f
            paint.color = Color.parseColor(if (hour % 6 == 0) TEXT else MUTED)
            paint.strokeWidth = if (hour % 6 == 0) size * 0.008f else size * 0.004f
            canvas.drawLine(
                center + cos(angle).toFloat() * inner,
                center + sin(angle).toFloat() * inner,
                center + cos(angle).toFloat() * outer,
                center + sin(angle).toFloat() * outer,
                paint,
            )
        }

        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        paint.color = Color.parseColor(MUTED)
        paint.textSize = size * 0.027f
        val labelRadius = radius + size * 0.083f
        val verticalCenter = -(paint.fontMetrics.ascent + paint.fontMetrics.descent) / 2f
        for (hour in 0 until 24 step 3) {
            val angle = hour * 2.0 * PI / 24.0 - PI / 2.0
            canvas.drawText(
                hour.toString().padStart(2, '0'),
                center + cos(angle).toFloat() * labelRadius,
                center + sin(angle).toFloat() * labelRadius + verticalCenter,
                paint,
            )
        }
    }

    private fun drawEventDot(
        canvas: Canvas,
        center: Float,
        radius: Float,
        minute: Double,
        color: String,
        size: Int,
        paint: Paint,
    ) {
        val angle = minute * 2.0 * PI / 1440.0 - PI / 2.0
        paint.style = Paint.Style.FILL
        paint.color = Color.parseColor(color)
        canvas.drawCircle(
            center + cos(angle).toFloat() * radius,
            center + sin(angle).toFloat() * radius,
            size * 0.015f,
            paint,
        )
    }

    private fun drawMoon(
        canvas: Canvas,
        x: Float,
        y: Float,
        radius: Float,
        phaseAngle: Double,
        texture: Bitmap?,
        paint: Paint,
    ) {
        paint.style = Paint.Style.FILL
        paint.color = Color.parseColor("#050B14")
        canvas.drawCircle(x, y, radius, paint)

        val phase = ((phaseAngle % 360.0) + 360.0) % 360.0
        val terminatorRadius = max(
            radius * 0.005f,
            abs(cos(phase * PI / 180.0)).toFloat() * radius,
        )
        val waxing = phase <= 180.0
        val outerSweep = if (waxing) 180f else -180f
        val terminatorSweep = if (waxing) {
            if (phase < 90.0) -180f else 180f
        } else {
            if (phase < 270.0) -180f else 180f
        }

        val litPath = Path().apply {
            moveTo(x, y - radius)
            arcTo(
                RectF(x - radius, y - radius, x + radius, y + radius),
                -90f,
                outerSweep,
            )
            arcTo(
                RectF(
                    x - terminatorRadius,
                    y - radius,
                    x + terminatorRadius,
                    y + radius,
                ),
                90f,
                terminatorSweep,
            )
            close()
        }

        canvas.save()
        canvas.clipPath(litPath)
        if (texture != null) {
            paint.colorFilter = ColorMatrixColorFilter(
                ColorMatrix().apply { setSaturation(0f) },
            )
            canvas.drawBitmap(
                texture,
                Rect(0, 0, texture.width, texture.height),
                RectF(x - radius, y - radius, x + radius, y + radius),
                paint,
            )
            paint.colorFilter = null
        } else {
            paint.color = Color.parseColor(MOON)
            canvas.drawCircle(x, y, radius, paint)
        }
        canvas.restore()

        paint.style = Paint.Style.STROKE
        paint.strokeWidth = radius * 0.055f
        paint.color = Color.parseColor("#8FA0A8")
        canvas.drawCircle(x, y, radius, paint)
        paint.style = Paint.Style.FILL
    }

    private fun drawCenterText(
        canvas: Canvas,
        snapshot: ClockSnapshot,
        center: Float,
        size: Int,
        paint: Paint,
    ) {
        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        paint.color = Color.parseColor(TEXT)
        paint.textSize = size * 0.046f
        canvas.drawText(snapshot.dateKey, center, center + size * 0.025f, paint)

        val sunrise = snapshot.event("sunrise")?.timeLabel
        val sunset = snapshot.event("sunset")?.timeLabel
        val schedule = when {
            sunrise != null && sunset != null -> "Rise $sunrise  •  Set $sunset"
            sunrise != null -> "Sunrise $sunrise"
            sunset != null -> "Sunset $sunset"
            else -> snapshot.moonPhaseName
        }
        paint.typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        paint.color = Color.parseColor(MUTED)
        paint.textSize = min(size * 0.031f, size * 0.52f / schedule.length.coerceAtLeast(1))
        canvas.drawText(schedule, center, center + size * 0.083f, paint)

        paint.textSize = size * 0.027f
        canvas.drawText(snapshot.locationLabel.take(32), center, center + size * 0.126f, paint)
    }

    private fun arcColor(snapshot: ClockSnapshot, kind: String, fallback: String): String =
        snapshot.arcs.firstOrNull { it.kind == kind }?.color ?: fallback

    private fun drawUnconfigured(canvas: Canvas, center: Float, size: Int, paint: Paint) {
        paint.style = Paint.Style.FILL
        paint.textAlign = Paint.Align.CENTER
        paint.typeface = Typeface.create("sans-serif-medium", Typeface.NORMAL)
        paint.color = Color.parseColor(TEXT)
        paint.textSize = size * 0.05f
        canvas.drawText("Open DayMan", center, center - size * 0.01f, paint)
        paint.typeface = Typeface.DEFAULT
        paint.color = Color.parseColor(MUTED)
        paint.textSize = size * 0.032f
        canvas.drawText("to choose a location", center, center + size * 0.045f, paint)
    }
}
