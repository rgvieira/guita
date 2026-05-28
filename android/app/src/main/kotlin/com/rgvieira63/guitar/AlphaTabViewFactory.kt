package com.rgvieira63.guitar

import alphaTab.AlphaTabView
import alphaTab.LayoutMode
import alphaTab.collections.DoubleList
import alphaTab.core.ecmaScript.Uint8Array
import alphaTab.importer.ScoreLoader
import alphaTab.model.Score
import android.content.Context
import android.util.Base64
import android.util.Log
import android.view.View
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.JavascriptInterface
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.contracts.ExperimentalContracts
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

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
    private var loadedScoreBytes: ByteArray? = null
    private var currentTrack: Int = 0
    private var trackSelected: Boolean = false
    private var isHorizontal: Boolean = false
    private var sfPath: String? = null
    private var sfLoadAttempted: Boolean = false

    private var printingInProgress = false
    private var renderTotalHeight: Double = 0.0
    private var printWebView: WebView? = null

    init {
        Log.w(TAG, ">>>> AlphaTabNativeView INIT <<<<")

        alphaTabView = AlphaTabView(context, null)
        channel = MethodChannel(messenger, "alphatab_$viewId")
        channel.setMethodCallHandler(this)

        val a = alphaTabView.api
        Log.w(TAG, "ALPHATAB: api obtained OK")

        a.settings.core.engine = "android"

        a.settings.player.enablePlayer = true
        a.settings.player.enableCursor = true
        a.settings.player.enableUserInteraction = true
        a.masterVolume = 1.0
        a.updateSettings()
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
            channel.invokeMethod("onTrackNames", names)
            channel.invokeMethod("onTrackPrograms", programs)
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
        a.renderFinished.on { args ->
            Log.w(TAG, "ALPHATAB: renderFinished")
            // Save totalHeight for printing
            try {
                val f = args::class.java.getDeclaredField("totalHeight")
                f.isAccessible = true
                renderTotalHeight = (f.get(args) as? Double) ?: 0.0
            } catch (_: Exception) {}
            channel.invokeMethod("onRenderFinished", null)
        }

        // Dump all methods/fields on api to find export capability
        try {
            Log.w(TAG, "ALPHATAB: === API METHODS DUMP ===")
            for (m in a::class.java.methods) {
                if (m.name.contains("render", true) || m.name.contains("export", true) || m.name.contains("svg", true) || m.name.contains("png", true) || m.name.contains("image", true) || m.name.contains("screen", true) || m.name.contains("capture", true) || m.name.contains("bitmap", true) || m.name.contains("picture", true) || m.name.contains("save", true) || m.name.contains("writer", true)) {
                    Log.w(TAG, "ALPHATAB:   API method: ${m.name}(${m.parameterTypes.joinToString { it.simpleName }}) -> ${m.returnType.simpleName}")
                }
            }
            for (f in a::class.java.declaredFields) {
                if (f.name.contains("render", true) || f.name.contains("export", true) || f.name.contains("svg", true) || f.name.contains("png", true) || f.name.contains("image", true) || f.name.contains("screen", true) || f.name.contains("capture", true) || f.name.contains("bitmap", true) || f.name.contains("picture", true) || f.name.contains("save", true)) {
                    Log.w(TAG, "ALPHATAB:   API field: ${f.name} : ${f.type.simpleName}")
                }
            }
            // Also check scoreRenderer if accessible
            try {
                val srField = a::class.java.getDeclaredField("scoreRenderer")
                srField.isAccessible = true
                val sr = srField.get(a)
                if (sr != null) {
                    Log.w(TAG, "ALPHATAB:   scoreRenderer found: ${sr::class.java.simpleName}")
                    for (m in sr::class.java.methods) {
                        if (m.name.contains("render", true) || m.name.contains("export", true) || m.name.contains("svg", true) || m.name.contains("png", true) || m.name.contains("image", true) || m.name.contains("screen", true) || m.name.contains("capture", true) || m.name.contains("bitmap", true) || m.name.contains("picture", true) || m.name.contains("save", true) || m.name.contains("writer", true)) {
                            Log.w(TAG, "ALPHATAB:   Renderer method: ${m.name}(${m.parameterTypes.joinToString { it.simpleName }}) -> ${m.returnType.simpleName}")
                        }
                    }
                }
            } catch (_: Exception) { Log.w(TAG, "ALPHATAB:   scoreRenderer field not accessible") }
            Log.w(TAG, "ALPHATAB: === END DUMP ===")
        } catch (_: Exception) { Log.w(TAG, "ALPHATAB: dump failed") }

        // Hidden WebView for print capture via evaluateJavascript
        val pv = WebView(context)
        pv.settings.javaScriptEnabled = true
        pv.settings.domStorageEnabled = true
        pv.settings.loadWithOverviewMode = true
        pv.settings.useWideViewPort = true
        pv.isVerticalScrollBarEnabled = false
        pv.isHorizontalScrollBarEnabled = false
        pv.visibility = View.INVISIBLE
        pv.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                Log.w(TAG, "ALPHATAB: printWebView loaded")
            }
        }
        pv.measure(View.MeasureSpec.makeMeasureSpec(1080, View.MeasureSpec.EXACTLY),
                   View.MeasureSpec.makeMeasureSpec(1500, View.MeasureSpec.EXACTLY))
        pv.layout(0, 0, 1080, 1500)
        alphaTabView.addView(pv)
        pv.loadUrl("file:///android_asset/print.html")
        printWebView = pv
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
            loadedScoreBytes = bytes
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
                    // Se o player já estiver pronto, carrega o SF2 imediatamente
                    if (!sfLoadAttempted) {
                        loadSoundFontNow()
                    }
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
                "setPlaybackSpeed" -> {
                    val speed = (call.arguments as Number).toDouble().coerceIn(0.125, 8.0)
                    api.playbackSpeed = speed
                    Log.w(TAG, "ALPHATAB: setPlaybackSpeed=$speed")
                    result.success(true)
                }
                "setVolume" -> {
                    val vol = (call.arguments as Number).toDouble().coerceIn(0.0, 1.0)
                    api.masterVolume = vol
                    Log.w(TAG, "ALPHATAB: setVolume=$vol")
                    result.success(true)
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
                    if (loadedScore == null) {
                        result.error("NO_SCORE", "No score loaded", null)
                        return@onMethodCall
                    }
                    if (printingInProgress) {
                        result.error("PRINT_IN_PROGRESS", "Print already in progress", null)
                        return@onMethodCall
                    }
                    printingInProgress = true
                    Log.w(TAG, "ALPHATAB: printScore track=$currentTrack")

                    val pv = printWebView
                    if (pv == null) {
                        result.error("PRINT_ERROR", "WebView not initialized", null)
                        printingInProgress = false
                        return@onMethodCall
                    }
                    val bytes = loadedScoreBytes ?: run {
                        result.error("PRINT_ERROR", "No score bytes", null)
                        printingInProgress = false
                        return@onMethodCall
                    }
                    val scoreB64 = Base64.encodeToString(bytes, Base64.NO_WRAP)
                    val mainHandler = android.os.Handler(android.os.Looper.getMainLooper())

                    Thread {
                        val pngPages = mutableListOf<ByteArray>()
                        var flowError: String? = null
                        Log.w(TAG, "ALPHATAB: print thread started, b64len=${scoreB64.length}")

                        // Step 1: load score into WebView via evaluateJavascript
                        val loadLatch = CountDownLatch(1)
                        mainHandler.post {
                            Log.w(TAG, "ALPHATAB: evaluateJavascript loadScoreBase64...")
                            pv.evaluateJavascript("loadScoreBase64('$scoreB64')") { res ->
                                Log.w(TAG, "ALPHATAB: loadScoreBase64 callback=${res?.take(50)}")
                                loadLatch.countDown()
                            }
                            Log.w(TAG, "ALPHATAB: evaluateJavascript returned")
                        }
                        Log.w(TAG, "ALPHATAB: awaiting load latch...")
                        if (!loadLatch.await(10, TimeUnit.SECONDS)) { flowError = "WebView load timeout" }
                        Log.w(TAG, "ALPHATAB: load done, flowError=$flowError")

                        if (flowError == null) {
                            // Step 2: poll for renderDone
                            val renderLatch = CountDownLatch(1)
                            mainHandler.post {
                                var tries = 0
                                val maxTries = 120
                                fun pollRender() {
                                    if (tries >= maxTries) { flowError = "Render timeout"; renderLatch.countDown(); return }
                                    tries++
                                    pv.evaluateJavascript("window.__renderDone") { done ->
                                        if (done == "true") {
                                            renderLatch.countDown()
                                        } else {
                                            pv.evaluateJavascript("window.__error") { err ->
                                                if (err != null && err.isNotEmpty() && err != "null" && err != "\"\"") {
                                                    flowError = "JS: $err"
                                                    renderLatch.countDown()
                                                } else {
                                                    mainHandler.postDelayed({ pollRender() }, 500)
                                                }
                                            }
                                        }
                                    }
                                }
                                pollRender()
                            }
                            if (!renderLatch.await(65, TimeUnit.SECONDS) && flowError == null) {
                                flowError = "Render timeout"
                            }
                        }

                        if (flowError == null) {
                            // Step 3: trigger captureAll
                            val capLatch = CountDownLatch(1)
                            mainHandler.post {
                                pv.evaluateJavascript("captureAll()") {
                                    capLatch.countDown()
                                }
                            }
                            if (!capLatch.await(10, TimeUnit.SECONDS)) { flowError = "captureAll timeout" }
                        }

                        if (flowError == null) {
                            // Step 4: poll for captureDone
                            val capDoneLatch = CountDownLatch(1)
                            mainHandler.post {
                                var tries = 0
                                val maxTries = 40
                                fun pollCap() {
                                    if (tries >= maxTries) { flowError = "Capture timeout"; capDoneLatch.countDown(); return }
                                    tries++
                                    pv.evaluateJavascript("window.__captureDone") { done ->
                                        if (done == "true") {
                                            // Read results
                                            pv.evaluateJavascript("window.__captureResult") { res ->
                                                try {
                                                    // res is a JSON string (with quotes), parse it
                                                    val jsonStr = if (res.length >= 2 && res.startsWith("\"") && res.endsWith("\"")) {
                                                        // Unescape
                                                        res.substring(1, res.length - 1)
                                                            .replace("\\\"", "\"")
                                                            .replace("\\n", "\n")
                                                            .replace("\\t", "\t")
                                                            .replace("\\\\", "\\")
                                                    } else res
                                                    // jsonStr should be a JSON array of base64 data URIs
                                                    val dataUris = org.json.JSONArray(jsonStr)
                                                    for (i in 0 until dataUris.length()) {
                                                        val dataUri = dataUris.getString(i) // "data:image/png;base64,XXXXX"
                                                        val comma = dataUri.indexOf(',')
                                                        if (comma >= 0) {
                                                            val b64 = dataUri.substring(comma + 1)
                                                            val pngBytes = Base64.decode(b64, Base64.DEFAULT)
                                                            pngPages.add(pngBytes)
                                                        }
                                                    }
                                                } catch (e: Exception) {
                                                    flowError = "Parse: ${e.message}"
                                                }
                                                capDoneLatch.countDown()
                                            }
                                        } else {
                                            pv.evaluateJavascript("window.__error") { err ->
                                                if (err != null && err.isNotEmpty() && err != "null" && err != "\"\"") {
                                                    flowError = "JS: $err"
                                                    capDoneLatch.countDown()
                                                } else {
                                                    mainHandler.postDelayed({ pollCap() }, 500)
                                                }
                                            }
                                        }
                                    }
                                }
                                pollCap()
                            }
                            if (!capDoneLatch.await(25, TimeUnit.SECONDS) && flowError == null) {
                                flowError = "Capture timeout"
                            }
                        }

                        val finalError = flowError
                        mainHandler.post {
                            if (finalError != null) result.error("PRINT_ERROR", finalError, null)
                            else result.success(pngPages)
                            printingInProgress = false
                        }
                    }.start()
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
