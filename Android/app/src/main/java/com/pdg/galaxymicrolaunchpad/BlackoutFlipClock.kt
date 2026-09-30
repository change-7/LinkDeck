package com.pdg.galaxymicrolaunchpad

import android.graphics.Paint
import android.graphics.Rect
import android.graphics.RectF
import android.graphics.Typeface
import android.text.format.DateFormat
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import java.time.LocalTime
import java.util.Locale
import kotlinx.coroutines.delay

private const val GluqloCardColor = 0xFF1C1C1C.toInt()
private const val GluqloDigitColor = 0xFFB7B7B7.toInt()

@Composable
internal fun BlackoutFlipClock(sizePercent: Int, modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val is24Hour = remember(context) { DateFormat.is24HourFormat(context) }
    var time by remember { mutableStateOf(LocalTime.now()) }

    LaunchedEffect(Unit) {
        while (true) {
            val now = LocalTime.now()
            time = now
            val untilNextMinute = 60_000L - now.second * 1_000L - now.nano / 1_000_000L
            delay(untilNextMinute.coerceAtLeast(1L))
        }
    }

    BoxWithConstraints(modifier = modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
        val shortAxis = if (maxWidth >= maxHeight) maxHeight else maxWidth
        val longAxis = if (maxWidth >= maxHeight) maxWidth else maxHeight
        val cardSize = shortAxis * (0.6f * clampBlackoutClockSizePercent(sizePercent) / 100f)
        val gap = longAxis * (0.031f * clampBlackoutClockSizePercent(sizePercent) / 100f)
        val hour = blackoutClockHour(time, is24Hour)
        val period = blackoutClockMeridiem(time, is24Hour)

        if (maxWidth >= maxHeight) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(gap),
                verticalAlignment = Alignment.CenterVertically
            ) {
                BlackoutClockCard(hour, cardSize, period)
                BlackoutClockCard("%02d".format(Locale.US, time.minute), cardSize)
            }
        } else {
            Column(
                verticalArrangement = Arrangement.spacedBy(gap),
                horizontalAlignment = Alignment.CenterHorizontally
            ) {
                BlackoutClockCard(hour, cardSize, period)
                BlackoutClockCard("%02d".format(Locale.US, time.minute), cardSize)
            }
        }
    }
}

@Composable
private fun BlackoutClockCard(value: String, size: Dp, period: String? = null) {
    val context = LocalContext.current
    val typeface = remember(context) { context.resources.getFont(R.font.gluqlo) }
    val progress = remember { Animatable(1f) }
    var previousValue by remember { mutableStateOf(value) }
    var flipFrom by remember { mutableStateOf(value) }

    LaunchedEffect(value) {
        if (previousValue != value) {
            progress.snapTo(0f)
            flipFrom = previousValue
            previousValue = value
            progress.animateTo(1f, tween(260, easing = LinearEasing))
        }
    }

    Canvas(Modifier.size(size)) {
        val cardSide = this.size.minDimension
        val nativeCanvas = drawContext.canvas.nativeCanvas
        val save = nativeCanvas.save()
        val cardPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = GluqloCardColor }
        val digitPaint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.typeface = typeface
            textSize = cardSide / (0.6f * 1.68f)
            color = GluqloDigitColor
        }
        val cornerRadius = cardSide * (0.05714f / 0.6f)

        nativeCanvas.drawRoundRect(
            RectF(0f, 0f, cardSide, cardSide),
            cornerRadius,
            cornerRadius,
            cardPaint
        )

        val fraction = progress.value
        if (fraction >= 1f) {
            drawGluqloDigits(nativeCanvas, value, cardSide, digitPaint)
        } else {
            drawGluqloDigits(nativeCanvas, flipFrom, cardSide, digitPaint)
            nativeCanvas.save()
            nativeCanvas.clipRect(0f, 0f, cardSide, cardSide / 2f)
            nativeCanvas.drawRoundRect(RectF(0f, 0f, cardSide, cardSide), cornerRadius, cornerRadius, cardPaint)
            drawGluqloDigits(nativeCanvas, value, cardSide, digitPaint)
            nativeCanvas.restore()

            if (fraction < 0.5f) {
                val scaleY = 1f - fraction * 2f
                digitPaint.color = animatedGluqloColor(1f - fraction * 2f)
                nativeCanvas.save()
                nativeCanvas.clipRect(0f, 0f, cardSide, cardSide / 2f)
                nativeCanvas.scale(1f, scaleY, cardSide / 2f, cardSide / 2f)
                nativeCanvas.drawRoundRect(RectF(0f, 0f, cardSide, cardSide), cornerRadius, cornerRadius, cardPaint)
                drawGluqloDigits(nativeCanvas, flipFrom, cardSide, digitPaint)
                nativeCanvas.restore()
            } else {
                val scaleY = ((fraction - 0.5f) * 2f).coerceIn(0f, 1f)
                digitPaint.color = animatedGluqloColor(scaleY)
                nativeCanvas.save()
                nativeCanvas.clipRect(0f, cardSide / 2f, cardSide, cardSide)
                nativeCanvas.scale(1f, scaleY, cardSide / 2f, cardSide / 2f)
                nativeCanvas.drawRoundRect(RectF(0f, 0f, cardSide, cardSide), cornerRadius, cornerRadius, cardPaint)
                drawGluqloDigits(nativeCanvas, value, cardSide, digitPaint)
                nativeCanvas.restore()
            }
        }

        digitPaint.color = GluqloDigitColor
        period?.let { drawGluqloPeriod(nativeCanvas, it, cardSide, typeface, digitPaint) }
        drawGluqloSeam(nativeCanvas, cardSide)
        nativeCanvas.restoreToCount(save)
    }
}

private fun drawGluqloDigits(
    canvas: android.graphics.Canvas,
    value: String,
    cardSide: Float,
    paint: Paint
) {
    val bounds = Rect()
    val centerX = cardSide / 2f
    val centerY = cardSide / 2f
    val spacing = cardSide * (0.0125f / 0.6f)

    if (value.length == 1) {
        val singleDigitCenterX = centerX - if (value[0] == '1') spacing * 2.5f else 0f
        paint.getTextBounds(value, 0, 1, bounds)
        val x = singleDigitCenterX - bounds.width() / 2f - bounds.left
        val baseline = centerY - (bounds.top + bounds.bottom) / 2f
        canvas.drawText(value, x, baseline, paint)
        return
    }

    val adjustX = if (value[0] == '1') spacing * 2.5f else 0f
    val pairCenterX = centerX - adjustX
    val first = value.substring(0, 1)
    paint.getTextBounds(first, 0, 1, bounds)
    val firstX = pairCenterX - bounds.width() - spacing - if (adjustX != 0f) spacing else 0f
    canvas.drawText(first, firstX - bounds.left, centerY - (bounds.top + bounds.bottom) / 2f, paint)

    val second = value.substring(1, 2)
    paint.getTextBounds(second, 0, 1, bounds)
    val secondX = pairCenterX + spacing / 2f
    canvas.drawText(second, secondX - bounds.left, centerY - (bounds.top + bounds.bottom) / 2f, paint)
}

private fun drawGluqloPeriod(
    canvas: android.graphics.Canvas,
    period: String,
    cardSide: Float,
    typeface: Typeface,
    paint: Paint
) {
    paint.typeface = typeface
    paint.textSize = cardSide / (0.6f * 16.5f)
    val bounds = Rect()
    paint.getTextBounds(period, 0, period.length, bounds)
    val offset = cardSide * 0.127f
    val top = if (period == "PM") cardSide - offset - bounds.height() else offset
    canvas.drawText(period, cardSide * 0.07f - bounds.left, top - bounds.top, paint)
}

private fun drawGluqloSeam(canvas: android.graphics.Canvas, cardSide: Float) {
    val seamHeight = (cardSide * (0.005f / 0.6f)).coerceAtLeast(1f)
    val center = cardSide / 2f
    val seamPaint = Paint().apply { color = android.graphics.Color.BLACK }
    canvas.drawRect(0f, center - seamHeight / 2f, cardSide, center + seamHeight / 2f, seamPaint)
    seamPaint.color = android.graphics.Color.rgb(0x1A, 0x1A, 0x1A)
    canvas.drawRect(0f, center + seamHeight / 2f, cardSide, center + seamHeight / 2f + 1f, seamPaint)
}

private fun animatedGluqloColor(amount: Float): Int {
    val channel = (0xB7 * amount.coerceIn(0f, 1f)).toInt()
    return android.graphics.Color.rgb(channel, channel, channel)
}

internal fun blackoutClockHour(time: LocalTime, is24Hour: Boolean): String {
    val hour = if (is24Hour) time.hour else (time.hour + 11) % 12 + 1
    return hour.toString()
}

internal fun blackoutClockMeridiem(time: LocalTime, is24Hour: Boolean): String? {
    if (is24Hour) return null
    return if (time.hour < 12) "AM" else "PM"
}
