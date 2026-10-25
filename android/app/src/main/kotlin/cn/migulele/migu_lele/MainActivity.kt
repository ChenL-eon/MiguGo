package cn.migulele.migu_lele

import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    // 只回传本机稳定设备号，用于把同一账号的多端会话区分开；不读取 IMEI 等敏感标识。
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "migu_lele/device"
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "androidId" -> result.success(
                    Settings.Secure.getString(contentResolver, Settings.Secure.ANDROID_ID)
                )
                else -> result.notImplemented()
            }
        }
    }
}
