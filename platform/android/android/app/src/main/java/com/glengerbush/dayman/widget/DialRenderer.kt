package com.glengerbush.dayman.widget

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import kotlin.math.PI
import kotlin.math.cos
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

    fun render(snapshot: ClockSnapshot?, sizePx: Int = 720): Bitmap {
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

        drawHourTicks(canvas, center, radius, sizePx, paint)
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
            snapshot.moonIllumination,
            snapshot.moonPhaseAngle,
            paint,
        )
        drawCenterText(canvas, snapshot, center, sizePx, paint)
        return bitmap
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

    private fun drawHourTicks(
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
        illumination: Double,
        phaseAngle: Double,
        paint: Paint,
    ) {
        paint.style = Paint.Style.FILL
        paint.color = Color.parseColor("#415066")
        canvas.drawCircle(x, y, radius, paint)

        val litWidth = (radius * 2f * illumination.toFloat()).coerceIn(1f, radius * 2f)
        val lit = if (phaseAngle <= 180.0) {
            RectF(x + radius - litWidth, y - radius, x + radius, y + radius)
        } else {
            RectF(x - radius, y - radius, x - radius + litWidth, y + radius)
        }
        canvas.save()
        val clip = Path().apply { addCircle(x, y, radius, Path.Direction.CW) }
        canvas.clipPath(clip)
        paint.color = Color.parseColor(MOON)
        canvas.drawOval(lit, paint)
        paint.color = Color.parseColor("#AAB6BA")
        canvas.drawCircle(x - radius * 0.27f, y - radius * 0.18f, radius * 0.15f, paint)
        canvas.drawCircle(x + radius * 0.23f, y + radius * 0.22f, radius * 0.10f, paint)
        canvas.restore()
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

        val next = snapshot.nextSolarEvent?.relativeLabel ?: snapshot.moonPhaseName
        paint.typeface = Typeface.create("sans-serif", Typeface.NORMAL)
        paint.color = Color.parseColor(MUTED)
        paint.textSize = min(size * 0.034f, size * 0.34f / next.length.coerceAtLeast(1))
        canvas.drawText(next, center, center + size * 0.083f, paint)

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
