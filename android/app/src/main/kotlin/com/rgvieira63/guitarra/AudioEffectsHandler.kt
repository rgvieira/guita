package com.rgvieira63.guitarra

import android.media.audiofx.BassBoost
import android.media.audiofx.Equalizer
import android.media.audiofx.LoudnessEnhancer
import android.media.audiofx.PresetReverb
import android.util.Log
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class AudioEffectsHandler(messenger: BinaryMessenger) : MethodChannel.MethodCallHandler {
    private val channel = MethodChannel(messenger, "audio_effects")

    private var equalizer: Equalizer? = null
    private var reverb: PresetReverb? = null
    private var bassBoost: BassBoost? = null
    private var loudness: LoudnessEnhancer? = null

    init {
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "init" -> {
                    try { equalizer = Equalizer(0, 0).also { it.enabled = true } } catch (e: Exception) { Log.w("AudioEffects", "Equalizer: ${e.message}") }
                    try { reverb = PresetReverb(0, 0).also { it.enabled = true } } catch (e: Exception) { Log.w("AudioEffects", "Reverb: ${e.message}") }
                    try { bassBoost = BassBoost(0, 0).also { it.enabled = true } } catch (e: Exception) { Log.w("AudioEffects", "BassBoost: ${e.message}") }
                    try { loudness = LoudnessEnhancer(0).also { it.enabled = true } } catch (e: Exception) { Log.w("AudioEffects", "Loudness: ${e.message}") }

                    val bandCount = try { equalizer?.numberOfBands ?: 0 } catch (e: Exception) { 0 }
                    val bandFreqs = (0 until bandCount).map { i ->
                        try { equalizer?.getCenterFreq(i.toShort()) ?: 0 } catch (e: Exception) { 0 }
                    }
                    val bandRange = try { equalizer?.bandLevelRange ?: shortArrayOf(-1500, 1500) } catch (e: Exception) { shortArrayOf(-1500, 1500) }

                    result.success(mapOf(
                        "bandCount" to bandCount,
                        "bandFreqs" to bandFreqs,
                        "minLevel" to bandRange[0].toInt(),
                        "maxLevel" to bandRange[1].toInt()
                    ))
                }

                "setEqBand" -> {
                    val band = (call.argument<Int>("band") ?: 0).toShort()
                    val level = (call.argument<Int>("level") ?: 0).toShort()
                    equalizer?.setBandLevel(band, level)
                    result.success(true)
                }

                "setReverbPreset" -> {
                    val preset = (call.argument<Int>("preset") ?: 0).toShort()
                    reverb?.setPreset(preset)
                    result.success(true)
                }

                "setBassBoost" -> {
                    val strength = (call.argument<Int>("strength") ?: 0).toShort()
                    bassBoost?.setStrength(strength)
                    result.success(true)
                }

                "setVolume" -> {
                    // LoudnessEnhancer gain in millibels: 0 = no gain, negative = attenuation
                    val vol = (call.argument<Double>("volume") ?: 1.0).coerceIn(0.0, 1.0)
                    val gainMb = if (vol <= 0) -9600 else (20.0 * kotlin.math.log10(vol) * 100).toInt()
                    loudness?.setTargetGain(gainMb)
                    result.success(true)
                }

                "release" -> {
                    try { equalizer?.release() } catch (_: Exception) {}
                    try { reverb?.release() } catch (_: Exception) {}
                    try { bassBoost?.release() } catch (_: Exception) {}
                    try { loudness?.release() } catch (_: Exception) {}
                    equalizer = null; reverb = null; bassBoost = null; loudness = null
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e("AudioEffects", "Error: ${e.message}")
            result.error("AUDIO_EFFECTS_ERROR", e.message, null)
        }
    }
}
