package com.rgvieira63.guitarra

import android.content.Context
import android.media.AudioAttributes
import android.media.AudioFormat
import android.media.AudioManager
import android.media.AudioTrack
import android.media.midi.MidiManager
import android.os.Build
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MidiAudioBridge(messenger: BinaryMessenger, private val context: Context) :
    MethodChannel.MethodCallHandler {

    companion object {
        private const val TAG = "MIDI_BRIDGE"
        private const val CHANNEL = "com.rgvieira63.guitarra/midi_audio"
    }

    private val channel = MethodChannel(messenger, CHANNEL)
    private val activeNotes = mutableSetOf<Int>()

    // Simple FM-like synthesis using AudioTrack
    private var audioTrack: AudioTrack? = null
    private var synthRunning = false
    private val sampleRate = 44100

    init {
        channel.setMethodCallHandler(this)
        initSynth()
    }

    private fun initSynth() {
        try {
            val bufferSize = AudioTrack.getMinBufferSize(
                sampleRate,
                AudioFormat.CHANNEL_OUT_MONO,
                AudioFormat.ENCODING_PCM_16BIT
            )
            audioTrack = AudioTrack.Builder()
                .setAudioAttributes(
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_MEDIA)
                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                        .build()
                )
                .setAudioFormat(
                    AudioFormat.Builder()
                        .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                        .setSampleRate(sampleRate)
                        .setChannelMask(AudioFormat.CHANNEL_OUT_MONO)
                        .build()
                )
                .setBufferSizeInBytes(bufferSize.coerceAtLeast(4096))
                .build()
            synthRunning = true
            audioTrack?.play()
            Log.w(TAG, "AudioTrack synth initialized")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to init AudioTrack: ${e.message}")
        }
    }

    private val synthThreads = mutableMapOf<Int, Thread>()

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "ping" -> {
                    result.success(true)
                }
                "sendNoteOn" -> {
                    val note = call.argument<Int>("note") ?: 60
                    val velocity = call.argument<Int>("velocity") ?: 100
                    playNote(note, velocity)
                    activeNotes.add(note)
                    result.success(true)
                }
                "sendNoteOff" -> {
                    val note = call.argument<Int>("note") ?: 60
                    stopNote(note)
                    activeNotes.remove(note)
                    result.success(true)
                }
                "allNotesOff" -> {
                    for (n in activeNotes.toSet()) {
                        stopNote(n)
                    }
                    activeNotes.clear()
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error: ${e.message}")
            result.error("MIDI_ERROR", e.message, null)
        }
    }

    private fun playNote(midi: Int, velocity: Int) {
        // Simple triangle wave synthesis per note
        val freq = 440.0 * Math.pow(2.0, (midi - 69).toDouble() / 12.0)
        val amp = velocity / 127.0 * 0.3
        val thread = Thread {
            try {
                val buffer = ShortArray(sampleRate / 10) // 100ms buffer
                val dt = 1.0 / sampleRate
                var phase = 0.0
                while (!Thread.interrupted() && synthRunning) {
                    for (i in buffer.indices) {
                        // Triangle wave
                        val t = phase * freq
                        val sample = if (t % 1.0 < 0.5) {
                            4.0 * (t % 1.0) - 1.0
                        } else {
                            3.0 - 4.0 * (t % 1.0)
                        }
                        buffer[i] = (sample * amp * Short.MAX_VALUE).toInt().coerceIn(-32768, 32767).toShort()
                        phase += dt
                    }
                    audioTrack?.write(buffer, 0, buffer.size)
                }
            } catch (e: InterruptedException) {
                // Thread interrupted = note off
            } catch (e: Exception) {
                Log.e(TAG, "Synth thread error: ${e.message}")
            }
        }
        thread.isDaemon = true
        thread.start()
        synthThreads[midi] = thread
    }

    private fun stopNote(midi: Int) {
        synthThreads[midi]?.interrupt()
        synthThreads.remove(midi)
    }

    fun dispose() {
        synthRunning = false
        for (thread in synthThreads.values) {
            thread.interrupt()
        }
        synthThreads.clear()
        audioTrack?.stop()
        audioTrack?.release()
        audioTrack = null
        channel.setMethodCallHandler(null)
    }
}
