package com.rgvieira63.guitarra

import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioEffectsHandler(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "audio_effects")

    companion object {
        private const val TAG = "AudioEffects"
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "init" -> {
                // Return empty EQ info - EQ not available with alphaTab's audio session
                result.success(mapOf(
                    "bandCount" to 0,
                    "bandFreqs" to listOf<Int>(),
                    "minLevel" to 0,
                    "maxLevel" to 0
                ))
            }
            "release" -> {
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
    }
}
