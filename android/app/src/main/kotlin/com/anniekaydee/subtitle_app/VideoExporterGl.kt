package com.anniekaydee.subtitle_app

import android.graphics.Bitmap
import android.graphics.SurfaceTexture
import android.media.MediaCodec
import android.media.MediaCodecInfo
import android.media.MediaExtractor
import android.media.MediaFormat
import android.media.MediaMuxer
import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.opengl.GLUtils
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer

/**
 * GPU video transcoder: decoder → OES texture → OpenGL compose (video + subtitle
 * overlay) → encoder input Surface → MediaMuxer. No per-pixel CPU work, hardware
 * codec where available → much faster than the bitmap pipeline.
 *
 * Throws on any failure so the caller can fall back to the CPU pipeline.
 */
class VideoExporterGl {

    private var eglDisplay: EGLDisplay = EGL14.EGL_NO_DISPLAY
    private var eglContext: EGLContext = EGL14.EGL_NO_CONTEXT
    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    private var oesTexId = 0
    private var overlayTexId = 0
    private lateinit var surfaceTexture: SurfaceTexture
    private lateinit var decoderSurface: Surface

    private val frameSync = Object()
    private var frameAvailable = false
    private var lastOverlay: Bitmap? = null

    private var oesProgram = 0
    private var ovProgram = 0
    private var oesPos = 0; private var oesTex = 0; private var oesMat = 0; private var oesSampler = 0
    private var ovPos = 0; private var ovTex = 0; private var ovSampler = 0

    private lateinit var posBuf: FloatBuffer
    private lateinit var oesTexBuf: FloatBuffer
    private lateinit var ovTexBuf: FloatBuffer

    private var vidW = 0
    private var vidH = 0
    // Output (encoder) dimensions — equal to vidW/vidH unless a target size is
    // given (used by clip-merge to normalize different-sized clips).
    private var outW = 0
    private var outH = 0

    fun export(
        inputPath: String,
        outputPath: String,
        onProgress: (Double) -> Unit,
        subtitleProvider: (Long) -> Bitmap?,
        keptRegions: List<Pair<Long, Long>>? = null,
        targetW: Int = 0,
        targetH: Int = 0,
    ) {
        var extractor: MediaExtractor? = null
        var audioExtractor: MediaExtractor? = null
        var decoder: MediaCodec? = null
        var encoder: MediaCodec? = null
        var encoderInput: Surface? = null
        var muxer: MediaMuxer? = null
        try {
            extractor = MediaExtractor()
            extractor.setDataSource(inputPath)
            var videoTrack = -1
            var audioTrack = -1
            for (i in 0 until extractor.trackCount) {
                val mime = extractor.getTrackFormat(i).getString(MediaFormat.KEY_MIME) ?: ""
                if (mime.startsWith("video/") && videoTrack == -1) videoTrack = i
                if (mime.startsWith("audio/") && audioTrack == -1) audioTrack = i
            }
            if (videoTrack == -1) throw RuntimeException("no video track")

            val videoFormat = extractor.getTrackFormat(videoTrack)
            vidW = videoFormat.getInteger(MediaFormat.KEY_WIDTH)
            vidH = videoFormat.getInteger(MediaFormat.KEY_HEIGHT)
            // Portrait phone videos often DON'T carry "rotation-degrees" in the
            // track format — fall back to MediaMetadataRetriever (the documented
            // source). Without this the output muxer gets no orientation hint and
            // the clip plays sideways. Mirrors MainActivity.readRotation().
            var rotation = if (videoFormat.containsKey("rotation-degrees"))
                videoFormat.getInteger("rotation-degrees") else 0
            if (rotation == 0) {
                try {
                    val mmr = android.media.MediaMetadataRetriever()
                    mmr.setDataSource(inputPath)
                    rotation = mmr.extractMetadata(
                        android.media.MediaMetadataRetriever.METADATA_KEY_VIDEO_ROTATION
                    )?.toIntOrNull() ?: 0
                    mmr.release()
                } catch (_: Exception) {}
            }
            val frameRate = if (videoFormat.containsKey(MediaFormat.KEY_FRAME_RATE))
                videoFormat.getInteger(MediaFormat.KEY_FRAME_RATE) else 30
            val bitRate = if (videoFormat.containsKey(MediaFormat.KEY_BIT_RATE))
                videoFormat.getInteger(MediaFormat.KEY_BIT_RATE) else 6_000_000
            val durationUs = if (videoFormat.containsKey(MediaFormat.KEY_DURATION))
                videoFormat.getLong(MediaFormat.KEY_DURATION) else 0L

            // When a target size is given (clip-merge normalize), encode at that
            // size and BAKE rotation into the pixels (output orientation 0) so all
            // clips become uniform and can be concatenated.
            val bake = targetW > 0 && targetH > 0
            outW = if (bake) targetW else vidW
            outH = if (bake) targetH else vidH

            // ── Encoder with input Surface (must support COLOR_FormatSurface) ──
            encoder = MediaCodec.createEncoderByType(MediaFormat.MIMETYPE_VIDEO_AVC)
            val encFormat = MediaFormat.createVideoFormat(MediaFormat.MIMETYPE_VIDEO_AVC, outW, outH).apply {
                setInteger(MediaFormat.KEY_COLOR_FORMAT,
                    MediaCodecInfo.CodecCapabilities.COLOR_FormatSurface)
                setInteger(MediaFormat.KEY_BIT_RATE, bitRate.coerceIn(1_000_000, 16_000_000))
                setInteger(MediaFormat.KEY_FRAME_RATE, frameRate)
                setInteger(MediaFormat.KEY_I_FRAME_INTERVAL, 2)
            }
            encoder.configure(encFormat, null, null, MediaCodec.CONFIGURE_FLAG_ENCODE)
            encoderInput = encoder.createInputSurface()
            encoder.start()

            // ── EGL on the encoder input surface ──
            initEgl(encoderInput)
            makeCurrent()
            setupGl()
            // For normalize mode: build an aspect-fit (letterbox) quad so the
            // RAW frame fills the target without distortion. Rotation is left to
            // the muxer orientation hint (same as the normal export path).
            if (bake) setupFitQuad()

            // ── Decoder → our SurfaceTexture ──
            decoder = MediaCodec.createDecoderByType(videoFormat.getString(MediaFormat.KEY_MIME)!!)
            decoder.configure(videoFormat, decoderSurface, null, 0)
            decoder.start()
            extractor.selectTrack(videoTrack)

            // ── Muxer + audio ──
            muxer = MediaMuxer(outputPath, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4)
            // Always keep the orientation hint (we never rotate pixels in GL —
            // only scale). Clips from the same camera share rotation, so the
            // re-encoded temps + their hints stay consistent for concat.
            if (rotation != 0) muxer.setOrientationHint(rotation)
            var audioFormat: MediaFormat? = null
            if (audioTrack != -1) {
                try {
                    audioExtractor = MediaExtractor()
                    audioExtractor.setDataSource(inputPath)
                    audioExtractor.selectTrack(audioTrack)
                    audioFormat = audioExtractor.getTrackFormat(audioTrack)
                } catch (_: Exception) {
                    audioExtractor?.release(); audioExtractor = null
                }
            }

            var muxVideo = -1
            var muxAudio = -1
            var muxerStarted = false

            val stMatrix = FloatArray(16)
            val decInfo = MediaCodec.BufferInfo()
            val encInfo = MediaCodec.BufferInfo()
            var inputDone = false
            var decodeDone = false
            var muxDone = false
            var lastPtsUs = -1L
            var lastPct = -1

            while (!muxDone) {
                // 1. feed decoder
                if (!inputDone) {
                    val inIdx = decoder.dequeueInputBuffer(10_000L)
                    if (inIdx >= 0) {
                        val buf = decoder.getInputBuffer(inIdx)!!
                        val sz = extractor.readSampleData(buf, 0)
                        if (sz < 0) {
                            decoder.queueInputBuffer(inIdx, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(inIdx, 0, sz, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }

                // 2. drain decoder → render to encoder surface
                if (!decodeDone) {
                    val st = decoder.dequeueOutputBuffer(decInfo, 5_000L)
                    if (st >= 0) {
                        val eos = decInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        val presentUs = decInfo.presentationTimeUs
                        val keepFrame = keptRegions == null || keptRegions.isEmpty() || keptRegions.any { presentUs >= it.first && presentUs <= it.second }
                        val render = decInfo.size != 0 && !eos && keepFrame

                        if (decInfo.size != 0 && !eos && !keepFrame) {
                            decoder.releaseOutputBuffer(st, false)
                        } else {
                            decoder.releaseOutputBuffer(st, render)
                            if (render) {
                                awaitNewImage()
                                surfaceTexture.getTransformMatrix(stMatrix)
                                drawFrame(stMatrix, subtitleProvider(presentUs))
                                val newPts = mapOriginalToNewPts(presentUs, keptRegions)
                                val pts = maxOf(newPts, lastPtsUs + 1)
                                lastPtsUs = pts
                                EGLExt.eglPresentationTimeANDROID(eglDisplay, eglSurface, pts * 1000L)
                                EGL14.eglSwapBuffers(eglDisplay, eglSurface)
                                if (durationUs > 0L) {
                                    val pct = ((presentUs.toDouble() / durationUs) * 100).toInt()
                                    if (pct != lastPct) {
                                        lastPct = pct
                                        onProgress(0.10 + (presentUs.toDouble() / durationUs).coerceIn(0.0, 1.0) * 0.82)
                                    }
                                }
                            }
                        }
                        if (eos) {
                            encoder.signalEndOfInputStream()
                            decodeDone = true
                        }
                    }
                }

                // 3. drain encoder → muxer
                while (true) {
                    val st = encoder.dequeueOutputBuffer(encInfo, 0)
                    if (st == MediaCodec.INFO_TRY_AGAIN_LATER) break
                    if (st == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        muxVideo = muxer.addTrack(encoder.outputFormat)
                        audioFormat?.let { muxAudio = muxer.addTrack(it) }
                        muxer.start()
                        muxerStarted = true
                        continue
                    }
                    if (st >= 0) {
                        val isCfg = encInfo.flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                        val isEos = encInfo.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        if (encInfo.size > 0 && !isCfg && muxerStarted) {
                            val out = encoder.getOutputBuffer(st)!!
                            out.position(encInfo.offset)
                            out.limit(encInfo.offset + encInfo.size)
                            muxer.writeSampleData(muxVideo, out, encInfo)
                        }
                        encoder.releaseOutputBuffer(st, false)
                        if (isEos) { muxDone = true; break }
                    }
                }
            }

            // 4. copy audio (compressed, no re-encode)
            val aEx = audioExtractor
            if (aEx != null && muxAudio != -1 && muxerStarted) {
                try {
                    val abuf = ByteBuffer.allocate(1 shl 19)
                    val aInfo = MediaCodec.BufferInfo()
                    while (true) {
                        val sz = aEx.readSampleData(abuf, 0)
                        if (sz < 0) break
                        val sampleTimeUs = aEx.sampleTime
                        val keepAudio = keptRegions == null || keptRegions.isEmpty() || keptRegions.any { sampleTimeUs >= it.first && sampleTimeUs <= it.second }
                        if (keepAudio) {
                            aInfo.offset = 0
                            aInfo.size = sz
                            aInfo.presentationTimeUs = mapOriginalToNewPts(sampleTimeUs, keptRegions)
                            aInfo.flags = if (aEx.sampleFlags and MediaExtractor.SAMPLE_FLAG_SYNC != 0)
                                MediaCodec.BUFFER_FLAG_KEY_FRAME else 0
                            muxer.writeSampleData(muxAudio, abuf, aInfo)
                        }
                        aEx.advance()
                    }
                } catch (_: Exception) {
                    // keep video-only on audio failure
                }
            }

            muxer.stop()
        } finally {
            try { decoder?.stop() } catch (_: Exception) {}
            try { decoder?.release() } catch (_: Exception) {}
            try { encoder?.stop() } catch (_: Exception) {}
            try { encoder?.release() } catch (_: Exception) {}
            try { encoderInput?.release() } catch (_: Exception) {}
            try { extractor?.release() } catch (_: Exception) {}
            try { audioExtractor?.release() } catch (_: Exception) {}
            try { muxer?.release() } catch (_: Exception) {}
            releaseGl()
        }
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

    // ─── EGL ─────────────────────────────────────────────────────────────────

    private fun initEgl(surface: Surface) {
        eglDisplay = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        if (eglDisplay == EGL14.EGL_NO_DISPLAY) throw RuntimeException("no EGL display")
        val version = IntArray(2)
        if (!EGL14.eglInitialize(eglDisplay, version, 0, version, 1))
            throw RuntimeException("eglInitialize failed")
        val attribs = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGLExt.EGL_RECORDABLE_ANDROID, 1,
            EGL14.EGL_NONE,
        )
        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfig = IntArray(1)
        if (!EGL14.eglChooseConfig(eglDisplay, attribs, 0, configs, 0, 1, numConfig, 0) || numConfig[0] <= 0)
            throw RuntimeException("eglChooseConfig failed")
        val ctxAttribs = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)
        eglContext = EGL14.eglCreateContext(eglDisplay, configs[0], EGL14.EGL_NO_CONTEXT, ctxAttribs, 0)
        if (eglContext == EGL14.EGL_NO_CONTEXT) throw RuntimeException("eglCreateContext failed")
        eglSurface = EGL14.eglCreateWindowSurface(eglDisplay, configs[0], surface, intArrayOf(EGL14.EGL_NONE), 0)
        if (eglSurface == EGL14.EGL_NO_SURFACE) throw RuntimeException("eglCreateWindowSurface failed")
    }

    private fun makeCurrent() {
        if (!EGL14.eglMakeCurrent(eglDisplay, eglSurface, eglSurface, eglContext))
            throw RuntimeException("eglMakeCurrent failed")
    }

    private fun releaseGl() {
        try { lastOverlay = null } catch (_: Exception) {}
        if (eglDisplay != EGL14.EGL_NO_DISPLAY) {
            EGL14.eglMakeCurrent(eglDisplay, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_SURFACE, EGL14.EGL_NO_CONTEXT)
            if (eglSurface != EGL14.EGL_NO_SURFACE) EGL14.eglDestroySurface(eglDisplay, eglSurface)
            if (eglContext != EGL14.EGL_NO_CONTEXT) EGL14.eglDestroyContext(eglDisplay, eglContext)
            EGL14.eglTerminate(eglDisplay)
        }
        try { if (::surfaceTexture.isInitialized) surfaceTexture.release() } catch (_: Exception) {}
        try { if (::decoderSurface.isInitialized) decoderSurface.release() } catch (_: Exception) {}
        eglDisplay = EGL14.EGL_NO_DISPLAY
        eglContext = EGL14.EGL_NO_CONTEXT
        eglSurface = EGL14.EGL_NO_SURFACE
    }

    // ─── GL setup ──────────────────────────────────────────────────────────────

    private fun setupGl() {
        oesProgram = buildProgram(VERT_OES, FRAG_OES)
        oesPos = GLES20.glGetAttribLocation(oesProgram, "aPosition")
        oesTex = GLES20.glGetAttribLocation(oesProgram, "aTexCoord")
        oesMat = GLES20.glGetUniformLocation(oesProgram, "uTexMatrix")
        oesSampler = GLES20.glGetUniformLocation(oesProgram, "sTexture")

        ovProgram = buildProgram(VERT_OV, FRAG_OV)
        ovPos = GLES20.glGetAttribLocation(ovProgram, "aPosition")
        ovTex = GLES20.glGetAttribLocation(ovProgram, "aTexCoord")
        ovSampler = GLES20.glGetUniformLocation(ovProgram, "sTexture")

        posBuf = floatBuf(floatArrayOf(-1f, -1f, 1f, -1f, -1f, 1f, 1f, 1f))
        oesTexBuf = floatBuf(floatArrayOf(0f, 0f, 1f, 0f, 0f, 1f, 1f, 1f))
        ovTexBuf = floatBuf(floatArrayOf(0f, 1f, 1f, 1f, 0f, 0f, 1f, 0f))

        val tex = IntArray(2)
        GLES20.glGenTextures(2, tex, 0)
        oesTexId = tex[0]
        overlayTexId = tex[1]

        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexId)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTexId)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
        GLES20.glTexParameteri(GLES20.GL_TEXTURE_2D, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

        surfaceTexture = SurfaceTexture(oesTexId)
        surfaceTexture.setOnFrameAvailableListener {
            synchronized(frameSync) { frameAvailable = true; frameSync.notifyAll() }
        }
        decoderSurface = Surface(surfaceTexture)
    }

    private fun awaitNewImage() {
        synchronized(frameSync) {
            val deadline = System.currentTimeMillis() + 2500
            while (!frameAvailable) {
                val wait = deadline - System.currentTimeMillis()
                if (wait <= 0) throw RuntimeException("frame wait timed out")
                frameSync.wait(wait)
            }
            frameAvailable = false
        }
        surfaceTexture.updateTexImage()
    }

    /// Build an aspect-fit (letterbox) position quad so the RAW frame
    /// (vidW×vidH) fills the output (outW×outH) without distortion. No rotation
    /// is applied here — the muxer orientation hint handles display rotation.
    private fun setupFitQuad() {
        if (vidW <= 0 || vidH <= 0 || outW <= 0 || outH <= 0) return
        val scale = minOf(outW.toFloat() / vidW, outH.toFloat() / vidH)
        val hw = (vidW * scale) / outW // half-width in NDC (0..1)
        val hh = (vidH * scale) / outH
        // Corners in posBuf order: BL, BR, TL, TR.
        posBuf = floatBuf(floatArrayOf(-hw, -hh, hw, -hh, -hw, hh, hw, hh))
    }

    private fun drawFrame(stMatrix: FloatArray, overlay: Bitmap?) {
        GLES20.glViewport(0, 0, outW, outH)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glDisable(GLES20.GL_BLEND)

        // video (external OES)
        GLES20.glUseProgram(oesProgram)
        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTexId)
        GLES20.glUniform1i(oesSampler, 0)
        GLES20.glUniformMatrix4fv(oesMat, 1, false, stMatrix, 0)
        GLES20.glEnableVertexAttribArray(oesPos)
        GLES20.glVertexAttribPointer(oesPos, 2, GLES20.GL_FLOAT, false, 0, posBuf)
        GLES20.glEnableVertexAttribArray(oesTex)
        GLES20.glVertexAttribPointer(oesTex, 2, GLES20.GL_FLOAT, false, 0, oesTexBuf)
        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
        GLES20.glDisableVertexAttribArray(oesPos)
        GLES20.glDisableVertexAttribArray(oesTex)

        // subtitle overlay (premultiplied-alpha 2D texture)
        if (overlay != null && !overlay.isRecycled) {
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTexId)
            if (overlay !== lastOverlay) {
                GLUtils.texImage2D(GLES20.GL_TEXTURE_2D, 0, overlay, 0)
                lastOverlay = overlay
            }
            GLES20.glEnable(GLES20.GL_BLEND)
            GLES20.glBlendFunc(GLES20.GL_ONE, GLES20.GL_ONE_MINUS_SRC_ALPHA)
            GLES20.glUseProgram(ovProgram)
            GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
            GLES20.glBindTexture(GLES20.GL_TEXTURE_2D, overlayTexId)
            GLES20.glUniform1i(ovSampler, 0)
            GLES20.glEnableVertexAttribArray(ovPos)
            GLES20.glVertexAttribPointer(ovPos, 2, GLES20.GL_FLOAT, false, 0, posBuf)
            GLES20.glEnableVertexAttribArray(ovTex)
            GLES20.glVertexAttribPointer(ovTex, 2, GLES20.GL_FLOAT, false, 0, ovTexBuf)
            GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
            GLES20.glDisableVertexAttribArray(ovPos)
            GLES20.glDisableVertexAttribArray(ovTex)
            GLES20.glDisable(GLES20.GL_BLEND)
        }
    }

    private fun floatBuf(data: FloatArray): FloatBuffer {
        val b = ByteBuffer.allocateDirect(data.size * 4).order(ByteOrder.nativeOrder()).asFloatBuffer()
        b.put(data); b.position(0); return b
    }

    private fun buildProgram(vert: String, frag: String): Int {
        val v = loadShader(GLES20.GL_VERTEX_SHADER, vert)
        val f = loadShader(GLES20.GL_FRAGMENT_SHADER, frag)
        val p = GLES20.glCreateProgram()
        GLES20.glAttachShader(p, v)
        GLES20.glAttachShader(p, f)
        GLES20.glLinkProgram(p)
        val status = IntArray(1)
        GLES20.glGetProgramiv(p, GLES20.GL_LINK_STATUS, status, 0)
        if (status[0] != GLES20.GL_TRUE) {
            val log = GLES20.glGetProgramInfoLog(p)
            GLES20.glDeleteProgram(p)
            throw RuntimeException("link failed: $log")
        }
        return p
    }

    private fun loadShader(type: Int, src: String): Int {
        val s = GLES20.glCreateShader(type)
        GLES20.glShaderSource(s, src)
        GLES20.glCompileShader(s)
        val status = IntArray(1)
        GLES20.glGetShaderiv(s, GLES20.GL_COMPILE_STATUS, status, 0)
        if (status[0] != GLES20.GL_TRUE) {
            val log = GLES20.glGetShaderInfoLog(s)
            GLES20.glDeleteShader(s)
            throw RuntimeException("shader compile failed: $log")
        }
        return s
    }

    companion object {
        private const val VERT_OES =
            "uniform mat4 uTexMatrix;\n" +
            "attribute vec4 aPosition;\n" +
            "attribute vec4 aTexCoord;\n" +
            "varying vec2 vTexCoord;\n" +
            "void main() {\n" +
            "  gl_Position = aPosition;\n" +
            "  vTexCoord = (uTexMatrix * aTexCoord).xy;\n" +
            "}\n"
        private const val FRAG_OES =
            "#extension GL_OES_EGL_image_external : require\n" +
            "precision mediump float;\n" +
            "varying vec2 vTexCoord;\n" +
            "uniform samplerExternalOES sTexture;\n" +
            "void main() { gl_FragColor = texture2D(sTexture, vTexCoord); }\n"
        private const val VERT_OV =
            "attribute vec4 aPosition;\n" +
            "attribute vec2 aTexCoord;\n" +
            "varying vec2 vTexCoord;\n" +
            "void main() { gl_Position = aPosition; vTexCoord = aTexCoord; }\n"
        private const val FRAG_OV =
            "precision mediump float;\n" +
            "varying vec2 vTexCoord;\n" +
            "uniform sampler2D sTexture;\n" +
            "void main() { gl_FragColor = texture2D(sTexture, vTexCoord); }\n"
    }
}
