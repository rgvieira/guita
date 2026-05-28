package com.rgvieira63.guitarra

import android.media.audiofx.Visualizer
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioVisualizerHandler(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "audio_visualizer")
    private var visualizer: Visualizer? = null
    private var captureRate = 0

    companion object {
        private const val TAG = "AudioVisualizer"
    }

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                try {
                    release()
                    visualizer = Visualizer(0).apply {
                        captureRate = Visualizer.getMaxCaptureRate()
                        setCaptureSize(Visualizer.getCaptureSizeRange()[1])
                        setDataCaptureListener(object : Visualizer.OnDataCaptureListener {
                            override fun onWaveFormDataCapture(
                                v: Visualizer,
                                waveform: ByteArray,
                                samplingRate: Int
                            ) {
                                val levels = extractLevels(waveform)
                                channel.invokeMethod("onAudioData", levels)
                            }

                            override fun onFftDataCapture(
                                v: Visualizer,
                                fft: ByteArray,
                                samplingRate: Int
                            ) {
                                // Not using FFT for now
                            }
                        }, captureRate / 2, true, false)
                        enabled = true
                    }
                    Log.d(TAG, "Visualizer started, captureRate=$captureRate")
                    result.success(true)
                } catch (e: Exception) {
                    Log.e(TAG, "Failed to start visualizer: ${e.message}")
                    result.success(false)
                }
            }
            "stop" -> {
                release()
                result.success(true)
            }
            else -> result.notImplemented()
        }
    }

    private fun extractLevels(data: ByteArray): List<Double> {
        val barCount = 32
        val levels = MutableList(barCount) { 0.0 }
        val step = data.size / barCount
        for (i in 0 until barCount) {
            var sum = 0.0
            val start = i * step
            val end = start + step
            for (j in start until end.coerceAtMost(data.size)) {
                val amplitude = (data[j].toInt() + 128) / 255.0
                sum += amplitude
            }
            levels[i] = (sum / step.coerceAtLeast(1)).coerceIn(0.0, 1.0)
        }
        return levels
    }

    private fun release() {
        try {
            visualizer?.enabled = false
            visualizer?.release()
        } catch (_: Exception) {}
        visualizer = null
    }

    fun dispose() {
        release()
        channel.setMethodCallHandler(null)
    }
}
