import glob
import re

# ---------- 1. AndroidManifest ----------
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()

extra = (
    '<uses-permission android:name="android.permission.INTERNET"/>\n'
    '    <uses-feature android:name="android.software.leanback" android:required="false"/>\n'
    '    <uses-feature android:name="android.hardware.touchscreen" android:required="false"/>\n'
    '    '
)
s = s.replace(
    '<application',
    extra + '<application android:usesCleartextTraffic="true" android:banner="@drawable/banner"',
    1,
)
# hamesha landscape
s = s.replace('<activity', '<activity android:screenOrientation="sensorLandscape"', 1)
s = re.sub(
    r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
    r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
    s,
    count=1,
)
s = re.sub(r'android:label="[^"]*"', 'android:label="Streamivo"', s)

assert 'LEANBACK_LAUNCHER' in s, 'LEANBACK_LAUNCHER patch failed'
assert 'android:banner' in s, 'banner patch failed'
assert 'sensorLandscape' in s, 'orientation patch failed'
open(p, 'w', encoding='utf-8').write(s)
print(s)

# ---------- 2. MainActivity (volume, brightness, TV detection) ----------
KOTLIN = '''
import android.app.UiModeManager
import android.content.Context
import android.content.res.Configuration
import android.media.AudioManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamivo/native")
            .setMethodCallHandler { call, result ->
                val am = getSystemService(Context.AUDIO_SERVICE) as AudioManager
                when (call.method) {
                    "getVolume" -> {
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        result.success(am.getStreamVolume(AudioManager.STREAM_MUSIC).toDouble() / max.toDouble())
                    }
                    "setVolume" -> {
                        val v = call.arguments as Double
                        val max = am.getStreamMaxVolume(AudioManager.STREAM_MUSIC)
                        am.setStreamVolume(AudioManager.STREAM_MUSIC, Math.round(v * max).toInt(), 0)
                        result.success(null)
                    }
                    "getBrightness" -> {
                        val b = window.attributes.screenBrightness
                        val v: Double = if (b >= 0f) {
                            b.toDouble()
                        } else {
                            try {
                                Settings.System.getInt(contentResolver, Settings.System.SCREEN_BRIGHTNESS) / 255.0
                            } catch (e: Exception) {
                                0.5
                            }
                        }
                        result.success(v)
                    }
                    "setBrightness" -> {
                        val lp = window.attributes
                        lp.screenBrightness = (call.arguments as Double).toFloat()
                        window.attributes = lp
                        result.success(null)
                    }
                    "resetBrightness" -> {
                        val lp = window.attributes
                        lp.screenBrightness = -1f
                        window.attributes = lp
                        result.success(null)
                    }
                    "isTv" -> {
                        val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                        val tv = ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                            packageManager.hasSystemFeature("android.software.leanback") ||
                            packageManager.hasSystemFeature("android.hardware.type.television")
                        result.success(tv)
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
'''

files = glob.glob('android/app/src/main/kotlin/**/MainActivity.kt', recursive=True)
assert files, 'MainActivity.kt not found'
src = open(files[0], encoding='utf-8').read()
pkg = re.search(r'^package\s+[\w.]+', src, re.M).group(0)
open(files[0], 'w', encoding='utf-8').write(pkg + '\n' + KOTLIN)
print('MainActivity patched:', files[0])
