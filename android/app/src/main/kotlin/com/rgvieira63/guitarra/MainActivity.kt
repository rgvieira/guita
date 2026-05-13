package com.rgvieira63.guitarra

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine
            .platformViewsController
            ?.registry
            ?.registerViewFactory(
                "alphatab_view",
                AlphaTabViewFactory(flutterEngine.dartExecutor.binaryMessenger)
            )
        AudioEffectsHandler(flutterEngine.dartExecutor.binaryMessenger)
    }
}
