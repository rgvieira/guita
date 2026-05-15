package com.rgvieira63.guitarra

import alphaTab.AlphaTabView
import alphaTab.LayoutMode
import alphaTab.collections.DoubleList
import alphaTab.core.ecmaScript.Uint8Array
import alphaTab.importer.ScoreLoader
import alphaTab.model.Score
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.util.Log
import java.io.ByteArrayOutputStream
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.contracts.ExperimentalContracts
import java.io.File

@OptIn(ExperimentalContracts::class, ExperimentalUnsignedTypes::class)
class AlphaTabViewFactory(private val messenger: BinaryMessenger) :
    PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return AlphaTabNativeView(context, viewId, messenger)
    }
}

@OptIn(ExperimentalContracts::class, ExperimentalUnsignedTypes::class)
class AlphaTabNativeView(
    context: Context,
    viewId: Int,
    private val messenger: BinaryMessenger
) : PlatformView, MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "ALPHATAB"
    }

    private val alphaTabView: AlphaTabView
    private val channel: MethodChannel
    private var loadedScore: Score? = null
    private var currentTrack: Int = 0
    private var trackSelected: Boolean = false
    private var isHorizontal: Boolean = false
    private var sfPath: String? = null
    private var sfLoadAttempted: Boolean = false

    private var printingInProgress = false

    init {
        Log.w(TAG, ">>>> AlphaTabNativeView INIT <<<<")

        alphaTabView = AlphaTabView(context, null)
        channel = MethodChannel(messenger, "alphatab_$viewId")
        channel.setMethodCallHandler(this)

        val a = alphaTabView.api
        Log.w(TAG, "ALPHATAB: api obtained OK")

        // Use Android Canvas engine so view.draw(canvas) captures the score for printing
        a.settings.core.engine = "android"

        a.settings.player.enablePlayer = true
        a.settings.player.enableCursor = true
        a.settings.player.enableUserInteraction = true
        a.masterVolume = 1.0
        Log.w(TAG, "ALPHATAB: player enabled, volume=1.0")

        a.scoreLoaded.on { score ->
            Log.w(TAG, "ALPHATAB: onScoreLoaded fires! tracks=${score.tracks.count()}")
            loadedScore = score
            channel.invokeMethod("onScoreLoaded", null)
            val names = mutableListOf<String>()
            val programs = mutableListOf<Int>()
            for (i in 0 until score.tracks.count()) {
                val track = score.tracks.get(i)
                val name = track.name
                names.add(name ?: "Faixa ${i + 1}")
                val prog = track.playbackInfo?.program
                programs.add(if (prog is Int) prog else 0)
            }
            channel.invokeMethod("onTrackNames", names.joinToString("|"))
            channel.invokeMethod("onTrackPrograms", programs.joinToString(","))
        }
        a.soundFontLoaded.on {
            Log.w(TAG, "ALPHATAB: onSoundFontLoaded fires!")
            channel.invokeMethod("onSoundFontLoaded", null)
        }
        a.playerReady.on {
            Log.w(TAG, "ALPHATAB: onPlayerReady fires! sfLoadAttempted=$sfLoadAttempted")
            if (!sfLoadAttempted) loadSoundFontNow()
        }
        a.playerStateChanged.on { args ->
            channel.invokeMethod("onPlayerStateChanged", args.state.ordinal)
        }
        a.renderFinished.on {
            Log.w(TAG, "ALPHATAB: renderFinished")
            channel.invokeMethod("onRenderFinished", null)
        }
    }

    private fun loadSoundFontNow() {
        sfLoadAttempted = true
        val path = sfPath
        if (path == null) {
            Log.w(TAG, "ALPHATAB: no SF path yet, skipping")
            return
        }
        try {
            val sfFile = File(path)
            if (!sfFile.exists()) {
                val msg = "SF2 file not found at $path"
                Log.wtf(TAG, "ALPHATAB: $msg")
                channel.invokeMethod("onError", msg)
                return
            }
            val a = alphaTabView.api
            val bytes = sfFile.readBytes()
            Log.w(TAG, "ALPHATAB: SF2 size=${sfFile.length()}")

            // Try soundFontFile property first (path-based)
            try {
                val sfProp = a::class.java.getDeclaredField("soundFontFile")
                sfProp.isAccessible = true
                sfProp.set(a, path)
                Log.w(TAG, "ALPHATAB: set soundFontFile=$path")
                return
            } catch (e: Exception) {
                Log.w(TAG, "ALPHATAB: soundFontFile prop not found: ${e.message}")
            }

            // Fallback: loadSoundFont with bytes
            val result = a.loadSoundFont(Uint8Array(bytes.toUByteArray()), false)
            Log.w(TAG, "ALPHATAB: loadSoundFont=$result")
            if (!result) {
                Log.w(TAG, "SoundFont load returned false — using built-in synth (non-critical)")
            }
        } catch (e: Throwable) {
            Log.wtf(TAG, "ALPHATAB: SOUNDFONT LOAD FAILED: ${e.message}", e)
            channel.invokeMethod("onError", "SF load: ${e.message}")
        }
    }

    private fun doLoadScore(path: String) {
        try {
            val api = alphaTabView.api
            val file = java.io.File(path)
            Log.w(TAG, "ALPHATAB: doLoadScore path=$path exists=${file.exists()} size=${if (file.exists()) file.length() else -1}")
            if (!file.exists()) {
                val msg = "File not found: $path"
                Log.wtf(TAG, "ALPHATAB: $msg")
                channel.invokeMethod("onError", msg)
                return
            }
            val bytes = file.readBytes()
            Log.w(TAG, "ALPHATAB: read ${bytes.size} bytes for score")
            val score = ScoreLoader.loadScoreFromBytes(Uint8Array(bytes.toUByteArray()), api.settings)
            if (score != null) {
                loadedScore = score
                currentTrack = 0
                trackSelected = false
                isHorizontal = false
                val trackCount = score.tracks.count()
                Log.w(TAG, "ALPHATAB: score OK, rendering... tracks=$trackCount")
                channel.invokeMethod("onTrackChanged", "0/${trackCount}")
                api.renderScore(score, null)
            } else {
                val msg = "ScoreLoader returned null (unsupported format?)"
                Log.wtf(TAG, "ALPHATAB: $msg")
                channel.invokeMethod("onError", msg)
            }
        } catch (e: Throwable) {
            val msg = "Score load error: ${e.message}"
            Log.wtf(TAG, "ALPHATAB: $msg", e)
            channel.invokeMethod("onError", msg)
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val api = alphaTabView.api
            when (call.method) {
                "setSoundFontPath" -> {
                    sfPath = call.arguments as String
                    Log.w(TAG, "ALPHATAB: setSoundFontPath=$sfPath")
                    result.success(null)
                }
                "setLayoutMode" -> {
                    isHorizontal = call.arguments as Boolean
                    Log.w(TAG, "ALPHATAB: setLayoutMode -> ${if (isHorizontal) "Horizontal" else "Page"}")
                    api.settings.display.layoutMode = if (isHorizontal) LayoutMode.Horizontal else LayoutMode.Page
                    api.updateSettings()
                    result.success(null)
                }
                "loadScore" -> {
                    val path = call.arguments as String
                    doLoadScore(path)
                    result.success(null)
                }
                "play" -> {
                    Log.w(TAG, "ALPHATAB: play() called")
                    api.play()
                    result.success(null)
                }
                "pause" -> {
                    api.pause()
                    result.success(null)
                }
                "stop" -> {
                    api.stop()
                    result.success(null)
                }
                "nextTrack" -> {
                    val score = loadedScore
                    if (score != null && currentTrack < score.tracks.count() - 1) {
                        currentTrack++
                        trackSelected = true
                        val trackCount = score.tracks.count()
                        Log.w(TAG, "ALPHATAB: switch to track $currentTrack of $trackCount")
                        api.renderScore(score, DoubleList(currentTrack.toDouble()))
                        channel.invokeMethod("onTrackChanged", "${currentTrack}/${trackCount}")
                        result.success(currentTrack)
                    } else {
                        result.success(-1)
                    }
                }
                "prevTrack" -> {
                    val score = loadedScore
                    if (score != null && currentTrack > 0) {
                        currentTrack--
                        trackSelected = true
                        val trackCount = score.tracks.count()
                        Log.w(TAG, "ALPHATAB: switch to track $currentTrack of $trackCount")
                        api.renderScore(score, DoubleList(currentTrack.toDouble()))
                        channel.invokeMethod("onTrackChanged", "${currentTrack}/${trackCount}")
                        result.success(currentTrack)
                    } else {
                        result.success(-1)
                    }
                }
                "setTrack" -> {
                    val trackIndex = call.arguments as Int
                    val score = loadedScore
                    if (score != null && trackIndex >= 0 && trackIndex < score.tracks.count()) {
                        currentTrack = trackIndex
                        trackSelected = true
                        val trackCount = score.tracks.count()
                        Log.w(TAG, "ALPHATAB: set track $trackIndex of $trackCount")
                        api.renderScore(score, DoubleList(currentTrack.toDouble()))
                        channel.invokeMethod("onTrackChanged", "${trackIndex}/${trackCount}")
                        result.success(trackIndex)
                    } else {
                        result.success(-1)
                    }
                }
                "toggleLayout" -> {
                    isHorizontal = !isHorizontal
                    Log.w(TAG, "ALPHATAB: toggle layout -> ${if (isHorizontal) "Horizontal" else "Page"}")
                    api.settings.display.layoutMode = if (isHorizontal) LayoutMode.Horizontal else LayoutMode.Page
                    api.updateSettings()
                    val score = loadedScore
                    if (score != null) {
                        api.renderScore(score, null)
                    }
                    result.success(isHorizontal)
                }
                "reRender" -> {
                    Log.w(TAG, "ALPHATAB: reRender")
                    val score = loadedScore
                    if (score != null) {
                        api.renderScore(score, null)
                    }
                    result.success(null)
                }
                "printScore" -> {
                    try {
                        if (printingInProgress) {
                            result.error("PRINT_IN_PROGRESS", "Print already in progress", null)
                            return@onMethodCall
                        }
                        printingInProgress = true
                        val view = alphaTabView
                        if (view.width <= 0 || view.height <= 0) {
                            result.error("VIEW_INVALID", "View has no size", null)
                            return@onMethodCall
                        }
                        val w = view.width
                        val h = view.height
                        Log.w(TAG, "ALPHATAB: printScore w=$w h=$h")

                        // Force software layer so view.draw(canvas) captures the score
                        val prevLayerType = view.layerType
                        view.setLayerType(View.LAYER_TYPE_SOFTWARE, null)

                        val pages = mutableListOf<ByteArray>()

                        // 1) Try view.draw(canvas) with software layer
                        if (w > 0 && h > 0) {
                            val bitmap = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                            val canvas = Canvas(bitmap)
                            canvas.drawColor(Color.WHITE)
                            view.draw(canvas)
                            val stream = ByteArrayOutputStream()
                            bitmap.compress(Bitmap.CompressFormat.PNG, 100, stream)
                            val bytes = stream.toByteArray()
                            // Check whether the capture has actual content
                            if (bytes.size > 200) {
                                Log.w(TAG, "ALPHATAB: view.draw produced ${bytes.size} bytes")
                                pages.add(bytes)
                            } else {
                                Log.w(TAG, "ALPHATAB: view.draw too small (${bytes.size}), trying buildDrawingCache")
                                // 2) Fallback: use drawing cache
                                view.isDrawingCacheEnabled = true
                                view.buildDrawingCache()
                                val cacheBmp = view.drawingCache
                                if (cacheBmp != null && !cacheBmp.isRecycled) {
                                    val s2 = ByteArrayOutputStream()
                                    cacheBmp.compress(Bitmap.CompressFormat.PNG, 100, s2)
                                    val b2 = s2.toByteArray()
                                    if (b2.size > 200) {
                                        pages.add(b2)
                                    }
                                }
                                view.isDrawingCacheEnabled = false
                                view.destroyDrawingCache()
                            }
                            bitmap.recycle()
                        }

                        // Restore layer type
                        view.setLayerType(prevLayerType, null)

                        if (pages.isEmpty()) {
                            result.error("PRINT_EMPTY", "No captured content", null)
                        } else {
                            result.success(pages)
                        }
                    } catch (e: Exception) {
                        Log.wtf(TAG, "ALPHATAB: printScore error: ${e.message}", e)
                        result.error("PRINT_ERROR", e.message, null)
                    } finally {
                        printingInProgress = false
                    }
                }
                else -> result.notImplemented()
            }
        } catch (e: Throwable) {
            Log.wtf(TAG, "ALPHATAB: unhandled error: ${e.message}", e)
            result.error("ALPHATAB_ERROR", e.message, null)
        }
    }

    override fun getView(): View = alphaTabView

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
