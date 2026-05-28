package com.rgvieira63.guitar

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
    }

    override fun onDestroy() {
        super.onDestroy()
    }
}
