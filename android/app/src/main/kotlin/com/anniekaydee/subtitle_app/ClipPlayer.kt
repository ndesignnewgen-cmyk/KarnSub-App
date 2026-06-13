package com.anniekaydee.subtitle_app

import android.content.Context
import android.net.Uri
import android.view.Surface
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.exoplayer.ExoPlayer
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.view.TextureRegistry
import java.io.File

/**
 * Gapless multi-clip player for the CapCut-style timeline. One ExoPlayer plays a
 * playlist of clips back-to-back (the next decoder is warmed up automatically →
 * no black flash at transitions), rendering into a Flutter Texture. ExoPlayer
 * applies each clip's own rotation, so clips always show upright.
 *
 * Method channel: com.anniekaydee.subtitle_app/clipplayer
 */
class ClipPlayer(
    private val context: Context,
    private val textureRegistry: TextureRegistry,
) : MethodChannel.MethodCallHandler {

    private var player: ExoPlayer? = null
    private var surfaceEntry: TextureRegistry.SurfaceTextureEntry? = null
    private var surface: Surface? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "create" -> create(result)
            "setClips" -> setClips(call, result)
            "play" -> { player?.play(); result.success(null) }
            "pause" -> { player?.pause(); result.success(null) }
            "seek" -> {
                val index = call.argument<Int>("index") ?: 0
                val ms = (call.argument<Int>("ms") ?: 0).toLong()
                player?.seekTo(index, ms)
                result.success(null)
            }
            "setVolume" -> {
                player?.volume = (call.argument<Double>("v") ?: 1.0).toFloat()
                result.success(null)
            }
            "position" -> result.success(positionMap())
            "size" -> {
                val vs = player?.videoSize
                result.success(mapOf(
                    "w" to (vs?.width ?: 0),
                    "h" to (vs?.height ?: 0),
                ))
            }
            "dispose" -> { disposeInternal(); result.success(null) }
            else -> result.notImplemented()
        }
    }

    private fun create(result: MethodChannel.Result) {
        disposeInternal()
        val entry = textureRegistry.createSurfaceTexture()
        surfaceEntry = entry
        val st = entry.surfaceTexture()
        surface = Surface(st)
        val p = ExoPlayer.Builder(context).build()
        p.setVideoSurface(surface)
        p.repeatMode = Player.REPEAT_MODE_OFF
        p.playWhenReady = false
        player = p
        result.success(entry.id())
    }

    private fun setClips(call: MethodCall, result: MethodChannel.Result) {
        val paths = call.argument<List<String>>("paths") ?: emptyList()
        val trimStarts = call.argument<List<Int>>("trimStarts")
        val trimEnds = call.argument<List<Int>>("trimEnds")
        val items = paths.mapIndexed { i, path ->
            val b = MediaItem.Builder().setUri(Uri.fromFile(File(path)))
            if (trimStarts != null) {
                val s = (trimStarts.getOrElse(i) { 0 }).toLong()
                val e = (trimEnds?.getOrElse(i) { -1 } ?: -1)
                val cc = MediaItem.ClippingConfiguration.Builder()
                    .setStartPositionMs(if (s > 0) s else 0)
                if (e > 0) cc.setEndPositionMs(e.toLong())
                b.setClippingConfiguration(cc.build())
            }
            b.build()
        }
        val p = player
        if (p == null) { result.error("NO_PLAYER", "create() first", null); return }
        p.setMediaItems(items)
        p.prepare()
        result.success(null)
    }

    private fun positionMap(): Map<String, Any> {
        val p = player ?: return mapOf("index" to 0, "posMs" to 0, "playing" to false, "ended" to false)
        return mapOf(
            "index" to p.currentMediaItemIndex,
            "posMs" to p.currentPosition.toInt(),
            "playing" to p.isPlaying,
            "ended" to (p.playbackState == Player.STATE_ENDED),
        )
    }

    private fun disposeInternal() {
        try { player?.release() } catch (_: Exception) {}
        player = null
        try { surface?.release() } catch (_: Exception) {}
        surface = null
        try { surfaceEntry?.release() } catch (_: Exception) {}
        surfaceEntry = null
    }
}
