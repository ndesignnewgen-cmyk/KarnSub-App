package com.anniekaydee.subtitle_app

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.SurfaceTexture
import android.net.Uri
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.view.Choreographer
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * PRO_EDITOR_PLAN phase P — preview-engine PROTOTYPE (GO/NO-GO gate).
 *
 * Two ExoPlayers (main + picture-in-picture) decode into OES SurfaceTextures;
 * a dedicated GL thread composites them plus one RGBA overlay (text drawn by
 * Flutter) into a single Flutter Texture, once per display vsync.
 * Exposes live counters so the gate can be measured on real phones:
 * render fps, video frames/s, slow frames (> 1.5 vsync), seek latency.
 *
 * Method channel: com.anniekaydee.subtitle_app/previewengine
 */
class PreviewEngine(
    private val context: Context,
    private val textures: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private var entry: TextureRegistry.SurfaceTextureEntry? = null
    private var renderer: GlRenderer? = null
    private var main: ExoPlayer? = null
    private var pip: ExoPlayer? = null
    private val ui = Handler(Looper.getMainLooper())

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "create" -> create(call, result)
                "load" -> load(call, result)
                "play" -> { main?.play(); pip?.play(); result.success(null) }
                "pause" -> { main?.pause(); pip?.pause(); result.success(null) }
                "seek" -> {
                    val ms = (call.argument<Number>("ms") ?: 0).toLong()
                    renderer?.markSeek()
                    main?.seekTo(ms)
                    pip?.seekTo(ms)
                    result.success(null)
                }
                "setPip" -> {
                    renderer?.setPip(
                        (call.argument<Number>("x") ?: 0.7).toFloat(),
                        (call.argument<Number>("y") ?: 0.25).toFloat(),
                        (call.argument<Number>("scale") ?: 0.4).toFloat(),
                    )
                    result.success(null)
                }
                "setOverlay" -> {
                    val png = call.argument<ByteArray>("png")
                    val bmp = png?.let { BitmapFactory.decodeByteArray(it, 0, it.size) }
                    renderer?.setOverlay(bmp)
                    result.success(null)
                }
                "stats" -> result.success(renderer?.stats() ?: emptyMap<String, Any>())
                "dispose" -> { disposeAll(); result.success(null) }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("PREVIEW_ENGINE", e.message, null)
        }
    }

    private fun create(call: MethodCall, result: MethodChannel.Result) {
        disposeAll()
        val w = call.argument<Int>("width") ?: 1080
        val h = call.argument<Int>("height") ?: 1920
        val e = textures.createSurfaceTexture()
        e.surfaceTexture().setDefaultBufferSize(w, h)
        entry = e
        val r = GlRenderer(e.surfaceTexture(), w, h)
        if (!r.start()) {
            e.release()
            entry = null
            result.error("PREVIEW_ENGINE", "GL init failed", null)
            return
        }
        renderer = r
        result.success(e.id())
    }

    private fun load(call: MethodCall, result: MethodChannel.Result) {
        val r = renderer ?: return result.error("PREVIEW_ENGINE", "create() first", null)
        val mainPath = call.argument<String>("main")
            ?: return result.error("PREVIEW_ENGINE", "main missing", null)
        val pipPath = call.argument<String>("pip")
        main?.release(); pip?.release()
        main = player(mainPath, r.surfaceA, volume = 1f) { r.setAspectA(it) }
        pip = pipPath?.let { player(it, r.surfaceB, volume = 0f) { s -> r.setAspectB(s) } }
        r.pipEnabled = pip != null
        result.success(null)
    }

    private fun player(path: String, surface: Surface, volume: Float, onSize: (Float) -> Unit) =
        ExoPlayer.Builder(context).build().apply {
            setVideoSurface(surface)
            this.volume = volume
            repeatMode = Player.REPEAT_MODE_ALL
            addListener(object : Player.Listener {
                override fun onVideoSizeChanged(videoSize: VideoSize) {
                    if (videoSize.width > 0 && videoSize.height > 0) {
                        val w = videoSize.width * videoSize.pixelWidthHeightRatio
                        onSize(w / videoSize.height)
                    }
                }
            })
            setMediaItem(MediaItem.fromUri(Uri.fromFile(File(path))))
            prepare()
        }

    private fun disposeAll() {
        main?.release(); main = null
        pip?.release(); pip = null
        renderer?.stop(); renderer = null
        entry?.release(); entry = null
    }
}

/** GL thread: EGL setup, OES inputs, vsync-paced compositing, counters. */
private class GlRenderer(
    private val output: SurfaceTexture,
    private val outW: Int,
    private val outH: Int,
) {
    private val thread = HandlerThread("PreviewEngineGL")
    private lateinit var handler: Handler

    private var display: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var texA = 0
    private var texB = 0
    private var texOverlay = 0
    private lateinit var stA: SurfaceTexture
    private lateinit var stB: SurfaceTexture
    lateinit var surfaceA: Surface
    lateinit var surfaceB: Surface

    @Volatile private var newA = false
    @Volatile private var newB = false
    @Volatile var pipEnabled = false
    @Volatile private var aspectA = 9f / 16f
    @Volatile private var aspectB = 16f / 9f
    @Volatile private var pipX = 0.7f
    @Volatile private var pipY = 0.25f
    @Volatile private var pipScale = 0.4f
    @Volatile private var pendingOverlay: Bitmap? = null
    @Volatile private var overlayDirty = false
    private var hasOverlay = false

    private var oesProgram = 0
    private var texProgram = 0
    private val stMatrix = FloatArray(16)
    private val quad: FloatBuffer = ByteBuffer.allocateDirect(4 * 4 * 4)
        .order(ByteOrder.nativeOrder()).asFloatBuffer()

    // Counters (read from the platform thread via stats()).
    @Volatile private var running = false
    private var lastFrameNs = 0L
    private var windowStartNs = 0L
    private var windowRenders = 0
    private var windowVideo = 0
    @Volatile private var renderFps = 0.0
    @Volatile private var videoFps = 0.0
    @Volatile private var slowFrames = 0
    @Volatile private var totalFrames = 0
    @Volatile private var lastDrawMs = 0.0
    @Volatile private var maxDrawMs = 0.0
    @Volatile private var seekStartNs = 0L
    @Volatile private var lastSeekMs = -1.0

    private val frameCallback = object : Choreographer.FrameCallback {
        override fun doFrame(frameTimeNanos: Long) {
            if (!running) return
            drawFrame(frameTimeNanos)
            Choreographer.getInstance().postFrameCallback(this)
        }
    }

    fun start(): Boolean {
        thread.start()
        handler = Handler(thread.looper)
        val latch = CountDownLatch(1)
        var ok = false
        handler.post {
            ok = try { initGl(); true } catch (e: Exception) { false }
            latch.countDown()
            if (ok) {
                running = true
                Choreographer.getInstance().postFrameCallback(frameCallback)
            }
        }
        latch.await(3, TimeUnit.SECONDS)
        return ok
    }

    fun stop() {
        running = false
        val latch = CountDownLatch(1)
        handler.post {
            try {
                surfaceA.release(); surfaceB.release()
                stA.release(); stB.release()
                EGL14.eglMakeCurrent(display, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
                EGL14.eglDestroySurface(display, eglSurface)
                EGL14.eglDestroyContext(display, eglContext)
                EGL14.eglTerminate(display)
            } catch (_: Exception) {}
            latch.countDown()
        }
        latch.await(2, TimeUnit.SECONDS)
        thread.quitSafely()
    }

    fun setAspectA(a: Float) { aspectA = a }
    fun setAspectB(a: Float) { aspectB = a }
    fun setPip(x: Float, y: Float, scale: Float) { pipX = x; pipY = y; pipScale = scale }
    fun setOverlay(b: Bitmap?) { pendingOverlay = b; overlayDirty = true }
    fun markSeek() { seekStartNs = System.nanoTime() }

    fun stats(): Map<String, Any> = mapOf(
        "renderFps" to renderFps,
        "videoFps" to videoFps,
        "slowFrames" to slowFrames,
        "totalFrames" to totalFrames,
        "lastDrawMs" to lastDrawMs,
        "maxDrawMs" to maxDrawMs,
        "seekLatencyMs" to lastSeekMs,
        "width" to outW,
        "height" to outH,
    )

    // ── GL setup ──

    private fun initGl() {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        val ver = IntArray(2)
        check(EGL14.eglInitialize(display, ver, 0, ver, 1)) { "eglInitialize" }
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8, EGL14.EGL_GREEN_SIZE, 8, EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8, EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val num = IntArray(1)
        check(EGL14.eglChooseConfig(display, attribs, 0, configs, 0, 1, num, 0) && num[0] > 0) { "config" }
        eglContext = EGL14.eglCreateContext(
            display, configs[0], EGL14.EGL_NO_CONTEXT,
            intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE), 0,
        )
        check(eglContext != EGL14.EGL_NO_CONTEXT) { "context" }
        eglSurface = EGL14.eglCreateWindowSurface(
            display, configs[0], Surface(output), intArrayOf(EGL14.EGL_NONE), 0,
        )
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "surface" }
        check(EGL14.eglMakeCurrent(display, eglSurface, eglSurface, eglContext)) { "makeCurrent" }

        val ids = IntArray(3)
        GLES20.glGenTextures(3, ids, 0)
        texA = ids[0]; texB = ids[1]; texOverlay = ids[2]
        for (t in intArrayOf(texA, texB)) {
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, t)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)
        }
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texOverlay)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)

        stA = SurfaceTexture(texA).apply {
            setOnFrameAvailableListener({
                newA = true
                if (seekStartNs != 0L) {
                    lastSeekMs = (System.nanoTime() - seekStartNs) / 1e6
                    seekStartNs = 0L
                }
            }, handler)
        }
        stB = SurfaceTexture(texB).apply { setOnFrameAvailableListener({ newB = true }, handler) }
        surfaceA = Surface(stA)
        surfaceB = Surface(stB)

        oesProgram = program(VS, FS_OES)
        texProgram = program(VS, FS_2D)
        GLES20.glEnable(GLES20.GL_BLEND)
        // Bitmaps uploaded with GLUtils are premultiplied.
        GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
    }

    private fun program(vs: String, fs: String): Int {
        fun shader(type: Int, src: String): Int {
            val s = GLES20.glCreateShader(type)
            GLES20.glShaderSource(s, src)
            GLES20.glCompileShader(s)
            val ok = IntArray(1)
            GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, ok, 0)
            check(ok[0] != 0) { "shader: " + GLES20.glGetShaderInfoLog(s) }
            return s
        }
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, shader(GLES20.GL_VERTEX_SHADER, vs))
        GLES20.glAttachShader(p, shader(GLES20.GL_FRAGMENT_SHADER, fs))
        GLES20.glLinkProgram(p)
        val ok = IntArray(1)
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, ok, 0)
        check(ok[0] != 0) { "link: " + GLES20.glGetProgramInfoLog(p) }
        return p
    }

    // ── Per-vsync compositing ──

    private fun drawFrame(frameTimeNanos: Long) {
        val t0 = System.nanoTime()
        var videoUpdated = false
        if (newA) { newA = false; stA.updateTexImage(); videoUpdated = true }
        if (newB) { newB = false; stB.updateTexImage() }
        if (overlayDirty) {
            overlayDirty = false
            val b = pendingOverlay
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, texOverlay)
            if (b != null) {
                GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, b, 0)
                hasOverlay = true
            } else {
                hasOverlay = false
            }
        }

        GLES20.glViewport(0, 0, outW, outH)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)

        // Main video: fit inside the canvas.
        val canvasAspect = outW.toFloat() / outH
        val (mw, mh) = if (aspectA > canvasAspect) 1f to (canvasAspect / aspectA)
        else (aspectA / canvasAspect) to 1f
        drawOes(texA, stA, 0f, 0f, mw, mh)

        if (pipEnabled) {
            val pw = pipScale
            val ph = pipScale * canvasAspect / aspectB
            drawOes(texB, stB, pipX * 2 - 1, 1 - pipY * 2, pw, ph)
        }
        if (hasOverlay) draw2d(texOverlay)

        EGL14.eglSwapBuffers(display, eglSurface)

        // Counters.
        val drawMs = (System.nanoTime() - t0) / 1e6
        lastDrawMs = drawMs
        if (drawMs > maxDrawMs) maxDrawMs = drawMs
        totalFrames++
        if (lastFrameNs != 0L && frameTimeNanos - lastFrameNs > 25_000_000L) slowFrames++ // > 1.5 × 16.7 ms
        lastFrameNs = frameTimeNanos
        if (windowStartNs == 0L) windowStartNs = frameTimeNanos
        windowRenders++
        if (videoUpdated) windowVideo++
        val span = frameTimeNanos - windowStartNs
        if (span >= 1_000_000_000L) {
            renderFps = windowRenders * 1e9 / span
            videoFps = windowVideo * 1e9 / span
            windowRenders = 0; windowVideo = 0; windowStartNs = frameTimeNanos
        }
    }

    /** Quad centred at (cx, cy) in clip space with half-size (hw, hh). */
    private fun drawOes(tex: Int, st: SurfaceTexture, cx: Float, cy: Float, hw: Float, hh: Float) {
        st.getTransformMatrix(stMatrix)
        GLES20.glUseProgram(oesProgram)
        bindQuad(oesProgram, cx, cy, hw, hh)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(oesProgram, "uSt"), 1, false, stMatrix, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, tex)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(oesProgram, "uTex"), 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun draw2d(tex: Int) {
        GLES20.glUseProgram(texProgram)
        bindQuad(texProgram, 0f, 0f, 1f, 1f)
        // Bitmaps are top-down; flip V with the st matrix.
        val flip = floatArrayOf(1f, 0f, 0f, 0f, 0f, -1f, 0f, 0f, 0f, 0f, 1f, 0f, 0f, 1f, 0f, 1f)
        GLES20.glUniformMatrix4fv(GLES20.glGetUniformLocation(texProgram, "uSt"), 1, false, flip, 0)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, tex)
        GLES20.glUniform1i(GLES20.glGetUniformLocation(texProgram, "uTex"), 0)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun bindQuad(prog: Int, cx: Float, cy: Float, hw: Float, hh: Float) {
        // x, y, u, v
        quad.clear()
        quad.put(floatArrayOf(
            cx - hw, cy - hh, 0f, 0f,
            cx + hw, cy - hh, 1f, 0f,
            cx - hw, cy + hh, 0f, 1f,
            cx + hw, cy + hh, 1f, 1f,
        ))
        val pos = GLES20.glGetAttribLocation(prog, "aPos")
        val uv = GLES20.glGetAttribLocation(prog, "aUv")
        quad.position(0)
        GLES20.glVertexAttribPointer(pos, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(pos)
        quad.position(2)
        GLES20.glVertexAttribPointer(uv, 2, GLES20.GL_FLOAT, false, 16, quad)
        GLES20.glEnableVertexAttribArray(uv)
    }

    companion object {
        private const val VS = """
            attribute vec2 aPos;
            attribute vec2 aUv;
            uniform mat4 uSt;
            varying vec2 vUv;
            void main() {
                gl_Position = vec4(aPos, 0.0, 1.0);
                vUv = (uSt * vec4(aUv, 0.0, 1.0)).xy;
            }
        """
        private const val FS_OES = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES uTex;
            varying vec2 vUv;
            void main() { gl_FragColor = texture2D(uTex, vUv); }
        """
        private const val FS_2D = """
            precision mediump float;
            uniform sampler2D uTex;
            varying vec2 vUv;
            void main() { gl_FragColor = texture2D(uTex, vUv); }
        """
    }
}
