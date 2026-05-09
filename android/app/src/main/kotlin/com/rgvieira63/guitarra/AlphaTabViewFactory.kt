package com.rgvieira63.guitarra

import alphaTab.AlphaTabView
import alphaTab.core.ecmaScript.Uint8Array
import android.content.Context
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
            channel.invokeMethod("onSoundFontLoaded", null)
        }
        api.playerStateChanged.on { args ->
            channel.invokeMethod("onPlayerStateChanged", args.state.ordinal)
        }
        api.renderFinished.on {
            channel.invokeMethod("onRenderFinished", null)
        }

        loadSoundFontFromAssets(context)
    }

    private fun loadSoundFontFromAssets(context: Context) {
        try {
            context.assets.open("soundfonts/sonivox.sf2").use { inputStream ->
                val bytes = inputStream.readBytes()
                val uint8Array = Uint8Array(bytes.toUByteArray())
                alphaTabView.api.loadSoundFont(uint8Array, false)
            }
        } catch (e: Exception) {
            channel.invokeMethod("onError", "soundFont load: ${e.message}")
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            val api = alphaTabView.api
            when (call.method) {
                "loadScore" -> {
                    val path = call.arguments as String
                    api.load(path)
                    result.success(null)
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
