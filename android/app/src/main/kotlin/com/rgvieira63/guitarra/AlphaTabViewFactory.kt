package com.rgvieira63.guitarra

import alphaTab.AlphaTabView
import alphaTab.core.ecmaScript.Uint8Array
import alphaTab.importer.ScoreLoader
import android.content.Context
import android.util.Log
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.contracts.ExperimentalContracts

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
        private const val TAG = "AlphaTab"
    }

    private val alphaTabView: AlphaTabView
    private val channel: MethodChannel

    init {
        alphaTabView = AlphaTabView(context, null)
        channel = MethodChannel(messenger, "alphatab_$viewId")
        channel.setMethodCallHandler(this)

        val api = alphaTabView.api
        api.scoreLoaded.on { score ->
            channel.invokeMethod("onScoreLoaded", null)
        }
        api.soundFontLoaded.on {
            Log.i(TAG, "SoundFont loaded")
            channel.invokeMethod("onSoundFontLoaded", null)
        }
        api.playerStateChanged.on { args ->
            channel.invokeMethod("onPlayerStateChanged", args.state.ordinal)
        }
        api.renderFinished.on {
            Log.i(TAG, "Render finished")
            channel.invokeMethod("onRenderFinished", null)
        }

        loadSoundFontFromAssets(context)
    }

    private fun loadSoundFontFromAssets(context: Context) {
        try {
            context.assets.open("soundfonts/sonivox.sf2").use { inputStream ->
                val bytes = inputStream.readBytes()
                Log.i(TAG, "SoundFont read ${bytes.size} bytes, loading via Uint8Array...")
                alphaTabView.api.loadSoundFont(Uint8Array(bytes.toUByteArray()), false)
                Log.i(TAG, "loadSoundFont called (async)")
            }
        } catch (e: Exception) {
            Log.e(TAG, "soundFont load error", e)
            channel.invokeMethod("onError", "soundFont load: ${e.message}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val api = alphaTabView.api
            when (call.method) {
                "loadScore" -> {
                    val path = call.arguments as String
                    try {
                        val file = java.io.File(path)
                        Log.i(TAG, "loadScore: path=$path exists=${file.exists()} size=${if (file.exists()) file.length() else -1}")
                        if (!file.exists()) {
                            result.error("FILE_NOT_FOUND", "File not found: $path", null)
                            return@onMethodCall
                        }
                        val bytes = file.readBytes()
                        Log.i(TAG, "Read ${bytes.size} bytes, loading score via ScoreLoader...")
                        val score = ScoreLoader.loadScoreFromBytes(Uint8Array(bytes.toUByteArray()), api.settings)
                        if (score != null) {
                            Log.i(TAG, "Score loaded successfully, rendering...")
                            api.renderScore(score, null)
                            result.success(null)
                        } else {
                            result.error("LOAD_FAILED", "ScoreLoader returned null", null)
                        }
                    } catch (e: Exception) {
                        Log.e(TAG, "loadScore error", e)
                        result.error("LOAD_ERROR", "Failed to load score: ${e.message}", null)
                    }
                }
                "play" -> {
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
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("ALPHATAB_ERROR", e.message, null)
        }
    }

    override fun getView(): View = alphaTabView

    override fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
