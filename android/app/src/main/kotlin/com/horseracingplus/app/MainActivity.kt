package com.horseracingplus.app

import android.os.Bundle
import androidx.core.view.WindowCompat
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15(API 35)에서 deprecated 된 Window.setStatusBarColor 등을 직접 호출하지 않고
        // edge-to-edge 를 활성화한다. (시스템 바는 자동으로 투명해짐)
        WindowCompat.setDecorFitsSystemWindows(window, false)
    }
}
