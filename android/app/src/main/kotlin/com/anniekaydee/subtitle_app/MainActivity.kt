package com.anniekaydee.subtitle_app

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.media.Image
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream
import java.io.RandomAccessFile
import java.nio.ByteBuffer
import java.nio.ByteOrder

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.anniekaydee.subtitle_app/audio"
    private val TARGET_SAMPLE_RATE = 44100
    private val TARGET_CHANNELS = 1
    private var methodChannel: MethodChannel? = null
    private var lastEmittedPct = -1

    // ── Image overlays (B-roll/sticker) composited onto each frame ────────────
    private data class ImgOverlay(
        val bitmap: Bitmap,           // static image, GIF first frame, or video first frame (ratio/fallback)
        val startUs: Long,
        val endUs: Long,
        val x: Float,      // 0–1 centre
        val y: Float,      // 0–1 centre
        val scale: Float,  // fraction of display width
        val rotation: Float,
        val flipH: Boolean,
        val movie: android.graphics.Movie? = null, // animated GIF (null = static)
        val gifW: Int = 0,
        val gifH: Int = 0,
        val decoder: BrollDecoder? = null, // video B-roll sequential decoder (null = not video)
        val srcDurUs: Long = 0L,      // source clip length (for looping)
        val cover: Boolean = false,   // fill the whole frame (crop overflow)
        val opacity: Float = 1f,      // static opacity (used when keyframes empty)
        val keyframes: List<OvKf> = emptyList(), // animate x/y/scale/rotation/opacity
    )
    private data class OvKf(
        val timeUs: Long, val x: Float, val y: Float,
        val scale: Float, val rotation: Float, val opacity: Float, val easing: Int = 0,
    )
    private data class OvState(
        val x: Float, val y: Float, val scale: Float, val rotation: Float, val opacity: Float)

    /// Interpolate an overlay's transform + opacity at [presentUs] across its
    /// keyframes (falls back to the static values when there are none).
    private fun overlayStateAt(ov: ImgOverlay, presentUs: Long): OvState {
        val kfs = ov.keyframes
        if (kfs.isEmpty()) return OvState(ov.x, ov.y, ov.scale, ov.rotation, ov.opacity)
        if (presentUs <= kfs.first().timeUs) {
            val k = kfs.first(); return OvState(k.x, k.y, k.scale, k.rotation, k.opacity)
        }
        if (presentUs >= kfs.last().timeUs) {
            val k = kfs.last(); return OvState(k.x, k.y, k.scale, k.rotation, k.opacity)
        }
        var i = 0
        while (i < kfs.size - 1 && kfs[i + 1].timeUs < presentUs) i++
        val a = kfs[i]; val b = kfs[i + 1]
        val span = (b.timeUs - a.timeUs).coerceAtLeast(1L)
        val t = ease(a.easing,
            ((presentUs - a.timeUs).toFloat() / span).coerceIn(0f, 1f))
        return OvState(
            a.x + (b.x - a.x) * t,
            a.y + (b.y - a.y) * t,
            a.scale + (b.scale - a.scale) * t,
            a.rotation + (b.rotation - a.rotation) * t,
            a.opacity + (b.opacity - a.opacity) * t,
        )
    }
    private var imageOverlays: List<ImgOverlay> = emptyList()

    /** Release any B-roll video decoders held by overlays. */
    private fun releaseOverlayVideos() {
        for (ov in imageOverlays) {
            try { ov.decoder?.release() } catch (_: Exception) {}
        }
    }

    private fun parseOvKfs(raw: Any?): List<OvKf> {
        @Suppress("UNCHECKED_CAST")
        val list = raw as? List<Map<String, Any>> ?: return emptyList()
        val out = ArrayList<OvKf>()
        for (k in list) {
            try {
                out.add(OvKf(
                    timeUs = (k["timeMs"] as Number).toLong() * 1000L,
                    x = (k["x"] as? Number)?.toFloat() ?: 0.5f,
                    y = (k["y"] as? Number)?.toFloat() ?: 0.5f,
                    scale = (k["scale"] as? Number)?.toFloat() ?: 0.5f,
                    rotation = (k["rotation"] as? Number)?.toFloat() ?: 0f,
                    opacity = (k["opacity"] as? Number)?.toFloat() ?: 1f,
                    easing = (k["easing"] as? Number)?.toInt() ?: 0,
                ))
            } catch (_: Exception) {}
        }
        out.sortBy { it.timeUs }
        return out
    }

    private fun parseImageOverlays(raw: List<Map<String, Any>>?): List<ImgOverlay> {
        if (raw == null) return emptyList()
        val out = ArrayList<ImgOverlay>()
        for (m in raw) {
            try {
                val path = m["path"] as? String ?: continue
                if (!File(path).exists()) continue
                val isVideo = (m["isVideo"] as? Boolean) ?: false
                if (isVideo) {
                    // Video B-roll: read duration + rotation + a fallback first frame
                    // via a one-shot retriever, then stream frames with a sequential
                    // MediaCodec decoder (BrollDecoder) for smooth export-fps playback.
                    var durMs = 0L
                    var rot = 0
                    var first: Bitmap? = null
                    val r = android.media.MediaMetadataRetriever()
                    try {
                        r.setDataSource(path)
                        durMs = r.extractMetadata(
                            android.media.MediaMetadataRetriever.METADATA_KEY_DURATION)
                            ?.toLongOrNull() ?: 0L
                        rot = r.extractMetadata(
                            android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION)
                            ?.toIntOrNull() ?: 0
                        first = r.getFrameAtTime(
                            0L, android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC)
                    } catch (_: Exception) {}
                    try { r.release() } catch (_: Exception) {}
                    if (first == null) continue
                    val dec = try { BrollDecoder(path, rot) } catch (_: Exception) { null }
                    out.add(ImgOverlay(
                        bitmap = first,
                        startUs = (m["startMs"] as Number).toLong() * 1000L,
                        endUs = (m["endMs"] as Number).toLong() * 1000L,
                        x = (m["x"] as? Number)?.toFloat() ?: 0.5f,
                        y = (m["y"] as? Number)?.toFloat() ?: 0.5f,
                        scale = (m["scale"] as? Number)?.toFloat() ?: 0.5f,
                        rotation = (m["rotation"] as? Number)?.toFloat() ?: 0f,
                        flipH = (m["flipH"] as? Boolean) ?: false,
                        decoder = dec,
                        srcDurUs = durMs * 1000L,
                        gifW = first.width,
                        gifH = first.height,
                        cover = (m["cover"] as? Boolean) ?: false,
                        opacity = (m["opacity"] as? Number)?.toFloat() ?: 1f,
                        keyframes = parseOvKfs(m["keyframes"]),
                    ))
                    continue
                }
                val bmp = android.graphics.BitmapFactory.decodeFile(path) ?: continue
                // Animated GIF → also load a Movie so we can render the right frame
                // per video time. BitmapFactory above gives the first frame (ratio).
                var movie: android.graphics.Movie? = null
                if (path.lowercase().endsWith(".gif")) {
                    try {
                        val mv = android.graphics.Movie.decodeFile(path)
                        if (mv != null && mv.duration() > 0 && mv.width() > 0) movie = mv
                    } catch (_: Exception) {}
                }
                out.add(ImgOverlay(
                    bitmap = bmp,
                    startUs = (m["startMs"] as Number).toLong() * 1000L,
                    endUs = (m["endMs"] as Number).toLong() * 1000L,
                    x = (m["x"] as? Number)?.toFloat() ?: 0.5f,
                    y = (m["y"] as? Number)?.toFloat() ?: 0.5f,
                    scale = (m["scale"] as? Number)?.toFloat() ?: 0.5f,
                    rotation = (m["rotation"] as? Number)?.toFloat() ?: 0f,
                    flipH = (m["flipH"] as? Boolean) ?: false,
                    movie = movie,
                    gifW = movie?.width() ?: bmp.width,
                    gifH = movie?.height() ?: bmp.height,
                    cover = (m["cover"] as? Boolean) ?: false,
                    opacity = (m["opacity"] as? Number)?.toFloat() ?: 1f,
                    keyframes = parseOvKfs(m["keyframes"]),
                ))
            } catch (_: Exception) {}
        }
        return out
    }

    // ── Zoom / Ken-Burns effects on the video frame ───────────────────────────
    private data class ZoomKf(val timeUs: Long, val scale: Float, val fx: Float, val fy: Float, val easing: Int = 0)

    /// Easing curve for a keyframe interval (mirrors the Dart _ease).
    private fun ease(mode: Int, t: Float): Float {
        return when (mode) {
            1 -> t * t
            2 -> 1f - (1f - t) * (1f - t)
            3 -> if (t < 0.5f) 2f * t * t else { val u = -2f * t + 2f; 1f - (u * u) / 2f }
            4 -> t * t * t
            5 -> { val u = 1f - t; 1f - u * u * u }
            else -> t
        }
    }
    private data class ZoomFx(
        val startUs: Long,
        val endUs: Long,
        val fromScale: Float,
        val toScale: Float,
        val focusX: Float,
        val focusY: Float,
        val keyframes: List<ZoomKf>,
    )
    private var zoomEffects: List<ZoomFx> = emptyList()

    private fun parseZoomEffects(raw: List<Map<String, Any>>?): List<ZoomFx> {
        if (raw == null) return emptyList()
        val out = ArrayList<ZoomFx>()
        for (m in raw) {
            try {
                @Suppress("UNCHECKED_CAST")
                val kfRaw = m["keyframes"] as? List<Map<String, Any>>
                val kfs = ArrayList<ZoomKf>()
                kfRaw?.forEach { k ->
                    kfs.add(ZoomKf(
                        timeUs = (k["timeMs"] as Number).toLong() * 1000L,
                        scale = (k["scale"] as? Number)?.toFloat() ?: 1f,
                        fx = (k["focusX"] as? Number)?.toFloat() ?: 0.5f,
                        fy = (k["focusY"] as? Number)?.toFloat() ?: 0.5f,
                        easing = (k["easing"] as? Number)?.toInt() ?: 0,
                    ))
                }
                kfs.sortBy { it.timeUs }
                out.add(ZoomFx(
                    startUs = (m["startMs"] as Number).toLong() * 1000L,
                    endUs = (m["endMs"] as Number).toLong() * 1000L,
                    fromScale = (m["fromScale"] as? Number)?.toFloat() ?: 1f,
                    toScale = (m["toScale"] as? Number)?.toFloat() ?: 1f,
                    focusX = (m["focusX"] as? Number)?.toFloat() ?: 0.5f,
                    focusY = (m["focusY"] as? Number)?.toFloat() ?: 0.5f,
                    keyframes = kfs,
                ))
            } catch (_: Exception) {}
        }
        return out
    }

    /// Scale + focal point active at [presentUs], or null (no zoom / scale≈1).
    private fun zoomAt(presentUs: Long): Triple<Float, Float, Float>? {
        for (z in zoomEffects) {
            if (presentUs < z.startUs || presentUs > z.endUs) continue
            val s: Float; val fx: Float; val fy: Float
            if (z.keyframes.isNotEmpty()) {
                // Keyframe mode: interpolate scale + focal across keyframes
                // (a single keyframe holds its value across the whole clip).
                val kfs = z.keyframes
                when {
                    presentUs <= kfs.first().timeUs -> {
                        s = kfs.first().scale; fx = kfs.first().fx; fy = kfs.first().fy
                    }
                    presentUs >= kfs.last().timeUs -> {
                        s = kfs.last().scale; fx = kfs.last().fx; fy = kfs.last().fy
                    }
                    else -> {
                        var i = 0
                        while (i < kfs.size - 1 && kfs[i + 1].timeUs < presentUs) i++
                        val a = kfs[i]; val b = kfs[i + 1]
                        val span = (b.timeUs - a.timeUs).coerceAtLeast(1L)
                        val t = ease(a.easing,
                            ((presentUs - a.timeUs).toFloat() / span).coerceIn(0f, 1f))
                        s = a.scale + (b.scale - a.scale) * t
                        fx = a.fx + (b.fx - a.fx) * t
                        fy = a.fy + (b.fy - a.fy) * t
                    }
                }
            } else {
                val dur = (z.endUs - z.startUs).coerceAtLeast(1L)
                val t = ((presentUs - z.startUs).toFloat() / dur).coerceIn(0f, 1f)
                s = z.fromScale + (z.toScale - z.fromScale) * t
                fx = z.focusX; fy = z.focusY
            }
            if (s <= 1.001f) return null
            return Triple(s, fx, fy)
        }
        return null
    }

    /// Return a zoomed copy of [src] for [presentUs], or [src] unchanged.
    private fun applyZoom(src: Bitmap, presentUs: Long): Bitmap {
        val z = zoomAt(presentUs) ?: return src
        val (s, fx, fy) = z
        val out = Bitmap.createBitmap(src.width, src.height, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val cx = fx * src.width
        val cy = fy * src.height
        val mtx = android.graphics.Matrix().apply {
            postTranslate(-cx, -cy)
            postScale(s, s)
            postTranslate(cx, cy)
        }
        c.drawBitmap(src, mtx,
            android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
        return out
    }

    // ── Fade transitions (black overlay with animated alpha) ───────────────────
    private data class FadeFx(val startUs: Long, val endUs: Long, val toBlack: Boolean)
    private var fadeEffects: List<FadeFx> = emptyList()

    private fun parseFadeEffects(raw: List<Map<String, Any>>?): List<FadeFx> {
        if (raw == null) return emptyList()
        val out = ArrayList<FadeFx>()
        for (m in raw) {
            try {
                out.add(FadeFx(
                    startUs = (m["startMs"] as Number).toLong() * 1000L,
                    endUs = (m["endMs"] as Number).toLong() * 1000L,
                    toBlack = (m["toBlack"] as? Boolean) ?: true,
                ))
            } catch (_: Exception) {}
        }
        return out
    }

    /// Black-overlay alpha (0..255) active at [presentUs]; 0 = none.
    private fun fadeAlphaAt(presentUs: Long): Int {
        for (f in fadeEffects) {
            if (presentUs < f.startUs || presentUs > f.endUs) continue
            val dur = (f.endUs - f.startUs).coerceAtLeast(1L)
            val t = ((presentUs - f.startUs).toFloat() / dur).coerceIn(0f, 1f)
            val a = if (f.toBlack) t else (1f - t)
            return (a * 255f).toInt().coerceIn(0, 255)
        }
        return 0
    }

    // ── Camera shake ───────────────────────────────────────────────────────────
    private data class ShakeFx(val startUs: Long, val endUs: Long, val intensity: Float)
    private var shakeEffects: List<ShakeFx> = emptyList()

    private fun parseShakeEffects(raw: List<Map<String, Any>>?): List<ShakeFx> {
        if (raw == null) return emptyList()
        val out = ArrayList<ShakeFx>()
        for (m in raw) {
            try {
                out.add(ShakeFx(
                    startUs = (m["startMs"] as Number).toLong() * 1000L,
                    endUs = (m["endMs"] as Number).toLong() * 1000L,
                    intensity = (m["intensity"] as? Number)?.toFloat() ?: 0.03f,
                ))
            } catch (_: Exception) {}
        }
        return out
    }

    /// Shake intensity active at [presentUs] (fraction of frame), or 0.
    private fun shakeAt(presentUs: Long): Float {
        for (s in shakeEffects) {
            if (presentUs in s.startUs..s.endUs) return s.intensity
        }
        return 0f
    }

    /// Apply a camera shake to [src] for [presentUs]: scale up slightly so the
    /// jitter never reveals edges, then offset by a fast oscillation.
    private fun applyShake(src: Bitmap, presentUs: Long): Bitmap {
        val amp = shakeAt(presentUs)
        if (amp <= 0f) return src
        val w = src.width; val h = src.height
        val maxOff = amp * w
        // Two detuned sines → organic, non-repeating-looking shake.
        val tSec = presentUs / 1_000_000.0
        val dx = (Math.sin(tSec * 57.0) + Math.sin(tSec * 89.0) * 0.6).toFloat() * maxOff
        val dy = (Math.cos(tSec * 63.0) + Math.cos(tSec * 97.0) * 0.6).toFloat() * maxOff
        val scale = 1f + amp * 2f // margin so offset stays inside
        val out = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val mtx = android.graphics.Matrix().apply {
            postTranslate(-w / 2f, -h / 2f)
            postScale(scale, scale)
            postTranslate(w / 2f + dx, h / 2f + dy)
        }
        c.drawBitmap(src, mtx, android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG))
        return out
    }

    // ── Blurred background (fit a non-9:16 video into a 9:16 frame) ────────────
    private var blurBg: Boolean = false

    /// Compose [video] into an [outW]x[outH] canvas: a blurred, scaled-up copy
    /// fills the frame (cover) with the real video fit-centered on top.
    private fun blurBgCompose(video: Bitmap, outW: Int, outH: Int): Bitmap {
        val out = Bitmap.createBitmap(outW, outH, Bitmap.Config.ARGB_8888)
        val c = Canvas(out)
        val fp = android.graphics.Paint(android.graphics.Paint.FILTER_BITMAP_FLAG)
        // Cheap blur: downscale to ~1/18 then upscale to COVER the frame.
        val sw = (video.width / 18).coerceAtLeast(2)
        val sh = (video.height / 18).coerceAtLeast(2)
        val small = Bitmap.createScaledBitmap(video, sw, sh, true)
        val cover = maxOf(outW.toFloat() / sw, outH.toFloat() / sh)
        val cw = sw * cover; val ch = sh * cover
        c.drawBitmap(small, android.graphics.Matrix().apply {
            postScale(cover, cover)
            postTranslate((outW - cw) / 2f, (outH - ch) / 2f)
        }, fp)
        small.recycle()
        c.drawARGB(70, 0, 0, 0) // dark scrim for subtitle contrast
        // Real video, fit (contain) + centered.
        val fit = minOf(outW.toFloat() / video.width, outH.toFloat() / video.height)
        val fw = video.width * fit; val fh = video.height * fit
        c.drawBitmap(video, android.graphics.Matrix().apply {
            postScale(fit, fit)
            postTranslate((outW - fw) / 2f, (outH - fh) / 2f)
        }, fp)
        return out
    }

    /// Draw any active image overlays onto [canvas] sized [w]x[h] (display dims)
    /// for presentation time [presentUs]. Scaled by display width, centred at
    /// (x*w, y*h), rotated about that centre.
    private fun drawImageOverlays(canvas: Canvas, presentUs: Long, w: Int, h: Int) {
        if (imageOverlays.isEmpty()) return
        val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.FILTER_BITMAP_FLAG)
        for (ov in imageOverlays) {
            if (presentUs < ov.startUs || presentUs > ov.endUs) continue

            // Interpolated transform + opacity (keyframes) at this time.
            val st = overlayStateAt(ov, presentUs)
            val alpha = (st.opacity.coerceIn(0f, 1f) * 255f).toInt()
            if (alpha <= 0) continue
            paint.alpha = alpha

            // Full-screen "cover" overlay: fill the whole frame, crop the overflow.
            // Ignores x/y/scale/rotation. Used for full-screen B-roll.
            if (ov.cover) {
                val dec0 = ov.decoder
                val src: Bitmap = if (dec0 != null) {
                    val elapsedUs = presentUs - ov.startUs
                    val srcUs = if (ov.srcDurUs > 0L) elapsedUs % ov.srcDurUs else elapsedUs
                    dec0.frameAt(srcUs) ?: ov.bitmap
                } else ov.bitmap
                val sw = src.width.coerceAtLeast(1)
                val sh = src.height.coerceAtLeast(1)
                val coverScale = maxOf(w.toFloat() / sw, h.toFloat() / sh)
                val dw = sw * coverScale
                val dh = sh * coverScale
                val left = (w - dw) / 2f
                val top = (h - dh) / 2f
                canvas.save()
                canvas.clipRect(0f, 0f, w.toFloat(), h.toFloat())
                if (ov.flipH) { canvas.translate(w.toFloat(), 0f); canvas.scale(-1f, 1f) }
                canvas.drawBitmap(src, null, RectF(left, top, left + dw, top + dh), paint)
                canvas.restore()
                continue
            }

            val srcW = ov.gifW.coerceAtLeast(1)
            val srcH = ov.gifH.coerceAtLeast(1)
            val targetW = st.scale * w
            val targetH = targetW * (srcH.toFloat() / srcW.toFloat())
            val cx = st.x * w
            val cy = st.y * h
            canvas.save()
            canvas.translate(cx, cy)
            if (st.rotation != 0f) canvas.rotate(st.rotation)
            if (ov.flipH) canvas.scale(-1f, 1f)
            val dec = ov.decoder
            if (dec != null) {
                // Video B-roll: stream the frame at the (looped) elapsed time from
                // the sequential decoder — smooth at the export frame rate.
                val elapsedUs = presentUs - ov.startUs
                val srcUs = if (ov.srcDurUs > 0L) elapsedUs % ov.srcDurUs else elapsedUs
                val fb = dec.frameAt(srcUs) ?: ov.bitmap
                val fsW = fb.width.coerceAtLeast(1)
                val fsH = fb.height.coerceAtLeast(1)
                val tW = st.scale * w
                val tH = tW * (fsH.toFloat() / fsW.toFloat())
                canvas.drawBitmap(fb, null, RectF(-tW / 2f, -tH / 2f, tW / 2f, tH / 2f), paint)
                canvas.restore()
                continue
            }
            val mv = ov.movie
            if (mv != null && mv.duration() > 0) {
                // Animated GIF: pick the frame at the looped elapsed time.
                val elapsedMs = ((presentUs - ov.startUs) / 1000L).toInt()
                mv.setTime(elapsedMs % mv.duration())
                canvas.scale(targetW / srcW, targetH / srcH)
                canvas.translate(-srcW / 2f, -srcH / 2f)
                try { mv.draw(canvas, 0f, 0f, paint) } catch (_: Exception) {
                    canvas.drawBitmap(ov.bitmap, null,
                        RectF(0f, 0f, srcW.toFloat(), srcH.toFloat()), paint)
                }
            } else {
                val dst = RectF(-targetW / 2f, -targetH / 2f, targetW / 2f, targetH / 2f)
                canvas.drawBitmap(ov.bitmap, null, dst, paint)
            }
            canvas.restore()
        }
    }

    // Worker pool to parallelise the per-pixel YUV<->RGB conversions across cores.
    private val cpuCount = Runtime.getRuntime().availableProcessors().coerceIn(2, 8)
    private val pixelPool: java.util.concurrent.ExecutorService =
        java.util.concurrent.Executors.newFixedThreadPool(cpuCount)

    /** Run [body] over disjoint row ranges [start,end) in parallel and wait. */
    private inline fun parallelRows(h: Int, crossinline body: (Int, Int) -> Unit) {
        val chunk = (h + cpuCount - 1) / cpuCount
        val futures = ArrayList<java.util.concurrent.Future<*>>(cpuCount)
        var r = 0
        while (r < h) {
            val start = r
            val end = (r + chunk).coerceAtMost(h)
            futures.add(pixelPool.submit { body(start, end) })
            r = end
        }
        for (f in futures) f.get()
    }

    /// Sequential MediaCodec decoder for one B-roll clip. [frameAt] decodes forward
    /// to the requested source time and returns the current frame (display oriented),
    /// rewinding on a backward jump (loop wrap / scrub). Holds only one frame in
    /// memory. Reuses [imageToBitmap]/[bufferToBitmap] from the outer class.
    inner class BrollDecoder(path: String, private val rotationDeg: Int) {
        private val extractor = MediaExtractor()
        private var codec: MediaCodec? = null
        private val info = MediaCodec.BufferInfo()
        private var vw = 0
        private var vh = 0
        private var inputDone = false
        private var outputDone = false
        private var currentPtsUs = -1L
        private var current: Bitmap? = null
        private var ok = false

        init {
            try {
                extractor.setDataSource(path)
                var tIdx = -1
                var fmt: MediaFormat? = null
                for (i in 0 until extractor.trackCount) {
                    val f = extractor.getTrackFormat(i)
                    if ((f.getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                        tIdx = i; fmt = f; break
                    }
                }
                if (tIdx >= 0 && fmt != null) {
                    extractor.selectTrack(tIdx)
                    vw = fmt.getInteger(MediaFormat.KEY_WIDTH)
                    vh = fmt.getInteger(MediaFormat.KEY_HEIGHT)
                    val c = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
                    c.configure(fmt, null, null, 0)
                    c.start()
                    codec = c
                    ok = true
                }
            } catch (_: Exception) { ok = false }
        }

        private fun orient(bmp: Bitmap): Bitmap {
            if (rotationDeg == 0) return bmp
            val m = android.graphics.Matrix().apply { postRotate(rotationDeg.toFloat()) }
            val r = Bitmap.createBitmap(bmp, 0, 0, bmp.width, bmp.height, m, true)
            bmp.recycle(); return r
        }

        private fun rewind() {
            try {
                extractor.seekTo(0L, MediaExtractor.SEEK_TO_CLOSEST_SYNC)
                codec?.flush()
            } catch (_: Exception) {}
            inputDone = false; outputDone = false; currentPtsUs = -1L
        }

        /** Frame at [targetUs] (display oriented). Caller must NOT recycle it. */
        fun frameAt(targetUs: Long): Bitmap? {
            val c = codec
            if (!ok || c == null) return current
            // Backward jump (loop wrap or scrub) → rewind and re-decode from start.
            if (targetUs < currentPtsUs - 40_000L) {
                current?.recycle(); current = null
                rewind()
            }
            var guard = 0
            while (currentPtsUs < targetUs && !outputDone && guard < 3000) {
                guard++
                if (!inputDone) {
                    val inIdx = c.dequeueInputBuffer(8_000L)
                    if (inIdx >= 0) {
                        val buf = c.getInputBuffer(inIdx)!!
                        val sz = extractor.readSampleData(buf, 0)
                        if (sz < 0) {
                            c.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            c.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val outIdx = c.dequeueOutputBuffer(info, 8_000L)
                if (outIdx >= 0) {
                    val isEos = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                    if (info.size > 0) {
                        val img = c.getOutputImage(outIdx)
                        val raw = if (img != null) { val b = imageToBitmap(img); img.close(); b }
                                  else bufferToBitmap(c.getOutputBuffer(outIdx), c.outputFormat, vw, vh)
                        c.releaseOutputBuffer(outIdx, false)
                        if (raw != null) {
                            current?.recycle()
                            current = orient(raw)
                            currentPtsUs = info.presentationTimeUs
                        }
                    } else {
                        c.releaseOutputBuffer(outIdx, false)
                    }
                    if (isEos) outputDone = true
                }
            }
            return current
        }

        fun release() {
            try { current?.recycle() } catch (_: Exception) {}
            current = null
            try { codec?.stop() } catch (_: Exception) {}
            try { codec?.release() } catch (_: Exception) {}
            try { extractor.release() } catch (_: Exception) {}
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel = ch
        ch.setMethodCallHandler { call, result ->
                when (call.method) {
                    "extractAudio" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        val outputPath = call.argument<String>("outputPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "outputPath missing", null)
                        extractAudio(videoPath, outputPath, result)
                    }
                    "resolveVideoPath" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        resolveVideoPath(videoPath, result)
                    }
                    "burnSubtitles" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        val outputPath = call.argument<String>("outputPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "outputPath missing", null)
                        val fileName = call.argument<String>("fileName")
                            ?: return@setMethodCallHandler result.error("MISSING", "fileName missing", null)
                        val segments = call.argument<List<Map<String, Any>>>("segments")
                            ?: return@setMethodCallHandler result.error("MISSING", "segments missing", null)
                        val style = call.argument<Map<String, Any>>("style")
                            ?: return@setMethodCallHandler result.error("MISSING", "style missing", null)
                        val autoCut = call.argument<Boolean>("autoCut") ?: false
                        val returnTempPath = call.argument<Boolean>("returnTempPath") ?: false
                        val keptRegionsMs = call.argument<List<Int>>("keptRegionsMs")
                        val imageOverlays = call.argument<List<Map<String, Any>>>("imageOverlays")
                        val zoomEffectsRaw = call.argument<List<Map<String, Any>>>("zoomEffects")
                        val fadeEffectsRaw = call.argument<List<Map<String, Any>>>("fadeEffects")
                        val shakeEffectsRaw = call.argument<List<Map<String, Any>>>("shakeEffects")
                        val blurBgArg = call.argument<Boolean>("bgBlur") ?: false
                        val autoCutGapMs = (call.argument<Int>("autoCutGapMs") ?: 300).toLong()
                        burnSubtitles(videoPath, outputPath, fileName, segments, style, autoCut, returnTempPath, keptRegionsMs, imageOverlays, zoomEffectsRaw, fadeEffectsRaw, shakeEffectsRaw, blurBgArg, autoCutGapMs, result)
                    }
                    "detectSpeechOnsets" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        detectSpeechOnsets(videoPath, result)
                    }
                    "detectSpeechRegions" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        detectSpeechRegions(videoPath, result)
                    }
                    "segmentWords" -> {
                        val texts = call.argument<List<String>>("texts") ?: emptyList()
                        val locale = call.argument<String>("locale") ?: "lo"
                        result.success(segmentWords(texts, locale))
                    }
                    "audioWaveform" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        audioWaveform(videoPath, result)
                    }
                    "extractThumbnails" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        val maxCount = call.argument<Int>("maxCount") ?: 36
                        val height = call.argument<Int>("height") ?: 120
                        extractThumbnails(videoPath, maxCount, height, result)
                    }
                    "videoMeta" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        val thumbPath = call.argument<String>("thumbPath")
                        videoMeta(videoPath, thumbPath, result)
                    }
                    "replaceAudioTrack" -> {
                        val videoPath = call.argument<String>("videoPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "videoPath missing", null)
                        val audioPath = call.argument<String>("audioPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "audioPath missing", null)
                        val outputPath = call.argument<String>("outputPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "outputPath missing", null)
                        val fileName = call.argument<String>("fileName")
                            ?: return@setMethodCallHandler result.error("MISSING", "fileName missing", null)
                        replaceAudioTrack(videoPath, audioPath, outputPath, fileName, result)
                    }
                    "saveAudioToGallery" -> {
                        val audioPath = call.argument<String>("audioPath")
                            ?: return@setMethodCallHandler result.error("MISSING", "audioPath missing", null)
                        val fileName = call.argument<String>("fileName")
                            ?: return@setMethodCallHandler result.error("MISSING", "fileName missing", null)
                        saveAudioToGallery(audioPath, fileName, result)
                    }
                    "saveTextFile" -> {
                        val content = call.argument<String>("content")
                            ?: return@setMethodCallHandler result.error("MISSING", "content missing", null)
                        val fileName = call.argument<String>("fileName")
                            ?: return@setMethodCallHandler result.error("MISSING", "fileName missing", null)
                        val mime = call.argument<String>("mime") ?: "text/plain"
                        saveTextFile(content, fileName, mime, result)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    // ─── Data classes ─────────────────────────────────────────────────────────

    private data class Seg(
        val startUs: Long,
        val endUs: Long,
        val text: String,
        val translatedText: String? = null,
        val words: List<String> = emptyList(),
        val wordTimingsUs: List<Long>? = null,
        val styleOverride: Map<String, Any?>? = null,
        val emphasis: List<Int> = emptyList(), // Auto ✨ punch-word indices
        val emoji: String? = null,             // Auto ✨ emoji for this line
    )

    // Cache of typefaces built for per-segment font overrides (key: "path|weight").
    private val tfCache = HashMap<String, Typeface>()

    private fun buildTypefaceCached(fontPath: String, weight: Int): Typeface {
        val w = weight.coerceIn(100, 900)
        val key = "$fontPath|$w"
        tfCache[key]?.let { return it }
        val file = File(fontPath)
        val base = if (file.exists()) Typeface.createFromFile(file) else Typeface.DEFAULT
        val tf = try {
            if (file.exists() && Build.VERSION.SDK_INT >= 26)
                Typeface.Builder(file).setFontVariationSettings("'wght' ${w.toFloat()}").setWeight(w).build()
                    ?: Typeface.create(base, w, false)
            else if (Build.VERSION.SDK_INT >= 28) Typeface.create(base, w, false)
            else if (w >= 600) Typeface.create(base, Typeface.BOLD) else base
        } catch (e: Exception) { base }
        tfCache[key] = tf
        return tf
    }

    /** Build an effective RenderStyle for [seg], applying its per-segment override
     *  on top of [base]. Returns [base] unchanged when the segment has no override. */
    private fun effectiveStyle(seg: Seg, base: RenderStyle, displayH: Int): RenderStyle {
        val ov = seg.styleOverride ?: return base
        val fontPath = ov["fontPath"] as? String
        val weight = (ov["fontWeight"] as? Number)?.toInt() ?: 600
        val fontSize = (ov["fontSize"] as? Number)?.toFloat() ?: 18f
        val tf = if (fontPath != null) buildTypefaceCached(fontPath, weight) else base.typeface
        // Per-segment karaoke: explicit on/off lets a single phrase enable (or
        // disable) the colour-sweep independent of the project setting.
        val ovKaraoke = ov["karaoke"] as? Boolean
        val ovKaraokeColor = when (ovKaraoke) {
            true -> (ov["karaokeColor"] as? Number)?.toInt() ?: base.karaokeColor
            false -> null
            else -> base.karaokeColor
        }
        return base.copy(
            textColor = (ov["textColor"] as? Number)?.toInt() ?: base.textColor,
            bgColor = (ov["bgColor"] as? Number)?.toInt(),
            karaokeColor = ovKaraokeColor,
            karaokeScale = ov["karaokeScale"] as? Boolean ?: base.karaokeScale,
            hasShadow = ov["hasShadow"] as? Boolean ?: false,
            has3dShadow = ov["has3dShadow"] as? Boolean ?: false,
            hasOutline = ov["hasOutline"] as? Boolean ?: base.hasOutline,
            outlineColor = (ov["outlineColor"] as? Number)?.toInt() ?: base.outlineColor,
            gradientColors = (ov["gradientColors"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }?.toIntArray() ?: base.gradientColors,
            hasNeonGlow = ov["hasNeonGlow"] as? Boolean ?: false,
            glowColor = (ov["glowColor"] as? Number)?.toInt(),
            hasUnderline = ov["hasUnderline"] as? Boolean ?: false,
            underlineColor = (ov["underlineColor"] as? Number)?.toInt(),
            typeface = tf,
            scaledTextSize = fontSize * displayH / 220f,
            positionY = (ov["positionY"] as? Number)?.toFloat() ?: base.positionY,
            positionX = (ov["positionX"] as? Number)?.toFloat() ?: base.positionX,
            rotation = (ov["rotation"] as? Number)?.toFloat() ?: base.rotation,
            animationType = ov["animationType"] as? String ?: base.animationType,
        )
    }

    private data class RenderStyle(
        val textColor: Int,
        val bgColor: Int?,
        val karaokeColor: Int?,
        val karaokeScale: Boolean = false,
        val emphasisColor: Int? = null, // colour for Auto ✨ punch words
        val hasShadow: Boolean,
        val has3dShadow: Boolean = false,
        val hasOutline: Boolean = false,
        val outlineColor: Int? = null,
        val gradientColors: IntArray? = null,
        val hasNeonGlow: Boolean,
        val glowColor: Int?,
        val hasUnderline: Boolean,
        val underlineColor: Int?,
        val typeface: Typeface,
        val scaledTextSize: Float,
        val positionY: Float,
        val positionX: Float = 0.5f,
        val rotation: Float = 0f,
        val animationType: String,
        val bilingualTextColor: Int?,
        val bilingualBgColor: Int?,
        val bilingualHasShadow: Boolean,
        val bilingualIsBold: Boolean,
        val scaledBilingualSize: Float,
        val bilingualHasNeon: Boolean,
        val bilingualGlowColor: Int?,
        val bilingualGap: Float,
        val watermarkText: String? = null,
        val watermarkPosition: String = "top",
        val watermarkLogo: Bitmap? = null,
    )

    private class KWord(val text: String, val width: Float, val gapBefore: Float, val index: Int)

    private fun isAsciiWordChar(c: Char): Boolean =
        (c in 'A'..'Z') || (c in 'a'..'z') || (c in '0'..'9')

    /** Mirror of Dart needSpaceBetweenWords: Lao tight, space around Latin/digits. */
    /// Typewriter reveal: text shown so far by syllable units (~55ms/unit).
    private fun revealedText(seg: Seg, elapsedUs: Long, perUnitMs: Long): String {
        val units = seg.words.filter { it.isNotEmpty() }
        if (units.isEmpty()) return seg.text
        val k = ((elapsedUs / 1000L) / perUnitMs.coerceAtLeast(1L)).toInt().coerceIn(0, units.size)
        val sb = StringBuilder()
        for (i in 0 until k) {
            if (i > 0 && needSpaceBetween(units[i - 1], units[i])) sb.append(' ')
            sb.append(units[i])
        }
        return sb.toString()
    }

    /** Append an Auto-✨ emoji to the end of a line (for the non-karaoke path). */
    private fun appendEmoji(text: String, emoji: String?): String =
        if (emoji.isNullOrEmpty()) text else "$text $emoji"

    private fun needSpaceBetween(prev: String, cur: String): Boolean {
        if (prev.isEmpty() || cur.isEmpty()) return false
        return isAsciiWordChar(prev.last()) || isAsciiWordChar(cur.first())
    }

    // ─── Resolve URI ──────────────────────────────────────────────────────────

    private fun resolveVideoPath(videoPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                val resolved = resolveUriToFilePath(videoPath)
                runOnUiThread { result.success(resolved) }
            } catch (e: Exception) {
                runOnUiThread { result.error("FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    private fun resolveUriToFilePath(videoPath: String): String {
        return when {
            videoPath.startsWith("file://") ->
                Uri.parse(videoPath).path ?: videoPath.removePrefix("file://")
            videoPath.startsWith("content://") -> {
                val uri = Uri.parse(videoPath)
                val tmpFile = File(cacheDir, "input_${System.currentTimeMillis()}.mp4")
                contentResolver.openInputStream(uri)?.use { input ->
                    tmpFile.outputStream().use { output -> input.copyTo(output) }
                } ?: throw Exception("Cannot open content URI")
                tmpFile.absolutePath
            }
            else -> videoPath
        }
    }

    /** Report export progress (0..1) to Dart, throttled to whole-percent changes. */
    private fun emitProgress(frac: Double) {
        val pct = (frac.coerceIn(0.0, 1.0) * 100).toInt()
        if (pct == lastEmittedPct) return
        lastEmittedPct = pct
        runOnUiThread { methodChannel?.invokeMethod("exportProgress", frac) }
    }

    // ─── Burn Subtitles ──────────────────────────────────────────────────────
    // Dispatcher: try the fast GPU (OpenGL) pipeline; on any failure (e.g. an
    // emulator/device without surface-encoder or GL support) fall back to the
    // proven CPU pipeline so export never breaks.

    private fun burnSubtitles(
        videoPath: String,
        outputPath: String,
        fileName: String,
        segmentsRaw: List<Map<String, Any>>,
        styleMap: Map<String, Any>,
        autoCut: Boolean,
        returnTempPath: Boolean,
        keptRegionsMsFlat: List<Int>?,
        imageOverlaysRaw: List<Map<String, Any>>?,
        zoomEffectsRaw: List<Map<String, Any>>?,
        fadeEffectsRaw: List<Map<String, Any>>?,
        shakeEffectsRaw: List<Map<String, Any>>?,
        blurBgArg: Boolean,
        autoCutGapMs: Long,
        result: MethodChannel.Result,
    ) {
        // Decode image overlays once (downsampled near display width).
        imageOverlays = parseImageOverlays(imageOverlaysRaw)
        zoomEffects = parseZoomEffects(zoomEffectsRaw)
        fadeEffects = parseFadeEffects(fadeEffectsRaw)
        shakeEffects = parseShakeEffects(shakeEffectsRaw)
        blurBg = blurBgArg
        // Manual video cuts: flat [start,end,...] ms → list of (startUs,endUs).
        val manualKept: List<Pair<Long, Long>>? =
            if (keptRegionsMsFlat != null && keptRegionsMsFlat.size >= 2) {
                val list = ArrayList<Pair<Long, Long>>()
                var i = 0
                while (i + 1 < keptRegionsMsFlat.size) {
                    list.add(Pair(keptRegionsMsFlat[i].toLong() * 1000L,
                                  keptRegionsMsFlat[i + 1].toLong() * 1000L))
                    i += 2
                }
                list
            } else null

        Thread {
            try {
                lastEmittedPct = -1
                val effectivePath = resolveUriToFilePath(videoPath)

                // Peek video dimensions/rotation to build the subtitle provider.
                val peek = MediaExtractor()
                peek.setDataSource(effectivePath)
                var vIdx = -1
                for (i in 0 until peek.trackCount) {
                    if ((peek.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: "").startsWith("video/")) {
                        vIdx = i; break
                    }
                }
                if (vIdx == -1) { peek.release(); throw RuntimeException("no video track") }
                val vf = peek.getTrackFormat(vIdx)
                val vidW = vf.getInteger(MediaFormat.KEY_WIDTH)
                val vidH = vf.getInteger(MediaFormat.KEY_HEIGHT)
                val formatRotation = if (vf.containsKey("rotation-degrees")) vf.getInteger("rotation-degrees") else 0
                peek.release()
                val rotation = readRotation(effectivePath, formatRotation)

                // Manual cuts take precedence; otherwise compute silence-cut
                // regions when Auto-Cut is enabled.
                val keptRegions = manualKept ?: if (autoCut) {
                    val energies = decodeEnergies(effectivePath)
                    val rawRegions = computeRegions(energies, vadFrameMs)
                    val keptRegionsMs = ArrayList<Pair<Long, Long>>()
                    if (rawRegions.isNotEmpty()) {
                        var curStart = rawRegions[0][0].toLong()
                        var curEnd = rawRegions[0][1].toLong()
                        for (i in 1 until rawRegions.size) {
                            val rStart = rawRegions[i][0].toLong()
                            val rEnd = rawRegions[i][1].toLong()
                            if (rStart - curEnd <= autoCutGapMs) {
                                curEnd = rEnd
                            } else {
                                keptRegionsMs.add(Pair(curStart, curEnd))
                                curStart = rStart
                                curEnd = rEnd
                            }
                        }
                        keptRegionsMs.add(Pair(curStart, curEnd))
                    }
                    keptRegionsMs.map { Pair(it.first * 1000L, it.second * 1000L) }
                } else {
                    null
                }

                // Portrait/rotated videos: the GPU path's SurfaceTexture transform
                // handles rotation differently across devices, which can clash with
                // the muxer orientation hint and tilt the output. The CPU pipeline
                // decodes raw frames + sets the hint deterministically, so it's
                // reliable for rotation — use it whenever the source is rotated.
                // Image overlays, zoom/Ken-Burns and fade transitions are
                // composited only in the CPU path, so route there too whenever
                // any of them exist (the GPU path doesn't apply these effects).
                if (rotation != 0 || imageOverlays.isNotEmpty() ||
                    zoomEffects.isNotEmpty() || fadeEffects.isNotEmpty() ||
                    shakeEffects.isNotEmpty() || blurBg) {
                    burnSubtitlesCpu(videoPath, outputPath, fileName, segmentsRaw, styleMap, keptRegions, returnTempPath, result)
                    return@Thread
                }

                val provider = makeSubtitleProvider(segmentsRaw, styleMap, vidW, vidH, rotation)
                VideoExporterGl().export(effectivePath, outputPath, { p -> emitProgress(p) }, provider, keptRegions)

                emitProgress(0.96)
                if (!returnTempPath) {
                    saveVideoToGallery(outputPath, fileName)
                }
                emitProgress(1.0)
                runOnUiThread { result.success(if (returnTempPath) outputPath else "Movies/SubtitleAI/$fileName") }
            } catch (e: Throwable) {
                // GPU path unsupported/failed → fall back to CPU pipeline.
                try { File(outputPath).delete() } catch (_: Exception) {}
                // Re-evaluate path with kept regions
                val effectivePath = resolveUriToFilePath(videoPath)
                val keptRegions = manualKept ?: if (autoCut) {
                    try {
                        val energies = decodeEnergies(effectivePath)
                        val rawRegions = computeRegions(energies, vadFrameMs)
                        val keptRegionsMs = ArrayList<Pair<Long, Long>>()
                        if (rawRegions.isNotEmpty()) {
                            var curStart = rawRegions[0][0].toLong()
                            var curEnd = rawRegions[0][1].toLong()
                            for (i in 1 until rawRegions.size) {
                                val rStart = rawRegions[i][0].toLong()
                                val rEnd = rawRegions[i][1].toLong()
                                if (rStart - curEnd <= autoCutGapMs) {
                                    curEnd = rEnd
                                } else {
                                    keptRegionsMs.add(Pair(curStart, curEnd))
                                    curStart = rStart
                                    curEnd = rEnd
                                }
                            }
                            keptRegionsMs.add(Pair(curStart, curEnd))
                        }
                        keptRegionsMs.map { Pair(it.first * 1000L, it.second * 1000L) }
                    } catch (_: Exception) { null }
                } else {
                    null
                }
                burnSubtitlesCpu(videoPath, outputPath, fileName, segmentsRaw, styleMap, keptRegions, returnTempPath, result)
            }
        }.start()
    }

    /**
     * Build a provider that returns the subtitle overlay bitmap (full-frame,
     * transparent background) for a given presentation time — or null when no
     * subtitle is active. Reuses the same parsing/rendering as the CPU path.
     */
    private fun makeSubtitleProvider(
        segmentsRaw: List<Map<String, Any>>,
        styleMap: Map<String, Any>,
        vidW: Int,
        vidH: Int,
        rotation: Int,
    ): (Long) -> Bitmap? {
        val segments = segmentsRaw.map { raw ->
            @Suppress("UNCHECKED_CAST")
            val wordsList = (raw["words"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            @Suppress("UNCHECKED_CAST")
            val timingMs = (raw["wordTimingsMs"] as? List<*>)?.mapNotNull { v -> (v as? Number)?.toLong() }
            @Suppress("UNCHECKED_CAST")
            Seg(
                startUs        = (raw["startMs"] as Number).toLong() * 1_000L,
                endUs          = (raw["endMs"]   as Number).toLong() * 1_000L,
                text           = raw["text"] as String,
                translatedText = raw["translatedText"] as? String,
                words          = wordsList,
                wordTimingsUs  = timingMs?.map { ms -> ms * 1_000L },
                styleOverride  = raw["style"] as? Map<String, Any?>,
                emphasis       = (raw["emphasis"] as? List<*>)?.mapNotNull { v -> (v as? Number)?.toInt() } ?: emptyList(),
                emoji          = raw["emoji"] as? String,
            )
        }

        val textColorInt       = (styleMap["textColor"]    as? Long)?.toInt() ?: Color.WHITE
        val bgColorInt         = (styleMap["bgColor"]      as? Long)?.toInt()
        val karaokeColor       = (styleMap["karaokeColor"] as? Long)?.toInt()
        val karaokeScale       = styleMap["karaokeScale"] as? Boolean ?: false
        val emphasisColorInt   = (styleMap["emphasisColor"] as? Long)?.toInt()
        val hasShadow          = styleMap["hasShadow"]  as? Boolean ?: false
        val has3dShadow        = styleMap["has3dShadow"] as? Boolean ?: false
        val hasOutline         = styleMap["hasOutline"] as? Boolean ?: false
        val outlineColor       = (styleMap["outlineColor"] as? Long)?.toInt()
        val gradientColors     = (styleMap["gradientColors"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }?.toIntArray()
        val hasNeonGlow        = styleMap["hasNeonGlow"] as? Boolean ?: false
        val glowColor          = (styleMap["glowColor"]  as? Long)?.toInt()
        val hasUnderline       = styleMap["hasUnderline"] as? Boolean ?: false
        val underlineColor     = (styleMap["underlineColor"] as? Long)?.toInt()
        val fontWeight         = (styleMap["fontWeight"] as? Number)?.toInt() ?: 600
        val fontSize           = (styleMap["fontSize"]   as? Double)?.toFloat() ?: 18f
        val positionY          = (styleMap["positionY"]  as? Double)?.toFloat() ?: 0.85f
        val positionX          = (styleMap["positionX"]  as? Double)?.toFloat() ?: 0.5f
        val rotationDeg        = (styleMap["rotation"]   as? Double)?.toFloat() ?: 0f
        val fontPath           = styleMap["fontPath"]   as? String
        val animationType      = styleMap["animationType"] as? String ?: "none"
        val animInMs           = (styleMap["animInMs"] as? Number)?.toLong() ?: 350L
        val animOutType        = styleMap["animOutType"] as? String ?: "none"
        val typeUnitMs         = (styleMap["typeUnitMs"] as? Number)?.toLong() ?: 55L
        val bilingualTextColor = (styleMap["bilingualTextColor"]  as? Long)?.toInt()
        val bilingualBgColor   = (styleMap["bilingualBgColor"]    as? Long)?.toInt()
        val bilingualHasShadow = styleMap["bilingualHasShadow"]  as? Boolean ?: false
        val bilingualIsBold    = styleMap["bilingualIsBold"]     as? Boolean ?: false
        val bilingualFontSize  = (styleMap["bilingualFontSize"]   as? Double)?.toFloat()
        val bilingualGlowColor = (styleMap["bilingualGlowColor"] as? Long)?.toInt()
        val bilingualHasNeon   = styleMap["bilingualHasNeonGlow"] as? Boolean ?: false
        val bilingualGap       = (styleMap["bilingualGap"]        as? Double)?.toFloat() ?: 4f

        val displayH = if (rotation == 90 || rotation == 270) vidW else vidH
        val displayW = if (rotation == 90 || rotation == 270) vidH else vidW
        val w = fontWeight.coerceIn(100, 900)
        val fontFile = if (fontPath != null && File(fontPath).exists()) File(fontPath) else null
        val baseTypeface: Typeface =
            if (fontFile != null) Typeface.createFromFile(fontFile) else Typeface.DEFAULT
        val subTypeface: Typeface = run {
            if (fontFile != null && Build.VERSION.SDK_INT >= 26) {
                try {
                    Typeface.Builder(fontFile)
                        .setFontVariationSettings("'wght' ${w.toFloat()}")
                        .setWeight(w)
                        .build() ?: Typeface.create(baseTypeface, w, false)
                } catch (e: Exception) {
                    if (Build.VERSION.SDK_INT >= 28) Typeface.create(baseTypeface, w, false)
                    else if (w >= 600) Typeface.create(baseTypeface, Typeface.BOLD) else baseTypeface
                }
            } else if (Build.VERSION.SDK_INT >= 28) {
                Typeface.create(baseTypeface, w, false)
            } else {
                if (w >= 600) Typeface.create(baseTypeface, Typeface.BOLD) else baseTypeface
            }
        }

        val watermarkText      = styleMap["watermarkText"] as? String
        val watermarkPosition  = styleMap["watermarkPosition"] as? String ?: "top"
        val watermarkLogo      = (styleMap["watermarkLogoPath"] as? String)?.let { lp ->
            decodeScaledLogo(lp, vidW)
        }

        val style = RenderStyle(
            textColor           = textColorInt,
            bgColor             = bgColorInt,
            karaokeColor        = karaokeColor,
            karaokeScale        = karaokeScale,
            emphasisColor       = emphasisColorInt,
            hasShadow           = hasShadow,
            has3dShadow         = has3dShadow,
            hasOutline          = hasOutline,
            outlineColor        = outlineColor,
            gradientColors      = gradientColors,
            hasNeonGlow         = hasNeonGlow,
            glowColor           = glowColor,
            hasUnderline        = hasUnderline,
            underlineColor      = underlineColor,
            typeface            = subTypeface,
            scaledTextSize      = fontSize * displayH / 220f,
            positionY           = positionY,
            positionX           = positionX,
            rotation            = rotationDeg,
            animationType       = animationType,
            bilingualTextColor  = bilingualTextColor,
            bilingualBgColor    = bilingualBgColor,
            bilingualHasShadow  = bilingualHasShadow,
            bilingualIsBold     = bilingualIsBold,
            scaledBilingualSize = (bilingualFontSize ?: (fontSize * 0.75f)) * displayH / 220f,
            bilingualHasNeon    = bilingualHasNeon,
            bilingualGlowColor  = bilingualGlowColor,
            bilingualGap        = bilingualGap * displayH / 220f,
            watermarkText       = watermarkText,
            watermarkPosition   = watermarkPosition,
            watermarkLogo       = watermarkLogo,
        )

        // Persistent watermark overlay (free tier) — drawn on EVERY frame,
        // including those with no active subtitle. Rendered upright at display
        // dims, then rotated to the raw encoded orientation.
        val watermarkBmp: Bitmap? =
            makeWatermarkBitmap(displayW, displayH, style)?.let { orientOverlay(it, rotation) }

        var prevSubKey = ""
        var cachedSubBmp: Bitmap? = null
        return provider@{ presentUs ->
            val activeSeg = segments.firstOrNull { s -> s.startUs <= presentUs && presentUs < s.endUs }
                ?: return@provider watermarkBmp
            val es = effectiveStyle(activeSeg, style, displayH)
            val isType = es.animationType == "typewriter"
            val animDurUs = animInMs * 1000L
            val elapsed = (presentUs - activeSeg.startUs).coerceAtLeast(0L)
            val remaining = (activeSeg.endUs - presentUs).coerceAtLeast(0L)
            val exitWin = animOutType != "none" && remaining < animDurUs
            val inAnim = !isType && !exitWin && es.animationType != "none" && elapsed < animDurUs
            val animT = when {
                exitWin -> (remaining.toFloat() / animDurUs).coerceIn(0f, 1f)
                inAnim -> (elapsed.toFloat() / animDurUs).coerceIn(0f, 1f)
                else -> 1f
            }
            val sweepOn = es.karaokeColor != null && activeSeg.words.size >= 2
            val hasEmph = activeSeg.emphasis.isNotEmpty()
            val useKaraoke = !isType && activeSeg.words.isNotEmpty() && (sweepOn || hasEmph)
            // Only the karaoke sweep advances per word; ✨ emphasis is static.
            val activeWordIdx = if (sweepOn) computeActiveWordIdx(activeSeg, presentUs) else -1
            val shownText = if (isType) revealedText(activeSeg, elapsed, typeUnitMs) else activeSeg.text
            val subKey = when {
                exitWin -> "${activeSeg.startUs}|x|${remaining / 16_000L}"
                isType -> "${activeSeg.startUs}|${shownText.length}"
                inAnim -> "${activeSeg.startUs}|${activeSeg.text}|${activeSeg.translatedText}|${elapsed / 16_000L}"
                else -> "${activeSeg.startUs}|${activeSeg.text}|${activeSeg.translatedText}|$activeWordIdx"
            }
            if (subKey != prevSubKey) {
                cachedSubBmp?.recycle()
                val drawStyle = if (exitWin) es.copy(animationType = animOutType) else es
                val upright = if (useKaraoke) {
                    makeKaraokeBitmap(activeSeg.text, activeSeg.words, activeWordIdx,
                        activeSeg.translatedText, animT, displayW, displayH, drawStyle, exitWin,
                        activeSeg.emphasis, sweepOn, activeSeg.emoji)
                } else {
                    makeNormalBitmap(appendEmoji(shownText, activeSeg.emoji), activeSeg.translatedText, animT, displayW, displayH, drawStyle, exitWin)
                }
                cachedSubBmp = orientOverlay(upright, rotation)
                prevSubKey = subKey
            }
            cachedSubBmp
        }
    }

    // ─── Burn Subtitles — CPU fallback (MediaCodec + MediaMuxer) ──────────────

    private fun burnSubtitlesCpu(
        videoPath: String,
        outputPath: String,
        fileName: String,
        segmentsRaw: List<Map<String, Any>>,
        styleMap: Map<String, Any>,
        keptRegions: List<Pair<Long, Long>>?,
        returnTempPath: Boolean,
        result: MethodChannel.Result,
    ) {
        val segments = segmentsRaw.map { raw ->
            @Suppress("UNCHECKED_CAST")
            val wordsList = (raw["words"] as? List<*>)?.filterIsInstance<String>() ?: emptyList()
            @Suppress("UNCHECKED_CAST")
            val timingMs = (raw["wordTimingsMs"] as? List<*>)?.mapNotNull { v -> (v as? Number)?.toLong() }
            @Suppress("UNCHECKED_CAST")
            Seg(
                startUs        = (raw["startMs"] as Number).toLong() * 1_000L,
                endUs          = (raw["endMs"]   as Number).toLong() * 1_000L,
                text           = raw["text"] as String,
                translatedText = raw["translatedText"] as? String,
                words          = wordsList,
                wordTimingsUs  = timingMs?.map { ms -> ms * 1_000L },
                styleOverride  = raw["style"] as? Map<String, Any?>,
                emphasis       = (raw["emphasis"] as? List<*>)?.mapNotNull { v -> (v as? Number)?.toInt() } ?: emptyList(),
                emoji          = raw["emoji"] as? String,
            )
        }

        val textColorInt      = (styleMap["textColor"]    as? Long)?.toInt() ?: Color.WHITE
        val bgColorInt        = (styleMap["bgColor"]      as? Long)?.toInt()
        val karaokeColor      = (styleMap["karaokeColor"] as? Long)?.toInt()
        val karaokeScale      = styleMap["karaokeScale"] as? Boolean ?: false
        val emphasisColorInt2 = (styleMap["emphasisColor"] as? Long)?.toInt()
        val hasShadow         = styleMap["hasShadow"]  as? Boolean ?: false
        val has3dShadow       = styleMap["has3dShadow"] as? Boolean ?: false
        val hasOutline        = styleMap["hasOutline"] as? Boolean ?: false
        val outlineColor      = (styleMap["outlineColor"] as? Long)?.toInt()
        val gradientColors    = (styleMap["gradientColors"] as? List<*>)?.mapNotNull { (it as? Number)?.toInt() }?.toIntArray()
        val hasNeonGlow       = styleMap["hasNeonGlow"] as? Boolean ?: false
        val glowColor         = (styleMap["glowColor"]  as? Long)?.toInt()
        val hasUnderline      = styleMap["hasUnderline"] as? Boolean ?: false
        val underlineColor    = (styleMap["underlineColor"] as? Long)?.toInt()
        val isBold            = styleMap["isBold"]     as? Boolean ?: false
        val fontWeight        = (styleMap["fontWeight"] as? Number)?.toInt() ?: 600
        val fontSize          = (styleMap["fontSize"]   as? Double)?.toFloat() ?: 18f
        val positionY         = (styleMap["positionY"]  as? Double)?.toFloat() ?: 0.85f
        val positionX         = (styleMap["positionX"]  as? Double)?.toFloat() ?: 0.5f
        val rotationDeg       = (styleMap["rotation"]   as? Double)?.toFloat() ?: 0f
        val fontPath          = styleMap["fontPath"]   as? String
        val animationType     = styleMap["animationType"] as? String ?: "none"
        val animInMs          = (styleMap["animInMs"] as? Number)?.toLong() ?: 350L
        val animOutType       = styleMap["animOutType"] as? String ?: "none"
        val typeUnitMs        = (styleMap["typeUnitMs"] as? Number)?.toLong() ?: 55L
        val bilingualTextColor = (styleMap["bilingualTextColor"]  as? Long)?.toInt()
        val bilingualBgColor  = (styleMap["bilingualBgColor"]    as? Long)?.toInt()
        val bilingualHasShadow = styleMap["bilingualHasShadow"]  as? Boolean ?: false
        val bilingualIsBold   = styleMap["bilingualIsBold"]     as? Boolean ?: false
        val bilingualFontSize = (styleMap["bilingualFontSize"]   as? Double)?.toFloat()
        val bilingualGlowColor = (styleMap["bilingualGlowColor"] as? Long)?.toInt()
        val bilingualHasNeon  = styleMap["bilingualHasNeonGlow"] as? Boolean ?: false
        val bilingualGap      = (styleMap["bilingualGap"]        as? Double)?.toFloat() ?: 4f

        Thread {
            var extractor: MediaExtractor? = null
            var decoder: MediaCodec? = null
            var encoder: MediaCodec? = null
            var muxer: MediaMuxer? = null
            var audioExtractor: MediaExtractor? = null

            try {
                // Resolve video URI to file path for decoding and audio passthrough
                val effectiveVideoPath = resolveUriToFilePath(videoPath)

                extractor = MediaExtractor()
                extractor.setDataSource(effectiveVideoPath)

                var videoTrackIdx = -1
                var audioTrackIdx = -1
                for (i in 0 until extractor.trackCount) {
                    val fmt  = extractor.getTrackFormat(i)
                    val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/") && videoTrackIdx == -1) videoTrackIdx = i
                    if (mime.startsWith("audio/") && audioTrackIdx == -1) audioTrackIdx = i
                }
                if (videoTrackIdx == -1) throw Exception("No video track found")

                val videoFormat = extractor.getTrackFormat(videoTrackIdx)
                val vidW      = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
                val vidH      = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
                val formatRotation = if (videoFormat.containsKey("rotation-degrees"))
                    videoFormat.getInteger("rotation-degrees") else 0
                val rotation  = readRotation(effectiveVideoPath, formatRotation)
                val frameRate = if (videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE))
                    videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE) else 30
                val bitRate   = if (videoFormat.containsKey(MediaFormat.KEY_BIT_RATE))
                    videoFormat.getInteger(MediaFormat.KEY_BIT_RATE) else 4_000_000
                val durationUs = if (videoFormat.containsKey(MediaFormat.KEY_DURATION))
                    videoFormat.getLong(MediaFormat.KEY_DURATION) else 0L

                lastEmittedPct = -1
                // Output in DISPLAY orientation so all players show it correctly
                // (no orientation-hint needed — frames are physically rotated).
                val displayH = if (rotation == 90 || rotation == 270) vidW else vidH
                val displayW = if (rotation == 90 || rotation == 270) vidH else vidW
                // With blurred background, output a 9:16 portrait canvas; the video
                // is fit-centered and a blurred copy fills the rest. Otherwise keep
                // the video's own dimensions.
                val outW: Int
                val outH: Int
                if (blurBg) {
                    val longSide = maxOf(displayW, displayH)
                    outH = (longSide / 2) * 2
                    outW = ((longSide * 9 / 16) / 2) * 2
                } else {
                    outW = displayW
                    outH = displayH
                }

                val w = fontWeight.coerceIn(100, 900)
                val fontFile = if (fontPath != null && File(fontPath).exists()) File(fontPath) else null
                val baseTypeface: Typeface =
                    if (fontFile != null) Typeface.createFromFile(fontFile) else Typeface.DEFAULT
                val subTypeface: Typeface = run {
                    // Variable fonts: set the real 'wght' axis (Typeface.create(weight)
                    // alone does NOT apply the variation axis → bold looked thin).
                    if (fontFile != null && Build.VERSION.SDK_INT >= 26) {
                        try {
                            Typeface.Builder(fontFile)
                                .setFontVariationSettings("'wght' ${w.toFloat()}")
                                .setWeight(w)
                                .build() ?: Typeface.create(baseTypeface, w, false)
                        } catch (e: Exception) {
                            if (Build.VERSION.SDK_INT >= 28) Typeface.create(baseTypeface, w, false)
                            else if (w >= 600) Typeface.create(baseTypeface, Typeface.BOLD) else baseTypeface
                        }
                    } else if (Build.VERSION.SDK_INT >= 28) {
                        Typeface.create(baseTypeface, w, false)
                    } else {
                        if (w >= 600) Typeface.create(baseTypeface, Typeface.BOLD) else baseTypeface
                    }
                }

                val style = RenderStyle(
                    textColor           = textColorInt,
                    bgColor             = bgColorInt,
                    karaokeColor        = karaokeColor,
                    karaokeScale        = karaokeScale,
                    emphasisColor       = emphasisColorInt2,
                    hasShadow           = hasShadow,
            has3dShadow         = has3dShadow,
            hasOutline          = hasOutline,
            outlineColor        = outlineColor,
            gradientColors      = gradientColors,
                    hasNeonGlow         = hasNeonGlow,
                    glowColor           = glowColor,
                    hasUnderline        = hasUnderline,
                    underlineColor      = underlineColor,
                    typeface            = subTypeface,
                    scaledTextSize      = fontSize * outH / 220f,
                    positionY           = positionY,
                    positionX           = positionX,
                    rotation            = rotationDeg,
                    animationType       = animationType,
                    bilingualTextColor  = bilingualTextColor,
                    bilingualBgColor    = bilingualBgColor,
                    bilingualHasShadow  = bilingualHasShadow,
                    bilingualIsBold     = bilingualIsBold,
                    scaledBilingualSize = (bilingualFontSize ?: (fontSize * 0.75f)) * outH / 220f,
                    bilingualHasNeon    = bilingualHasNeon,
                    bilingualGlowColor  = bilingualGlowColor,
                    bilingualGap        = bilingualGap * outH / 220f,
                    watermarkText       = styleMap["watermarkText"] as? String,
                    watermarkPosition   = styleMap["watermarkPosition"] as? String ?: "top",
                    watermarkLogo       = (styleMap["watermarkLogoPath"] as? String)?.let { lp ->
                        decodeScaledLogo(lp, vidW)
                    },
                )

                // Watermark rendered at display (output) dims — no rotation needed
                // because frames are already physically rotated before compositing.
                val watermarkBmp: Bitmap? = makeWatermarkBitmap(outW, outH, style)

                // ── Decoder ──
                decoder = MediaCodec.createDecoderByType(videoFormat.getString(MediaFormat.KEY_MIME)!!)
                decoder.configure(videoFormat, null, null, 0)
                decoder.start()

                // ── Encoder (query a color format we can actually fill) ──
                encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
                val encColorFormats = encoder.codecInfo
                    .getCapabilitiesForType(MediaFormat.MIMETYPE_VIDEO_AVC).colorFormats
                val semiPlanar = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420SemiPlanar
                val planar     = MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Planar
                val chosenColor = when {
                    encColorFormats.contains(semiPlanar) -> semiPlanar
                    encColorFormats.contains(planar)     -> planar
                    else -> MediaCodecInfo.CodecCapabilities.COLOR_FormatYUV420Flexible
                }
                // Encode at display (output) dimensions — frames are rotated before encoding.
                val encFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, outW, outH).apply {
                    setInteger(MediaFormat.KEY_COLOR_FORMAT, chosenColor)
                    setInteger(MediaFormat.KEY_BIT_RATE,     bitRate.coerceIn(1_000_000, 12_000_000))
                    setInteger(MediaFormat.KEY_FRAME_RATE,   frameRate)
                    setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
                }
                encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                encoder.start()

                // ── MediaMuxer + audio passthrough (no audio re-encode) ──
                muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                // No setOrientationHint — frames are physically in display orientation.
                var audioFormatForMux: MediaFormat? = null
                if (audioTrackIdx != -1) {
                    try {
                        audioExtractor = MediaExtractor()
                        audioExtractor.setDataSource(effectiveVideoPath)
                        audioExtractor.selectTrack(audioTrackIdx)
                        audioFormatForMux = audioExtractor.getTrackFormat(audioTrackIdx)
                    } catch (_: Exception) {
                        try { audioExtractor?.release() } catch (_: Exception) {}
                        audioExtractor = null
                    }
                }
                var muxerVideoTrack = -1
                var muxerAudioTrack = -1
                var muxerStarted    = false
                val frameSize       = outW * outH * 3 / 2

                extractor.selectTrack(videoTrackIdx)

                var inputDone         = false
                var encoderDone       = false
                var prevSubKey        = ""
                var cachedSubBmp: Bitmap? = null
                var encodedFrameCount = 0L
                val ptsStepUs         = 1_000_000L / frameRate.toLong()

                while (!encoderDone) {
                    // 1. Feed decoder
                    if (!inputDone) {
                        val inIdx = decoder.dequeueInputBuffer(10_000L)
                        if (inIdx >= 0) {
                            val buf = decoder.getInputBuffer(inIdx)!!
                            val sz  = extractor.readSampleData(buf, 0)
                            if (sz < 0) {
                                decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputDone = true
                            } else {
                                decoder.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0)
                                extractor.advance()
                            }
                        }
                    }

                    // 2. Get decoded frame → draw subtitle → feed encoder
                    val decInfo   = MediaCodec.BufferInfo()
                    val decOutIdx = decoder.dequeueOutputBuffer(decInfo, 10_000L)
                    if (decOutIdx >= 0) {
                        val presentUs = decInfo.presentationTimeUs
                        val isEos     = decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0

                        val keepFrame = keptRegions == null || keptRegions.isEmpty() || keptRegions.any { presentUs >= it.first && presentUs <= it.second }

                        if (durationUs > 0L && decInfo.size > 0 && keepFrame) {
                            val frac = (presentUs.toDouble() / durationUs).coerceIn(0.0, 1.0)
                            emitProgress(0.10 + frac * 0.82) // 10%..92% during encoding
                        }

                        if (decInfo.size > 0) {
                            if (!keepFrame) {
                                decoder.releaseOutputBuffer(decOutIdx, false)
                                if (isEos) {
                                    val encInIdx = encoder.dequeueInputBuffer(10_000L)
                                    if (encInIdx >= 0) {
                                        val eosPts = encodedFrameCount * ptsStepUs
                                        encoder.queueInputBuffer(encInIdx, 0, 0, eosPts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                    }
                                }
                                continue
                            }
                            val image = decoder.getOutputImage(decOutIdx)
                            val rawBmp: Bitmap = when {
                                image != null -> { val b = imageToBitmap(image); image.close(); b }
                                else -> {
                                    val buf = decoder.getOutputBuffer(decOutIdx)
                                    bufferToBitmap(buf, decoder.outputFormat, vidW, vidH)
                                        ?: Bitmap.createBitmap(vidW, vidH, Bitmap.Config.ARGB_8888)
                                }
                            }
                            decoder.releaseOutputBuffer(decOutIdx, false)

                            // Physically rotate frame to display orientation — works on all players.
                            var frameBmp: Bitmap = if (rotation != 0) {
                                val m = android.graphics.Matrix().apply { postRotate(rotation.toFloat()) }
                                val r = Bitmap.createBitmap(rawBmp, 0, 0, rawBmp.width, rawBmp.height, m, true)
                                rawBmp.recycle(); r
                            } else rawBmp

                            // Zoom / Ken-Burns on the video frame (under overlays + subtitle).
                            if (zoomEffects.isNotEmpty()) {
                                val zoomed = applyZoom(frameBmp, presentUs)
                                if (zoomed !== frameBmp) { frameBmp.recycle(); frameBmp = zoomed }
                            }
                            // Camera shake (after zoom, still under overlays + subtitle).
                            if (shakeEffects.isNotEmpty()) {
                                val shaken = applyShake(frameBmp, presentUs)
                                if (shaken !== frameBmp) { frameBmp.recycle(); frameBmp = shaken }
                            }

                            // Blurred background: fit the (zoomed/shaken) video into the
                            // 9:16 output canvas with a blurred fill. frameBmp → outW×outH.
                            if (blurBg) {
                                val composed = blurBgCompose(frameBmp, outW, outH)
                                frameBmp.recycle(); frameBmp = composed
                            }

                            // Image overlays sit UNDER the subtitle/watermark text.
                            if (imageOverlays.isNotEmpty()) {
                                drawImageOverlays(Canvas(frameBmp), presentUs, outW, outH)
                            }

                            val activeSeg = segments.firstOrNull { s -> s.startUs <= presentUs && presentUs < s.endUs }
                            if (activeSeg != null) {
                                val es         = effectiveStyle(activeSeg, style, outH)
                                val isType     = es.animationType == "typewriter"
                                val animDurUs  = animInMs * 1000L
                                val elapsed    = (presentUs - activeSeg.startUs).coerceAtLeast(0L)
                                val remaining  = (activeSeg.endUs - presentUs).coerceAtLeast(0L)
                                val exitWin    = animOutType != "none" && remaining < animDurUs
                                val inAnim     = !isType && !exitWin && es.animationType != "none" && elapsed < animDurUs
                                val animT      = when {
                                    exitWin -> (remaining.toFloat() / animDurUs).coerceIn(0f, 1f)
                                    inAnim  -> (elapsed.toFloat() / animDurUs).coerceIn(0f, 1f)
                                    else    -> 1f
                                }
                                val sweepOn    = es.karaokeColor != null && activeSeg.words.size >= 2
                                val hasEmph    = activeSeg.emphasis.isNotEmpty()
                                val useKaraoke = !isType && activeSeg.words.isNotEmpty() && (sweepOn || hasEmph)
                                val activeWordIdx = if (sweepOn) computeActiveWordIdx(activeSeg, presentUs) else -1
                                val shownText  = if (isType) revealedText(activeSeg, elapsed, typeUnitMs) else activeSeg.text
                                val subKey     = when {
                                    exitWin -> "${activeSeg.startUs}|x|${remaining / 16_000L}"
                                    isType -> "${activeSeg.startUs}|${shownText.length}"
                                    inAnim -> "${activeSeg.startUs}|${activeSeg.text}|${activeSeg.translatedText}|${elapsed / 16_000L}"
                                    else -> "${activeSeg.startUs}|${activeSeg.text}|${activeSeg.translatedText}|$activeWordIdx"
                                }

                                if (subKey != prevSubKey) {
                                    cachedSubBmp?.recycle()
                                    val drawStyle = if (exitWin) es.copy(animationType = animOutType) else es
                                    // Subtitle rendered in display orientation — no orientOverlay needed.
                                    cachedSubBmp = if (useKaraoke) {
                                        makeKaraokeBitmap(activeSeg.text, activeSeg.words, activeWordIdx,
                                            activeSeg.translatedText, animT, outW, outH, drawStyle, exitWin,
                                            activeSeg.emphasis, sweepOn, activeSeg.emoji)
                                    } else {
                                        makeNormalBitmap(appendEmoji(shownText, activeSeg.emoji), activeSeg.translatedText,
                                            animT, outW, outH, drawStyle, exitWin)
                                    }
                                    prevSubKey = subKey
                                }
                                cachedSubBmp?.let { Canvas(frameBmp).drawBitmap(it, 0f, 0f, null) }
                            } else {
                                watermarkBmp?.let { Canvas(frameBmp).drawBitmap(it, 0f, 0f, null) }
                            }

                            // Fade transition: black overlay over the whole frame (incl. subtitle).
                            if (fadeEffects.isNotEmpty()) {
                                val fa = fadeAlphaAt(presentUs)
                                if (fa > 0) Canvas(frameBmp).drawARGB(fa, 0, 0, 0)
                            }

                            val encInIdx = encoder.dequeueInputBuffer(10_000L)
                            if (encInIdx >= 0) {
                                val framePtsUs = encodedFrameCount * ptsStepUs
                                encodedFrameCount++
                                val encBuf = encoder.getInputBuffer(encInIdx)!!
                                encBuf.clear()
                                val byteCount = when (chosenColor) {
                                    semiPlanar -> bitmapToYuv(frameBmp, encBuf, outW, outH, true)
                                    planar     -> bitmapToYuv(frameBmp, encBuf, outW, outH, false)
                                    else -> {
                                        val encImg = encoder.getInputImage(encInIdx)
                                        if (encImg != null) {
                                            bitmapToImage(frameBmp, encImg); encImg.close(); frameSize
                                        } else {
                                            bitmapToYuv(frameBmp, encBuf, outW, outH, false)
                                        }
                                    }
                                }
                                encoder.queueInputBuffer(encInIdx, 0, byteCount, framePtsUs, 0)
                            }
                            frameBmp.recycle()
                        } else {
                            decoder.releaseOutputBuffer(decOutIdx, false)
                        }

                        if (isEos) {
                            val encInIdx = encoder.dequeueInputBuffer(10_000L)
                            if (encInIdx >= 0) {
                                val eosPts = encodedFrameCount * ptsStepUs
                                encoder.queueInputBuffer(encInIdx, 0, 0, eosPts, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            }
                        }
                    }

                    // 3. Drain encoder → MediaMuxer
                    val encInfo  = MediaCodec.BufferInfo()
                    var draining = true
                    while (draining) {
                        val encOutIdx = encoder.dequeueOutputBuffer(encInfo, 0)
                        when {
                            encOutIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED -> {
                                muxerVideoTrack = muxer.addTrack(encoder.outputFormat)
                                audioFormatForMux?.let { muxerAudioTrack = muxer.addTrack(it) }
                                muxer.start()
                                muxerStarted = true
                            }
                            encOutIdx >= 0 -> {
                                val isEosFrame = encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                                val isCsd      = encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG  != 0
                                if (encInfo.size > 0 && !isCsd && muxerStarted) {
                                    val encBuf = encoder.getOutputBuffer(encOutIdx)!!
                                    encBuf.position(encInfo.offset)
                                    encBuf.limit(encInfo.offset + encInfo.size)
                                    muxer.writeSampleData(muxerVideoTrack, encBuf, encInfo)
                                }
                                encoder.releaseOutputBuffer(encOutIdx, false)
                                if (isEosFrame) { encoderDone = true; draining = false }
                            }
                            else -> draining = false
                        }
                    }
                }

                cachedSubBmp?.recycle()

                // 4. Copy original audio (compressed, no re-encode)
                val aExtractor = audioExtractor
                if (aExtractor != null && muxerAudioTrack != -1 && muxerStarted) {
                    try {
                        val audioBuf  = ByteBuffer.allocate(1 shl 19) // 512 KB
                        val audioInfo = MediaCodec.BufferInfo()
                        while (true) {
                            val sz = aExtractor.readSampleData(audioBuf, 0)
                            if (sz < 0) break
                            val sampleTimeUs = aExtractor.sampleTime
                            val keepAudio = keptRegions == null || keptRegions.isEmpty() || keptRegions.any { sampleTimeUs >= it.first && sampleTimeUs <= it.second }
                            if (keepAudio) {
                                audioInfo.offset = 0
                                audioInfo.size = sz
                                audioInfo.presentationTimeUs = mapOriginalToNewPts(sampleTimeUs, keptRegions)
                                audioInfo.flags =
                                    if (aExtractor.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                                        MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                                muxer.writeSampleData(muxerAudioTrack, audioBuf, audioInfo)
                            }
                            aExtractor.advance()
                        }
                    } catch (_: Exception) {
                        // Audio mux failed — keep video-only output
                    }
                }

                decoder.stop();  decoder.release();  decoder = null
                encoder.stop();  encoder.release();  encoder = null
                extractor.release()
                audioExtractor?.release(); audioExtractor = null
                releaseOverlayVideos()

                emitProgress(0.95)
                try { muxer.stop() } catch (_: Exception) {}
                muxer.release(); muxer = null

                emitProgress(0.98)
                if (!returnTempPath) {
                    saveVideoToGallery(outputPath, fileName)
                }
                emitProgress(1.0)
                runOnUiThread { result.success(if (returnTempPath) outputPath else "Movies/SubtitleAI/$fileName") }

            } catch (e: Exception) {
                try { decoder?.stop();  decoder?.release()  } catch (_: Exception) {}
                try { encoder?.stop();  encoder?.release()  } catch (_: Exception) {}
                try { extractor?.release()                  } catch (_: Exception) {}
                try { audioExtractor?.release()             } catch (_: Exception) {}
                try { muxer?.release()                      } catch (_: Exception) {}
                try { releaseOverlayVideos()                 } catch (_: Exception) {}
                try { File(outputPath).delete()             } catch (_: Exception) {}
                runOnUiThread { result.error("EXPORT_FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    private fun mapOriginalToNewPts(originalPtsUs: Long, keptRegions: List<Pair<Long, Long>>?): Long {
        if (keptRegions == null || keptRegions.isEmpty()) return originalPtsUs
        var accumulatedTime = 0L
        for (region in keptRegions) {
            if (originalPtsUs < region.first) {
                return accumulatedTime
            }
            if (originalPtsUs <= region.second) {
                return accumulatedTime + (originalPtsUs - region.first)
            }
            accumulatedTime += (region.second - region.first)
        }
        return accumulatedTime
    }

    // ─── Frame helpers ────────────────────────────────────────────────────────

    private fun computeActiveWordIdx(seg: Seg, presentUs: Long): Int {
        if (seg.words.isEmpty()) return -1
        val timings = seg.wordTimingsUs
        return if (timings != null && timings.size == seg.words.size) {
            timings.indexOfLast { it <= presentUs }.coerceAtLeast(0)
        } else {
            val dur = (seg.endUs - seg.startUs).coerceAtLeast(1L)
            ((((presentUs - seg.startUs).toFloat() / dur) * seg.words.size).toInt())
                .coerceIn(0, seg.words.size - 1)
        }
    }

    private fun imageToBitmap(image: Image): Bitmap {
        val w = image.width; val h = image.height
        val planes = image.planes
        val yBuf = planes[0].buffer; val uBuf = planes[1].buffer; val vBuf = planes[2].buffer
        val yRowStride = planes[0].rowStride; val uvRowStride = planes[1].rowStride
        val uvPixStride = planes[1].pixelStride
        val argb = IntArray(w * h)
        parallelRows(h) { startRow, endRow ->
            for (row in startRow until endRow) for (col in 0 until w) {
                val yVal  = (yBuf.get(row * yRowStride + col).toInt() and 0xFF) - 16
                val uvIdx = (row / 2) * uvRowStride + (col / 2) * uvPixStride
                val u     = (uBuf.get(uvIdx).toInt() and 0xFF) - 128
                val v     = (vBuf.get(uvIdx).toInt() and 0xFF) - 128
                val y1164 = yVal * 1164
                val r     = ((y1164 + 1596 * v) shr 10).coerceIn(0, 255)
                val g     = ((y1164 - 391 * u - 813 * v) shr 10).coerceIn(0, 255)
                val b     = ((y1164 + 2018 * u) shr 10).coerceIn(0, 255)
                argb[row * w + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
            }
        }
        val immutable = Bitmap.createBitmap(argb, w, h, Bitmap.Config.ARGB_8888)
        val mutable = immutable.copy(Bitmap.Config.ARGB_8888, true); immutable.recycle()
        return mutable
    }

    private fun bufferToBitmap(buf: ByteBuffer?, fmt: MediaFormat, w: Int, h: Int): Bitmap? {
        if (buf == null) return null
        val argb = IntArray(w * h)
        val yStride = if (fmt.containsKey(MediaFormat.KEY_STRIDE)) fmt.getInteger(MediaFormat.KEY_STRIDE) else w
        for (row in 0 until h) for (col in 0 until w) {
            val yVal  = (buf.get(row * yStride + col).toInt() and 0xFF) - 16
            val uvBase = yStride * h + (row / 2) * yStride; val uvOff = (col / 2) * 2
            val u     = (buf.get(uvBase + uvOff).toInt()     and 0xFF) - 128
            val v     = (buf.get(uvBase + uvOff + 1).toInt() and 0xFF) - 128
            val y1164 = yVal * 1164
            val r     = ((y1164 + 1596 * v) shr 10).coerceIn(0, 255)
            val g     = ((y1164 - 391 * u - 813 * v) shr 10).coerceIn(0, 255)
            val b     = ((y1164 + 2018 * u) shr 10).coerceIn(0, 255)
            argb[row * w + col] = (0xFF shl 24) or (r shl 16) or (g shl 8) or b
        }
        val immutable = Bitmap.createBitmap(argb, w, h, Bitmap.Config.ARGB_8888)
        val mutable = immutable.copy(Bitmap.Config.ARGB_8888, true); immutable.recycle()
        return mutable
    }

    private fun bitmapToImage(src: Bitmap, dst: Image) {
        val w = src.width; val h = src.height
        val argb = IntArray(w * h); src.getPixels(argb, 0, w, 0, 0, w, h)
        val yPlane = dst.planes[0]; val uPlane = dst.planes[1]; val vPlane = dst.planes[2]
        val uvStride = uPlane.pixelStride
        for (row in 0 until h) for (col in 0 until w) {
            val p = argb[row * w + col]
            val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
            val y = ((66 * r + 129 * g + 25 * b + 128) shr 8) + 16
            yPlane.buffer.put(row * yPlane.rowStride + col, y.coerceIn(16, 235).toByte())
            if (row % 2 == 0 && col % 2 == 0) {
                val u = ((-38 * r - 74 * g + 112 * b + 128) shr 8) + 128
                val v = ((112 * r - 94 * g - 18 * b + 128) shr 8) + 128
                val uvIdx = (row / 2) * uPlane.rowStride + (col / 2) * uvStride
                uPlane.buffer.put(uvIdx, u.coerceIn(16, 240).toByte())
                vPlane.buffer.put(uvIdx, v.coerceIn(16, 240).toByte())
            }
        }
    }

    /**
     * Convert an ARGB bitmap to YUV420 and write into the encoder input buffer.
     * @param semiPlanar true → NV12 (Y plane, then interleaved U,V) for COLOR_FormatYUV420SemiPlanar;
     *                   false → I420 (Y plane, then full U plane, then full V plane) for COLOR_FormatYUV420Planar.
     * @return number of bytes written (w*h*3/2).
     */
    private fun bitmapToYuv(src: Bitmap, out: ByteBuffer, w: Int, h: Int, semiPlanar: Boolean): Int {
        val argb = IntArray(w * h); src.getPixels(argb, 0, w, 0, 0, w, h)
        val frameSize = w * h
        val yuv = ByteArray(frameSize * 3 / 2)
        val cw = w / 2
        if (semiPlanar) {
            // NV12: Y plane, then interleaved U,V. Row-independent indexing.
            parallelRows(h) { startRow, endRow ->
                for (row in startRow until endRow) {
                    val yBase = row * w
                    val uvBase = frameSize + (row / 2) * w
                    val even = row % 2 == 0
                    for (col in 0 until w) {
                        val p = argb[yBase + col]
                        val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                        yuv[yBase + col] = (((66*r + 129*g + 25*b + 128) shr 8) + 16).coerceIn(16, 235).toByte()
                        if (even && col % 2 == 0) {
                            val idx = uvBase + col
                            yuv[idx]     = (((-38*r - 74*g + 112*b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                            yuv[idx + 1] = (((112*r - 94*g - 18*b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                        }
                    }
                }
            }
        } else {
            // I420: Y plane, then full U plane, then full V plane.
            val uBase = frameSize
            val vBase = frameSize + frameSize / 4
            parallelRows(h) { startRow, endRow ->
                for (row in startRow until endRow) {
                    val yBase = row * w
                    val even = row % 2 == 0
                    val chromaRow = (row / 2) * cw
                    for (col in 0 until w) {
                        val p = argb[yBase + col]
                        val r = (p shr 16) and 0xFF; val g = (p shr 8) and 0xFF; val b = p and 0xFF
                        yuv[yBase + col] = (((66*r + 129*g + 25*b + 128) shr 8) + 16).coerceIn(16, 235).toByte()
                        if (even && col % 2 == 0) {
                            val ci = chromaRow + (col / 2)
                            yuv[uBase + ci] = (((-38*r - 74*g + 112*b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                            yuv[vBase + ci] = (((112*r - 94*g - 18*b + 128) shr 8) + 128).coerceIn(16, 240).toByte()
                        }
                    }
                }
            }
        }
        out.clear(); out.put(yuv)
        return yuv.size
    }

    // ─── Subtitle rendering ───────────────────────────────────────────────────

    private fun easeOut(t: Float)  = 1f - (1f - t) * (1f - t) * (1f - t)
    private fun bounceEase(t: Float): Float { val s = 1.70158f; val t2 = t - 1f; return t2 * t2 * ((s + 1f) * t2 + s) + 1f }

    private fun animOffset(animType: String, animT: Float, slideAmt: Float, exit: Boolean = false): Pair<Float, Float> {
        val t = easeOut(animT)
        val d = if (exit) -1f else 1f // exit leaves the opposite way it entered
        return when (animType) {
            "slideUp"   -> Pair(0f,  d * slideAmt * (1f - t))
            "slideDown" -> Pair(0f, -d * slideAmt * (1f - t))
            "slideLeft" -> Pair( d * slideAmt * (1f - t), 0f)
            else        -> Pair(0f, 0f)
        }
    }

    private fun makeNormalBitmap(text: String, translatedText: String?, animT: Float, w: Int, h: Int, s: RenderStyle, exit: Boolean = false): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); val canvas = Canvas(bmp)
        // WYSIWYG free-transform: shift to positionX + rotate (positionY is applied
        // by the existing layout below). Restored before the watermark is drawn.
        val cxN = s.positionX * w; val cyN = s.positionY * h
        canvas.save()
        canvas.translate(cxN - w / 2f, 0f)
        if (s.rotation != 0f) canvas.rotate(s.rotation, w / 2f, cyN)
        val alpha = if (exit) (easeOut(animT) * 255).toInt().coerceIn(0, 255)
            else when (s.animationType) {
                "bounceIn" -> 255
                else -> if (animT < 1f) (easeOut(animT) * 255).toInt().coerceIn(0, 255) else 255
            }
        if (s.animationType == "bounceIn") {
            val scale = (if (exit) animT else bounceEase(animT)).coerceAtLeast(0.01f)
            canvas.save(); canvas.scale(scale, scale, w / 2f, s.positionY * h)
        } else {
            val (ox, oy) = animOffset(s.animationType, animT, s.scaledTextSize * 1.8f, exit)
            if (ox != 0f || oy != 0f) canvas.translate(ox, oy)
        }
        val textPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = s.textColor; textSize = s.scaledTextSize; typeface = s.typeface; textAlign = Paint.Align.CENTER; this.alpha = alpha }
        val lines = text.split("\n"); val lineH = textPaint.fontSpacing; val x = w / 2f
        val fm = textPaint.fontMetrics
        // Center the whole block (main lines + optional bilingual line) at positionY,
        // matching the Flutter preview which centers the subtitle column there.
        val hasBilingual = !translatedText.isNullOrEmpty() && s.bilingualTextColor != null
        val topOff = -(lines.size - 1) * lineH + fm.ascent
        val bottomOff = if (hasBilingual)
            (fm.descent + s.bilingualGap + s.scaledBilingualSize * 1.1f) else fm.descent
        val baseY = s.positionY * h - (topOff + bottomOff) / 2f
        val startY = baseY - lineH * (lines.size - 1)
        if (s.bgColor != null) {
            val maxW = lines.maxOf { textPaint.measureText(it) }; val pH = s.scaledTextSize * 0.2f; val pV = s.scaledTextSize * 0.06f
            canvas.drawRoundRect(RectF(x - maxW/2f - pH, startY + fm.ascent - pV, x + maxW/2f + pH, startY + lineH*(lines.size-1) + fm.descent + pV), s.scaledTextSize * 0.16f, s.scaledTextSize * 0.16f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = s.bgColor; style = Paint.Style.FILL; this.alpha = alpha })
        }
        // Match the Flutter preview for every style:
        //   • neon glow → blurred colour halo (no outline)
        //   • underline → plain text + accent bar (no outline)
        //   • otherwise → soft drop shadow when hasShadow, else plain (NO hard stroke)
        val glowC = if (s.hasNeonGlow) (s.glowColor ?: s.textColor) else Color.TRANSPARENT
        val glowPaintWide = if (s.hasNeonGlow) Paint(textPaint).apply { color = glowC; this.alpha = alpha; maskFilter = android.graphics.BlurMaskFilter(s.scaledTextSize * 1.4f, android.graphics.BlurMaskFilter.Blur.NORMAL) } else null
        val glowPaintTight = if (s.hasNeonGlow) Paint(textPaint).apply { color = glowC; this.alpha = alpha; maskFilter = android.graphics.BlurMaskFilter(s.scaledTextSize * 0.7f, android.graphics.BlurMaskFilter.Blur.NORMAL) } else null
        val shadowPaint = if (s.hasShadow && !s.hasNeonGlow && !s.has3dShadow) Paint(textPaint).apply { color = Color.BLACK; style = Paint.Style.FILL; this.alpha = (alpha * 0.7f).toInt(); maskFilter = android.graphics.BlurMaskFilter(s.scaledTextSize * 0.2f, android.graphics.BlurMaskFilter.Blur.NORMAL) } else null
        // Retro 3D extrude: stack hard black copies stepping down-right.
        val extrudePaint = if (s.has3dShadow) Paint(textPaint).apply { color = Color.BLACK; style = Paint.Style.FILL; this.alpha = alpha } else null
        val extrudeDepth = if (s.has3dShadow) (s.scaledTextSize * 0.13f).toInt().coerceIn(3, 14) else 0
        // Hard outline (sticker): black stroke behind the fill.
        val outlinePaint = if (s.hasOutline) Paint(textPaint).apply { color = s.outlineColor ?: Color.BLACK; style = Paint.Style.STROKE; strokeWidth = s.scaledTextSize * 0.13f; strokeJoin = Paint.Join.ROUND; this.alpha = alpha } else null
        val hasGradient = (s.gradientColors?.size ?: 0) >= 2
        for ((i, line) in lines.withIndex()) {
            val y = startY + i * lineH
            if (s.hasNeonGlow) {
                canvas.drawText(line, x, y, glowPaintWide!!)
                canvas.drawText(line, x, y, glowPaintTight!!)
            } else if (extrudePaint != null) {
                for (d in extrudeDepth downTo 1) {
                    canvas.drawText(line, x + d, y + d, extrudePaint)
                }
            } else if (shadowPaint != null) {
                canvas.drawText(line, x + s.scaledTextSize * 0.03f, y + s.scaledTextSize * 0.06f, shadowPaint)
            }
            if (outlinePaint != null) canvas.drawText(line, x, y, outlinePaint)
            if (hasGradient) {
                val lw = textPaint.measureText(line)
                textPaint.shader = android.graphics.LinearGradient(
                    x - lw / 2f, y - s.scaledTextSize, x + lw / 2f, y,
                    s.gradientColors!!, null, android.graphics.Shader.TileMode.CLAMP)
            }
            canvas.drawText(line, x, y, textPaint)
        }
        textPaint.shader = null
        // Underline accent bar (popLine style).
        if (s.hasUnderline) {
            val lineW = lines.maxOf { textPaint.measureText(it) }
            val lastY = startY + (lines.size - 1) * lineH
            val uH = s.scaledTextSize * 0.09f
            val uTop = lastY + fm.descent + s.scaledTextSize * 0.06f
            canvas.drawRoundRect(RectF(x - lineW / 2f, uTop, x + lineW / 2f, uTop + uH), uH / 2f, uH / 2f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = s.underlineColor ?: s.textColor; style = Paint.Style.FILL; this.alpha = alpha })
        }
        if (s.animationType == "bounceIn") canvas.restore()
        val biY = baseY + fm.descent + s.bilingualGap + s.scaledBilingualSize * 0.85f
        drawBilingualLine(canvas, translatedText, x, biY, w, s, alpha)
        canvas.restore()
        s.watermarkText?.let { drawWatermark(canvas, it, w, h, s.scaledTextSize, s.watermarkPosition, s.watermarkLogo) }
        return bmp
    }

    private fun makeKaraokeBitmap(text: String, words: List<String>, activeIdx: Int, translatedText: String?, animT: Float, w: Int, h: Int, s: RenderStyle, exit: Boolean = false, emphasis: List<Int> = emptyList(), sweep: Boolean = true, emoji: String? = null): Bitmap {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888); val canvas = Canvas(bmp)
        val cxN = s.positionX * w; val cyN = s.positionY * h
        canvas.save()
        canvas.translate(cxN - w / 2f, 0f)
        if (s.rotation != 0f) canvas.rotate(s.rotation, w / 2f, cyN)
        val alpha = if (exit || animT < 1f) (easeOut(animT) * 255).toInt().coerceIn(0, 255) else 255
        if (s.animationType == "bounceIn") { val scale = (if (exit) animT else bounceEase(animT)).coerceAtLeast(0.01f); canvas.save(); canvas.scale(scale, scale, w / 2f, s.positionY * h) }
        else { val (ox, oy) = animOffset(s.animationType, animT, s.scaledTextSize * 1.8f, exit); if (ox != 0f || oy != 0f) canvas.translate(ox, oy) }

        val basePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textSize = s.scaledTextSize; typeface = s.typeface; textAlign = Paint.Align.LEFT }
        val spaceW = basePaint.measureText(" ")
        val maxLineW = w * 0.92f
        // Word Pop scale.
        val popScale = 1.22f
        // Tokens = the words, plus the Auto-✨ emoji appended as a trailing token.
        val hasEmoji = !emoji.isNullOrEmpty()
        val allWords = if (hasEmoji) words + emoji!! else words
        val emojiIdx = if (hasEmoji) words.size else -1
        // A word is "hot" if the karaoke sweep is on it OR it's a ✨ punch word.
        fun isActiveHot(i: Int) =
            sweep && i == activeIdx && s.karaokeColor != null && words.size >= 2
        fun isEmph(i: Int) = emphasis.contains(i)
        fun isPopWord(i: Int) = (isActiveHot(i) || isEmph(i)) && (s.karaokeScale || isEmph(i))

        // 1. Measure each token + the gap before it. The hot/pop word is measured
        //    at its enlarged width so the line REFLOWS around it (like preview).
        val tokens = ArrayList<KWord>(allWords.size)
        for (i in allWords.indices) {
            val wd  = basePaint.measureText(allWords[i]) * (if (isPopWord(i)) popScale else 1f)
            val gap = if (i == 0) 0f
                      else if (i == emojiIdx || needSpaceBetween(allWords[i - 1], allWords[i])) spaceW
                      else 0f
            tokens.add(KWord(allWords[i], wd, gap, i))
        }

        // 2. Greedy wrap into lines that fit the width
        val lines = ArrayList<ArrayList<KWord>>()
        var cur = ArrayList<KWord>(); var curW = 0f
        for (t in tokens) {
            val addW = (if (cur.isEmpty()) 0f else t.gapBefore) + t.width
            if (cur.isNotEmpty() && curW + addW > maxLineW) { lines.add(cur); cur = ArrayList(); curW = 0f }
            curW += (if (cur.isEmpty()) 0f else t.gapBefore) + t.width
            cur.add(t)
        }
        if (cur.isNotEmpty()) lines.add(cur)

        val fm = basePaint.fontMetrics
        val lineH = basePaint.fontSpacing
        // Center the whole block (wrapped lines + optional bilingual) at positionY.
        val hasBilingual = !translatedText.isNullOrEmpty() && s.bilingualTextColor != null
        val biExtra = if (hasBilingual) (s.bilingualGap + s.scaledBilingualSize * 1.1f) else 0f
        val blockOff = (fm.ascent + (lines.size - 1) * lineH + fm.descent + biExtra) / 2f
        val baseY0 = s.positionY * h - blockOff

        // Background box (matches the preview Container when the preset has a bgColor).
        if (s.bgColor != null) {
            var widest = 0f
            for (line in lines) { var lw0 = 0f; for ((j, t) in line.withIndex()) lw0 += (if (j == 0) 0f else t.gapBefore) + t.width; if (lw0 > widest) widest = lw0 }
            val pH = s.scaledTextSize * 0.2f; val pV = s.scaledTextSize * 0.06f
            val top = baseY0 + fm.ascent - pV
            val bottom = baseY0 + (lines.size - 1) * lineH + fm.descent + pV
            canvas.drawRoundRect(RectF(w / 2f - widest / 2f - pH, top, w / 2f + widest / 2f + pH, bottom), s.scaledTextSize * 0.16f, s.scaledTextSize * 0.16f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = s.bgColor; style = Paint.Style.FILL; this.alpha = alpha })
        }
        // Soft drop shadow per word (matches the preview) instead of a hard outline.
        val shadowPaint = Paint(basePaint).apply { color = Color.BLACK; style = Paint.Style.FILL; maskFilter = android.graphics.BlurMaskFilter(s.scaledTextSize * 0.16f, android.graphics.BlurMaskFilter.Blur.NORMAL) }
        val fillPaint = Paint(basePaint).apply { style = Paint.Style.FILL }
        val shOff = s.scaledTextSize * 0.04f

        for ((li, line) in lines.withIndex()) {
            var lw = 0f
            for ((j, t) in line.withIndex()) lw += (if (j == 0) 0f else t.gapBefore) + t.width
            var xCursor = w / 2f - lw / 2f
            val baseY = baseY0 + li * lineH
            for ((j, t) in line.withIndex()) {
                if (j != 0) xCursor += t.gapBefore
                val activeHot = isActiveHot(t.index)
                val emph = isEmph(t.index)
                // Word Pop: draw the hot word at the enlarged size INLINE on the
                // baseline (its width was reserved during measure), so the line
                // reflows exactly like the preview instead of overlapping.
                val tsize = if (isPopWord(t.index)) s.scaledTextSize * popScale
                            else s.scaledTextSize
                shadowPaint.textSize = tsize
                shadowPaint.alpha = (alpha * 0.7f).toInt()
                canvas.drawText(t.text, xCursor + shOff, baseY + shOff, shadowPaint)
                fillPaint.textSize = tsize
                fillPaint.color = when {
                    activeHot -> s.karaokeColor!!
                    emph -> s.emphasisColor ?: s.karaokeColor ?: s.textColor
                    else -> s.textColor
                }
                fillPaint.alpha = alpha
                canvas.drawText(t.text, xCursor, baseY, fillPaint)
                xCursor += t.width
            }
        }

        if (s.animationType == "bounceIn") canvas.restore()
        val biY = baseY0 + (lines.size - 1) * lineH + fm.descent + s.bilingualGap + s.scaledBilingualSize * 0.85f
        drawBilingualLine(canvas, translatedText, w / 2f, biY, w, s, alpha)
        canvas.restore()
        s.watermarkText?.let { drawWatermark(canvas, it, w, h, s.scaledTextSize, s.watermarkPosition, s.watermarkLogo) }
        return bmp
    }

    /// Reliable video rotation: the MediaExtractor track format often lacks
    /// "rotation-degrees", so fall back to MediaMetadataRetriever (the documented
    /// source). Portrait phone videos carry rotation 90/270 here.
    private fun readRotation(path: String, formatRotation: Int): Int {
        if (formatRotation != 0) return formatRotation
        return try {
            val mmr = android.media.MediaMetadataRetriever()
            mmr.setDataSource(path)
            val r = mmr.extractMetadata(
                android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
            )?.toIntOrNull() ?: 0
            mmr.release()
            r
        } catch (_: Exception) {
            0
        }
    }

    /// Overlays are rendered upright at DISPLAY dimensions, then rotated back to
    /// the RAW (encoded) orientation so that after the player applies the
    /// orientation hint the watermark/subtitles appear upright. [src] is recycled.
    private fun orientOverlay(src: Bitmap, rotation: Int): Bitmap {
        val r = ((rotation % 360) + 360) % 360
        if (r == 0) return src
        val m = android.graphics.Matrix().apply { postRotate(-r.toFloat()) }
        val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, m, true)
        if (rotated !== src) src.recycle()
        return rotated
    }

    /// Builds a transparent full-frame bitmap containing only the watermark,
    /// composited on every output frame so the mark is always visible.
    /// Returns null when no watermark is requested.
    /// Decode the watermark logo downsampled near its on-screen size. The source
    /// PNG can be huge (e.g. 8000px); decoding it full then scaling ~33x in one
    /// step looks blurry. inSampleSize uses box-averaging → crisp result.
    private fun decodeScaledLogo(path: String, vidW: Int): Bitmap? {
        return try {
            if (!File(path).exists()) return null
            val bounds = android.graphics.BitmapFactory.Options().apply {
                inJustDecodeBounds = true
            }
            android.graphics.BitmapFactory.decodeFile(path, bounds)
            val maxDim = (vidW.coerceAtLeast(480) * 0.6f).toInt().coerceAtLeast(256)
            val srcMax = maxOf(bounds.outWidth, bounds.outHeight)
            var sample = 1
            while (srcMax / sample > maxDim) sample *= 2
            val opts =
                android.graphics.BitmapFactory.Options().apply { inSampleSize = sample }
            android.graphics.BitmapFactory.decodeFile(path, opts)
        } catch (_: Exception) {
            null
        }
    }

    private fun makeWatermarkBitmap(w: Int, h: Int, s: RenderStyle): Bitmap? {
        val text = s.watermarkText ?: return null
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        drawWatermark(Canvas(bmp), text, w, h, s.scaledTextSize, s.watermarkPosition, s.watermarkLogo)
        return bmp
    }

    /// CapCut-style watermark: app logo followed by the "KarnSub" wordmark,
    /// right-anchored in a corner. White, semi-transparent, no black outline.
    private fun drawWatermark(canvas: Canvas, text: String, w: Int, h: Int, refSize: Float, position: String, logo: Bitmap?) {
        val pad = w * 0.025f
        if (logo != null && logo.width > 0 && logo.height > 0) {
            // The logo image is the full "KarnSub" wordmark → draw it alone,
            // scaled by video width with its real aspect ratio.
            val logoW = (w * 0.22f).coerceIn(90f, 380f)
            val logoH = logoW * logo.height / logo.width
            val left = w - pad - logoW
            val top = if (position == "bottom") (h - pad - logoH) else pad
            canvas.drawBitmap(
                logo, null,
                RectF(left, top, left + logoW, top + logoH),
                Paint(Paint.FILTER_BITMAP_FLAG).apply { alpha = 200 },
            )
        } else {
            // Fallback (no logo asset): plain text wordmark with a soft shadow.
            val size = (w * 0.038f).coerceIn(22f, 64f)
            val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                color = Color.WHITE
                textSize = size
                typeface = Typeface.create(Typeface.DEFAULT, Typeface.BOLD)
                textAlign = Paint.Align.RIGHT
                style = Paint.Style.FILL
                alpha = 160
                setShadowLayer(size * 0.22f, 0f, size * 0.05f, 0x70000000.toInt())
            }
            val y = if (position == "bottom") (h - pad - size * 0.2f) else (size * 1.3f)
            canvas.drawText(text, w - pad, y, fillPaint)
        }
    }

    private fun drawBilingualLine(canvas: Canvas, text: String?, x: Float, y: Float, w: Int, s: RenderStyle, alpha: Int) {
        if (text.isNullOrEmpty() || s.bilingualTextColor == null) return
        val biPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { textAlign = Paint.Align.CENTER; color = s.bilingualTextColor; textSize = s.scaledBilingualSize; typeface = if (s.bilingualIsBold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT }
        if (s.bilingualBgColor != null) { val bw = biPaint.measureText(text); val fm = biPaint.fontMetrics; val pH = s.scaledBilingualSize * 0.3f; val pV = s.scaledBilingualSize * 0.15f; canvas.drawRoundRect(RectF(x - bw/2f - pH, y + fm.ascent - pV, x + bw/2f + pH, y + fm.descent + pV), 8f, 8f, Paint(Paint.ANTI_ALIAS_FLAG).apply { color = s.bilingualBgColor; style = Paint.Style.FILL }) }
        if (s.bilingualHasNeon && s.bilingualGlowColor != null) canvas.drawText(text, x, y, Paint(biPaint).apply { color = s.bilingualGlowColor; maskFilter = android.graphics.BlurMaskFilter(s.scaledBilingualSize * 0.6f, android.graphics.BlurMaskFilter.Blur.NORMAL) })
        else if (s.bilingualHasShadow) canvas.drawText(text, x + 1f, y + 1f, Paint(biPaint).apply { color = 0x80000000.toInt() })
        else if (s.bilingualBgColor == null) canvas.drawText(text, x, y, Paint(biPaint).apply { color = Color.BLACK; style = Paint.Style.STROKE; strokeWidth = s.scaledBilingualSize * 0.07f; strokeJoin = Paint.Join.ROUND })
        canvas.drawText(text, x, y, biPaint)
    }

    // ─── Save Video to Gallery ────────────────────────────────────────────────

    private fun saveVideoToGallery(sourcePath: String, fileName: String) {
        val sourceFile = File(sourcePath)
        if (!sourceFile.exists() || sourceFile.length() == 0L)
            throw Exception("Encoded file not found or empty: $sourcePath")
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/SubtitleAI")
                put(MediaStore.Video.Media.IS_PENDING, 1)
            }
            val uri = contentResolver.insert(MediaStore.Video.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                ?: throw Exception("MediaStore insert returned null")
            contentResolver.openOutputStream(uri)?.use { out -> sourceFile.inputStream().use { it.copyTo(out) } }
                ?: throw Exception("Cannot open MediaStore output stream")
            values.clear(); values.put(MediaStore.Video.Media.IS_PENDING, 0)
            contentResolver.update(uri, values, null, null)
        } else {
            @Suppress("DEPRECATION")
            val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "SubtitleAI")
            dir.mkdirs()
            val dest = File(dir, fileName)
            sourceFile.copyTo(dest, overwrite = true)
            MediaScannerConnection.scanFile(applicationContext, arrayOf(dest.absolutePath), arrayOf("video/mp4"), null)
        }
    }

    // ─── Speech onset detection (energy VAD) for auto-sync ──────────────────────

    private val vadFrameMs = 20

    private fun detectSpeechOnsets(videoPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                val energies = decodeEnergies(resolveUriToFilePath(videoPath))
                runOnUiThread { result.success(computeOnsets(energies, vadFrameMs)) }
            } catch (e: Exception) {
                runOnUiThread { result.error("VAD_FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    /** Extract a thumbnail (JPEG) + duration (ms) for a video. */
    private fun videoMeta(videoPath: String, thumbPath: String?, result: MethodChannel.Result) {
        Thread {
            val r = android.media.MediaMetadataRetriever()
            try {
                val path = resolveUriToFilePath(videoPath)
                r.setDataSource(path)
                val durMs = r.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: -1L
                var savedThumb: String? = null
                if (thumbPath != null) {
                    val frameUs = if (durMs > 0) (durMs * 1000L / 10L) else 0L
                    val bmp = r.getFrameAtTime(
                        frameUs,
                        android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                    )
                    if (bmp != null) {
                        val tw = 320
                        val th = (bmp.height.toLong() * tw / bmp.width.coerceAtLeast(1)).toInt().coerceAtLeast(1)
                        val scaled = Bitmap.createScaledBitmap(bmp, tw, th, true)
                        FileOutputStream(thumbPath).use {
                            scaled.compress(Bitmap.CompressFormat.JPEG, 82, it)
                        }
                        if (scaled != bmp) scaled.recycle()
                        bmp.recycle()
                        savedThumb = thumbPath
                    }
                }
                runOnUiThread { result.success(mapOf("durationMs" to durMs, "thumb" to savedThumb)) }
            } catch (e: Exception) {
                runOnUiThread { result.success(mapOf("durationMs" to -1L, "thumb" to null)) }
            } finally {
                try { r.release() } catch (_: Exception) {}
            }
        }.start()
    }

    /** Normalised audio amplitude (0..1) per 20ms — for drawing a waveform. */
    private fun audioWaveform(videoPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                val e = decodeEnergies(resolveUriToFilePath(videoPath))
                val max = (e.maxOrNull() ?: 1.0).coerceAtLeast(1e-6)
                val norm = e.map { (it / max).coerceIn(0.0, 1.0) }
                runOnUiThread { result.success(norm) }
            } catch (ex: Exception) {
                runOnUiThread { result.success(emptyList<Double>()) }
            }
        }.start()
    }

    /** Returns speech regions as a flat list [start0,end0,start1,end1,...] in ms. */
    private fun detectSpeechRegions(videoPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                val energies = decodeEnergies(resolveUriToFilePath(videoPath))
                val flat = ArrayList<Int>()
                for (r in computeRegions(energies, vadFrameMs)) { flat.add(r[0]); flat.add(r[1]) }
                runOnUiThread { result.success(flat) }
            } catch (e: Exception) {
                runOnUiThread { result.error("VAD_FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    /** Extract evenly-spaced video frame thumbnails for the timeline filmstrip.
     *  Runs off the main thread; saves small JPEGs to cache and returns a list
     *  of { ms, path }. Returns [] on any failure (timeline keeps the waveform). */
    private fun extractThumbnails(
        videoPath: String,
        maxCount: Int,
        targetH: Int,
        result: MethodChannel.Result,
    ) {
        Thread {
            val mmr = android.media.MediaMetadataRetriever()
            try {
                mmr.setDataSource(resolveUriToFilePath(videoPath))
                val durMs = mmr.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_DURATION
                )?.toLongOrNull() ?: 0L
                if (durMs <= 0) {
                    runOnUiThread { result.success(emptyList<Any>()) }
                    return@Thread
                }
                val vW = mmr.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_WIDTH
                )?.toIntOrNull() ?: 0
                val vH = mmr.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_HEIGHT
                )?.toIntOrNull() ?: 0
                val rot = mmr.extractMetadata(
                    android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                )?.toIntOrNull() ?: 0
                val dispW = if (rot == 90 || rot == 270) vH else vW
                val dispH = if (rot == 90 || rot == 270) vW else vH
                val aspect = if (dispH > 0) dispW.toFloat() / dispH else 16f / 9f
                val th = targetH.coerceIn(48, 240)
                val tw = (th * aspect).toInt().coerceAtLeast(2)

                val count = maxCount.coerceIn(4, 60)
                val stepMs = (durMs / count).coerceAtLeast(500L)
                val dir = java.io.File(cacheDir, "thumbs")
                if (dir.exists()) dir.listFiles()?.forEach { it.delete() } else dir.mkdirs()

                val out = ArrayList<Map<String, Any>>()
                var t = 0L
                var i = 0
                while (t < durMs && i < count) {
                    val bmp = if (Build.VERSION.SDK_INT >= 27) {
                        mmr.getScaledFrameAtTime(
                            t * 1000,
                            android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                            tw, th,
                        )
                    } else {
                        val full = mmr.getFrameAtTime(
                            t * 1000,
                            android.media.MediaMetadataRetriever.OPTION_CLOSEST_SYNC,
                        )
                        if (full != null) {
                            val sc = Bitmap.createScaledBitmap(full, tw, th, true)
                            if (sc !== full) full.recycle()
                            sc
                        } else null
                    }
                    if (bmp != null) {
                        val f = java.io.File(dir, "th_$i.jpg")
                        java.io.FileOutputStream(f).use {
                            bmp.compress(Bitmap.CompressFormat.JPEG, 60, it)
                        }
                        out.add(mapOf("ms" to t, "path" to f.absolutePath))
                        bmp.recycle()
                    }
                    t += stepMs
                    i++
                }
                runOnUiThread { result.success(out) }
            } catch (e: Exception) {
                runOnUiThread { result.success(emptyList<Any>()) }
            } finally {
                try { mmr.release() } catch (_: Exception) {}
            }
        }.start()
    }

    /** Dictionary-based Lao/Thai word segmentation via ICU. One list per input. */
    private fun segmentWords(texts: List<String>, locale: String): List<List<String>> {
        return try {
            val bi = android.icu.text.BreakIterator.getWordInstance(android.icu.util.ULocale(locale))
            texts.map { t ->
                if (t.isBlank()) return@map listOf(t)
                val out = ArrayList<String>()
                bi.setText(t)
                var start = bi.first()
                var end = bi.next()
                while (end != android.icu.text.BreakIterator.DONE) {
                    val w = t.substring(start, end)
                    if (w.isNotBlank()) out.add(w)
                    start = end
                    end = bi.next()
                }
                if (out.isEmpty()) listOf(t) else mergeLaoOrphans(out)
            }
        } catch (e: Exception) {
            texts.map { listOf(it) }
        }
    }

    /** Fix ICU mis-splits on Lao/Thai loanwords/names (e.g. "ໂຫຼດ" → "ໂຫຼ"+"ດ"):
     *  a syllable can't begin with a bare final consonant or a combining mark, and
     *  a leading vowel (ເແໂໃໄ) must attach to the following consonant. Merge such
     *  fragments back so words are never cut in a way that's unreadable. */
    private fun mergeLaoOrphans(words: List<String>): List<String> {
        if (words.size < 2) return words
        fun isCons(c: Char) = c.code in 0x0E81..0x0EAE || c.code in 0x0E01..0x0E2E
        fun isLead(c: Char) = c.code in 0x0EC0..0x0EC4 || c.code in 0x0E40..0x0E44
        fun isCombining(c: Char) =
            c.code in 0x0EB0..0x0EBD || c.code in 0x0EC8..0x0ECD ||
            c.code == 0x0E31 || c.code in 0x0E34..0x0E3A || c.code in 0x0E47..0x0E4E
        val out = ArrayList<String>()
        for (w in words) {
            if (out.isEmpty()) { out.add(w); continue }
            val prev = out.last()
            val orphanFinal = w.length == 1 && isCons(w[0])      // stray final consonant
            val combiningOnly = w.isNotEmpty() && w.all { isCombining(it) }
            val prevEndsLead = prev.isNotEmpty() && isLead(prev.last()) // dangling leading vowel
            if (orphanFinal || combiningOnly || prevEndsLead) {
                out[out.size - 1] = prev + w
            } else {
                out.add(w)
            }
        }
        return out
    }

    /** Decode the audio track to per-20ms RMS energy values. */
    private fun decodeEnergies(path: String): List<Double> {
        var extractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(path)
            var trackIndex = -1
            for (i in 0 until extractor.trackCount) {
                if ((extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: "").startsWith("audio/")) {
                    trackIndex = i; break
                }
            }
            if (trackIndex == -1) return emptyList()
            extractor.selectTrack(trackIndex)
            val fmt = extractor.getTrackFormat(trackIndex)
            val sampleRate = if (fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE))
                fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE) else 44100
            val channels = if (fmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT))
                fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT) else 1

            decoder = MediaCodec.createDecoderByType(fmt.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(fmt, null, null, 0)
            decoder.start()

            val frameSamples = (sampleRate.toLong() * channels * vadFrameMs / 1000).toInt().coerceAtLeast(1)
            val energies = ArrayList<Double>(4096)
            var acc = 0.0
            var accCount = 0
            // Pre-emphasis high-pass: y[n] = x[n] - 0.97*x[n-1]. This attenuates
            // low-frequency energy (music bass, hum) and emphasizes the higher
            // frequencies that carry speech, so the VAD locks onto the voice even
            // over background music instead of triggering on the beat.
            var prevSample = 0.0
            val info = MediaCodec.BufferInfo()
            var eos = false
            while (!eos) {
                val inIdx = decoder.dequeueInputBuffer(10_000)
                if (inIdx >= 0) {
                    val inBuf = decoder.getInputBuffer(inIdx)!!
                    val sz = extractor.readSampleData(inBuf, 0)
                    if (sz < 0) {
                        decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                        eos = true
                    } else {
                        decoder.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0)
                        extractor.advance()
                    }
                }
                var outIdx = decoder.dequeueOutputBuffer(info, 10_000)
                while (outIdx >= 0) {
                    val outBuf = decoder.getOutputBuffer(outIdx)!!
                    val shorts = outBuf.order(ByteOrder.LITTLE_ENDIAN).asShortBuffer()
                    val n = info.size / 2
                    var i = 0
                    while (i < n) {
                        val x = shorts.get(i) / 32768.0
                        val v = x - 0.97 * prevSample   // pre-emphasis
                        prevSample = x
                        acc += v * v; accCount++
                        if (accCount >= frameSamples) { energies.add(Math.sqrt(acc / accCount)); acc = 0.0; accCount = 0 }
                        i++
                    }
                    decoder.releaseOutputBuffer(outIdx, false)
                    outIdx = decoder.dequeueOutputBuffer(info, 0)
                }
            }
            if (accCount > 0) energies.add(Math.sqrt(acc / accCount))
            // Smooth with a short moving average (~3 frames) so brief dips inside a
            // word don't fragment a region and single-frame blips don't false-fire.
            return smoothEnergies(energies, 3)
        } finally {
            try { decoder?.stop(); decoder?.release() } catch (_: Exception) {}
            try { extractor?.release() } catch (_: Exception) {}
        }
    }

    /** Short moving-average smoothing of the per-frame energies (window = win
     *  frames). Reduces flicker so brief intra-word dips don't split a region. */
    private fun smoothEnergies(e: List<Double>, win: Int): List<Double> {
        if (e.size < 3 || win < 2) return e
        val half = win / 2
        val out = ArrayList<Double>(e.size)
        for (i in e.indices) {
            var s = 0.0; var c = 0
            var j = (i - half).coerceAtLeast(0)
            val end = (i + half).coerceAtMost(e.size - 1)
            while (j <= end) { s += e[j]; c++; j++ }
            out.add(s / c)
        }
        return out
    }

    /** Adaptive energy threshold → speech regions [startMs, endMs]. Uses
     *  hysteresis (two thresholds): enter speech only on a clear rise, but stay
     *  in speech down to a lower level so soft tails aren't clipped mid-word. */
    private fun computeRegions(energies: List<Double>, frameMs: Int): List<IntArray> {
        if (energies.size < 4) return emptyList()
        val sorted = energies.sorted()
        val floor = sorted[(sorted.size * 0.20).toInt().coerceIn(0, sorted.size - 1)]
        val peak  = sorted[(sorted.size * 0.95).toInt().coerceIn(0, sorted.size - 1)]
        val enterT = floor + (peak - floor) * 0.15   // must clearly exceed to start
        val stayT  = floor + (peak - floor) * 0.07   // stay in speech down to here
        val minGapFrames = (150 / frameMs).coerceAtLeast(1)
        val minSpeechFrames = (90 / frameMs).coerceAtLeast(1)
        val regions = ArrayList<IntArray>()
        var inSpeech = false
        var startF = -1
        var lastSpeechF = -1
        var silenceRun = 0
        var i = 0
        while (i < energies.size) {
            val e = energies[i]
            if (!inSpeech) {
                if (e > enterT) { startF = i; inSpeech = true; silenceRun = 0; lastSpeechF = i }
            } else {
                if (e > stayT) { silenceRun = 0; lastSpeechF = i }
                else {
                    silenceRun++
                    if (silenceRun >= minGapFrames) {
                        if (lastSpeechF - startF + 1 >= minSpeechFrames)
                            regions.add(intArrayOf(startF * frameMs, (lastSpeechF + 1) * frameMs))
                        inSpeech = false
                    }
                }
            }
            i++
        }
        if (inSpeech && lastSpeechF - startF + 1 >= minSpeechFrames)
            regions.add(intArrayOf(startF * frameMs, (lastSpeechF + 1) * frameMs))
        return regions
    }

    /** Adaptive energy threshold → list of speech-region start times (ms), with
     *  the same hysteresis as computeRegions so onsets land on a real rise. */
    private fun computeOnsets(energies: List<Double>, frameMs: Int): List<Int> {
        if (energies.size < 4) return emptyList()
        val sorted = energies.sorted()
        val floor = sorted[(sorted.size * 0.20).toInt().coerceIn(0, sorted.size - 1)]
        val peak  = sorted[(sorted.size * 0.95).toInt().coerceIn(0, sorted.size - 1)]
        val enterT = floor + (peak - floor) * 0.15
        val stayT  = floor + (peak - floor) * 0.07
        val minGapFrames = (150 / frameMs).coerceAtLeast(1)     // >=150ms silence splits regions
        val minSpeechFrames = (90 / frameMs).coerceAtLeast(1)   // ignore <90ms blips

        val onsets = ArrayList<Int>()
        var inSpeech = false
        var speechStart = -1
        var lastSpeechF = -1
        var silenceRun = 0
        var i = 0
        while (i < energies.size) {
            val e = energies[i]
            if (!inSpeech) {
                if (e > enterT) { speechStart = i; inSpeech = true; silenceRun = 0; lastSpeechF = i }
            } else {
                if (e > stayT) { silenceRun = 0; lastSpeechF = i }
                else {
                    silenceRun++
                    if (silenceRun >= minGapFrames) {
                        if (lastSpeechF - speechStart + 1 >= minSpeechFrames) onsets.add(speechStart * frameMs)
                        inSpeech = false
                    }
                }
            }
            i++
        }
        if (inSpeech && lastSpeechF - speechStart + 1 >= minSpeechFrames) onsets.add(speechStart * frameMs)
        return onsets
    }

    // ─── Extract Audio ────────────────────────────────────────────────────────

    private fun extractAudio(videoPath: String, outputPath: String, result: MethodChannel.Result) {
        Thread {
            try {
                val extractor = MediaExtractor()
                extractor.setDataSource(videoPath)
                var trackIndex = -1; var srcSampleRate = 44100; var srcChannels = 1
                for (i in 0 until extractor.trackCount) {
                    val fmt = extractor.getTrackFormat(i); val mime = fmt.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("audio/")) { trackIndex = i; if (fmt.containsKey(MediaFormat.KEY_SAMPLE_RATE)) srcSampleRate = fmt.getInteger(MediaFormat.KEY_SAMPLE_RATE); if (fmt.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) srcChannels = fmt.getInteger(MediaFormat.KEY_CHANNEL_COUNT); break }
                }
                if (trackIndex == -1) { extractor.release(); runOnUiThread { result.error("NO_AUDIO", "No audio track", null) }; return@Thread }
                extractor.selectTrack(trackIndex)
                val format = extractor.getTrackFormat(trackIndex); val mime = format.getString(MediaFormat.KEY_MIME)!!
                val decoder = MediaCodec.createDecoderByType(mime); decoder.configure(format, null, null, 0); decoder.start()
                val rawPcm = mutableListOf<ByteArray>(); var isEOS = false
                while (!isEOS) {
                    val inIdx = decoder.dequeueInputBuffer(10_000)
                    if (inIdx >= 0) { val inBuf = decoder.getInputBuffer(inIdx)!!; val sz = extractor.readSampleData(inBuf, 0); if (sz < 0) { decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM); isEOS = true } else { decoder.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0); extractor.advance() } }
                    val info = MediaCodec.BufferInfo()
                    var outIdx = decoder.dequeueOutputBuffer(info, 10_000)
                    while (outIdx != MediaCodec.INFO_TRY_AGAIN_LATER) {
                        if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val newFormat = decoder.outputFormat
                            if (newFormat.containsKey(MediaFormat.KEY_SAMPLE_RATE)) srcSampleRate = newFormat.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                            if (newFormat.containsKey(MediaFormat.KEY_CHANNEL_COUNT)) srcChannels = newFormat.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                        } else if (outIdx >= 0) {
                            val outBuf = decoder.getOutputBuffer(outIdx)!!
                            val bytes = ByteArray(info.size)
                            outBuf.position(info.offset)
                            outBuf.get(bytes)
                            rawPcm.add(bytes)
                            decoder.releaseOutputBuffer(outIdx, false)
                        }
                        if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) isEOS = true
                        if (isEOS) break
                        outIdx = decoder.dequeueOutputBuffer(info, 0)
                    }
                }
                decoder.stop(); decoder.release(); extractor.release()
                val resampled = resample(rawPcm, srcSampleRate, srcChannels)
                val fos = FileOutputStream(outputPath); fos.write(ByteArray(44)); fos.write(resampled); fos.close()
                writeWavHeader(outputPath, resampled.size.toLong(), TARGET_SAMPLE_RATE, TARGET_CHANNELS)
                runOnUiThread { result.success(outputPath) }
            } catch (e: Exception) { runOnUiThread { result.error("FAILED", e.message ?: "Unknown", null) } }
        }.start()
    }

    private fun resample(chunks: List<ByteArray>, srcRate: Int, srcChannels: Int): ByteArray {
        val totalSrc = chunks.sumOf { it.size } / (srcChannels * 2); val ratio = srcRate.toDouble() / TARGET_SAMPLE_RATE; val totalDst = (totalSrc / ratio).toInt()
        val out = ByteBuffer.allocate(totalDst * 2).order(ByteOrder.LITTLE_ENDIAN); val flat = ByteBuffer.allocate(chunks.sumOf { it.size }).order(ByteOrder.LITTLE_ENDIAN)
        for (c in chunks) flat.put(c); flat.rewind(); val srcShorts = flat.asShortBuffer(); val srcFrames = srcShorts.limit() / srcChannels
        for (i in 0 until totalDst) { val f = (i * ratio).toInt().coerceAtMost(srcFrames - 1); var sum = 0L; for (ch in 0 until srcChannels) sum += srcShorts.get(f * srcChannels + ch).toLong(); out.putShort((sum / srcChannels).toInt().coerceIn(-32768, 32767).toShort()) }
        return out.array()
    }

    private fun writeWavHeader(path: String, pcmBytes: Long, sampleRate: Int, channels: Int) {
        val raf = RandomAccessFile(path, "rw"); raf.seek(0); val buf = ByteBuffer.allocate(44).order(ByteOrder.LITTLE_ENDIAN); val byteRate = sampleRate * channels * 2
        buf.put("RIFF".toByteArray()); buf.putInt((pcmBytes + 36).toInt()); buf.put("WAVE".toByteArray()); buf.put("fmt ".toByteArray()); buf.putInt(16)
        buf.putShort(1); buf.putShort(channels.toShort()); buf.putInt(sampleRate); buf.putInt(byteRate); buf.putShort((channels * 2).toShort()); buf.putShort(16)
        buf.put("data".toByteArray()); buf.putInt(pcmBytes.toInt()); raf.write(buf.array()); raf.close()
    }

    private fun replaceAudioTrack(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        fileName: String,
        result: MethodChannel.Result
    ) {
        Thread {
            try {
                val resolvedVideo = resolveUriToFilePath(videoPath)
                val resolvedAudio = resolveUriToFilePath(audioPath)

                // ── 1. Extract video track ──
                val videoExtractor = MediaExtractor()
                videoExtractor.setDataSource(resolvedVideo)
                var videoTrackIndex = -1
                var videoFormat: MediaFormat? = null
                for (i in 0 until videoExtractor.trackCount) {
                    val format = videoExtractor.getTrackFormat(i)
                    val mime = format.getString(MediaFormat.KEY_MIME) ?: ""
                    if (mime.startsWith("video/")) {
                        videoTrackIndex = i
                        videoFormat = format
                        break
                    }
                }
                if (videoTrackIndex == -1) {
                    videoExtractor.release()
                    runOnUiThread { result.error("NO_VIDEO", "No video track found", null) }
                    return@Thread
                }
                videoExtractor.selectTrack(videoTrackIndex)

                // ── 2. Parse WAV header to get PCM parameters ──
                val wavFile = java.io.RandomAccessFile(resolvedAudio, "r")
                if (wavFile.length() < 44) {
                    wavFile.close()
                    videoExtractor.release()
                    runOnUiThread { result.error("BAD_WAV", "WAV file too small", null) }
                    return@Thread
                }
                val wavHeader = ByteArray(44)
                wavFile.readFully(wavHeader)
                val wavData = java.nio.ByteBuffer.wrap(wavHeader).order(java.nio.ByteOrder.LITTLE_ENDIAN)
                val audioChannels = wavData.getShort(22).toInt()
                val sampleRate = wavData.getInt(24)
                val bitsPerSample = wavData.getShort(34).toInt()
                val pcmDataSize = wavData.getInt(40)
                android.util.Log.d("MuxerPCM", "WAV: ${sampleRate}Hz, ${audioChannels}ch, ${bitsPerSample}bit, PCM=${pcmDataSize}bytes")

                // ── 3. Setup AAC encoder (no decoder needed for raw PCM) ──
                val aacMime = MediaFormat.MIMETYPE_AUDIO_AAC
                val encoderFormat = MediaFormat.createAudioFormat(aacMime, sampleRate, audioChannels)
                encoderFormat.setInteger(MediaFormat.KEY_AAC_PROFILE, MediaCodecInfo.CodecProfileLevel.AACObjectLC)
                encoderFormat.setInteger(MediaFormat.KEY_BIT_RATE, 128000)
                encoderFormat.setInteger(MediaFormat.KEY_MAX_INPUT_SIZE, 16384)

                val audioEncoder = MediaCodec.createEncoderByType(aacMime)
                audioEncoder.configure(encoderFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
                audioEncoder.start()

                // ── 4. Setup Muxer ──
                val muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
                val muxedVideoTrackIndex = muxer.addTrack(videoFormat!!)
                var muxedAudioTrackIndex = -1

                var videoDone = false
                var audioInputDone = false
                var audioEncoderDone = false
                var muxerStarted = false
                var pcmBytesRead = 0L
                val bytesPerSampleFrame = audioChannels * (bitsPerSample / 8)

                val videoBuffer = java.nio.ByteBuffer.allocate(2 * 1024 * 1024)
                val videoBufferInfo = MediaCodec.BufferInfo()
                val encBufferInfo = MediaCodec.BufferInfo()

                val startTimeMs = System.currentTimeMillis()
                while (!videoDone || !audioEncoderDone) {
                    if (System.currentTimeMillis() - startTimeMs > 60000) {
                        throw Exception("Muxing timed out (60s)")
                    }
                    var workDone = false

                    // ── Copy video samples ──
                    if (muxerStarted && !videoDone) {
                        videoBufferInfo.offset = 0
                        videoBufferInfo.size = videoExtractor.readSampleData(videoBuffer, 0)
                        if (videoBufferInfo.size < 0) {
                            videoDone = true
                        } else {
                            videoBufferInfo.presentationTimeUs = videoExtractor.sampleTime
                            videoBufferInfo.flags = videoExtractor.sampleFlags
                            muxer.writeSampleData(muxedVideoTrackIndex, videoBuffer, videoBufferInfo)
                            videoExtractor.advance()
                            workDone = true
                        }
                    }

                    // ── Feed raw PCM directly into encoder input (skip decoder entirely) ──
                    if (!audioInputDone) {
                        val inIdx = audioEncoder.dequeueInputBuffer(5000)
                        if (inIdx >= 0) {
                            val inBuf = audioEncoder.getInputBuffer(inIdx)!!
                            inBuf.clear()
                            val readSize = minOf(inBuf.remaining().toLong(), (pcmDataSize - pcmBytesRead)).toInt()
                            if (readSize <= 0) {
                                audioEncoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                audioInputDone = true
                            } else {
                                val pcmChunk = ByteArray(readSize)
                                wavFile.readFully(pcmChunk)
                                inBuf.put(pcmChunk)
                                val presentationTimeUs = (pcmBytesRead * 1000000L) / (sampleRate.toLong() * bytesPerSampleFrame)
                                audioEncoder.queueInputBuffer(inIdx, 0, readSize, presentationTimeUs, 0)
                                pcmBytesRead += readSize
                            }
                            workDone = true
                        }
                    }

                    // ── Drain encoder output → muxer ──
                    if (!audioEncoderDone) {
                        val outIdx = audioEncoder.dequeueOutputBuffer(encBufferInfo, 5000)
                        if (outIdx >= 0) {
                            val outBuf = audioEncoder.getOutputBuffer(outIdx)!!
                            if (muxedAudioTrackIndex != -1 && muxerStarted && encBufferInfo.size > 0) {
                                muxer.writeSampleData(muxedAudioTrackIndex, outBuf, encBufferInfo)
                            }
                            if ((encBufferInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) {
                                audioEncoderDone = true
                            }
                            audioEncoder.releaseOutputBuffer(outIdx, false)
                            workDone = true
                        } else if (outIdx == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                            val newFormat = audioEncoder.outputFormat
                            muxedAudioTrackIndex = muxer.addTrack(newFormat)
                            muxer.start()
                            muxerStarted = true
                            workDone = true
                        }
                    }

                    if (!workDone) {
                        try { Thread.sleep(5) } catch (_: Exception) {}
                    }
                }

                try { wavFile.close() } catch (_: Exception) {}
                try { videoExtractor.release() } catch (_: Exception) {}
                try { audioEncoder.stop(); audioEncoder.release() } catch (_: Exception) {}
                try { muxer.stop(); muxer.release() } catch (_: Exception) {}

                saveVideoToGallery(outputPath, fileName)
                runOnUiThread { result.success("Movies/SubtitleAI/$fileName") }
            } catch (e: Exception) {
                android.util.Log.e("MuxerPCM", "replaceAudioTrack failed", e)
                runOnUiThread { result.error("FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    private fun saveAudioToGallery(audioPath: String, fileName: String, result: MethodChannel.Result) {
        Thread {
            try {
                val sourceFile = File(audioPath)
                if (!sourceFile.exists() || sourceFile.length() == 0L) {
                    runOnUiThread { result.error("FILE_ERROR", "Audio file not found or empty", null) }
                    return@Thread
                }
                val destFileName = if (fileName.endsWith(".wav")) fileName else "$fileName.wav"
                
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Audio.Media.DISPLAY_NAME, destFileName)
                        put(MediaStore.Audio.Media.MIME_TYPE, "audio/wav")
                        put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/SubtitleAI")
                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Audio.Media.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                        ?: throw Exception("MediaStore insert returned null")
                    contentResolver.openOutputStream(uri)?.use { out -> sourceFile.inputStream().use { it.copyTo(out) } }
                        ?: throw Exception("Cannot open MediaStore output stream")
                    values.clear()
                    values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    @Suppress("DEPRECATION")
                    val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "SubtitleAI")
                    dir.mkdirs()
                    val dest = File(dir, destFileName)
                    sourceFile.copyTo(dest, overwrite = true)
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(dest.absolutePath), arrayOf("audio/wav"), null)
                }
                runOnUiThread { result.success("Music/SubtitleAI/$destFileName") }
            } catch (e: Exception) {
                runOnUiThread { result.error("FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }

    // Save a UTF-8 text file (e.g. .srt/.vtt) to Download/SubtitleAI so it can be
    // imported into CapCut / YouTube / other editors.
    private fun saveTextFile(content: String, fileName: String, mime: String, result: MethodChannel.Result) {
        Thread {
            try {
                val bytes = content.toByteArray(Charsets.UTF_8)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                        put(MediaStore.Downloads.MIME_TYPE, mime)
                        put(MediaStore.Downloads.RELATIVE_PATH, "Download/SubtitleAI")
                        put(MediaStore.Downloads.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
                        ?: throw Exception("MediaStore insert returned null")
                    contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
                        ?: throw Exception("Cannot open MediaStore output stream")
                    values.clear()
                    values.put(MediaStore.Downloads.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    @Suppress("DEPRECATION")
                    val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "SubtitleAI")
                    dir.mkdirs()
                    val dest = File(dir, fileName)
                    dest.writeBytes(bytes)
                    MediaScannerConnection.scanFile(applicationContext, arrayOf(dest.absolutePath), arrayOf(mime), null)
                }
                runOnUiThread { result.success("Download/SubtitleAI/$fileName") }
            } catch (e: Exception) {
                runOnUiThread { result.error("FAILED", e.message ?: "Unknown", null) }
            }
        }.start()
    }
}
