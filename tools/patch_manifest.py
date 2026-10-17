import glob
import os
import re
import shutil

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
# always landscape + picture-in-picture
s = s.replace(
    '<activity',
    '<activity android:screenOrientation="sensorLandscape" android:supportsPictureInPicture="true"',
    1,
)
s = re.sub(
    r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
    r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
    s,
    count=1,
)
s = re.sub(r'android:label="[^"]*"', 'android:label="Streamivo"', s)

s = s.replace(
    '</application>',
    '    <meta-data android:name="io.flutter.embedding.android.EnableImpeller" android:value="false"/>\n    </application>',
    1,
)

assert 'LEANBACK_LAUNCHER' in s, 'LEANBACK_LAUNCHER patch failed'
assert 'android:banner' in s, 'banner patch failed'
assert 'sensorLandscape' in s, 'orientation patch failed'
open(p, 'w', encoding='utf-8').write(s)
print(s)

# ---------- 2. Dark launch screen (no white/grey square) ----------
RES = 'android/app/src/main/res'


def w(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    open(path, 'w', encoding='utf-8').write(text)


LAYER = '''<?xml version="1.0" encoding="utf-8"?>
<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item>
        <shape android:shape="rectangle">
            <solid android:color="#0B0B12"/>
        </shape>
    </item>
</layer-list>
'''
for d in ['drawable', 'drawable-v21']:
    w(f'{RES}/{d}/launch_background.xml', LAYER)

BASE = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
</resources>
'''
V31 = '''<?xml version="1.0" encoding="utf-8"?>
<resources>
    <style name="LaunchTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
        <item name="android:windowSplashScreenBackground">#0B0B12</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_icon</item>
    </style>
    <style name="NormalTheme" parent="@android:style/Theme.Black.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_background</item>
    </style>
</resources>
'''
w(f'{RES}/values/styles.xml', BASE)
w(f'{RES}/values-night/styles.xml', BASE)
w(f'{RES}/values-v31/styles.xml', V31)
w(f'{RES}/values-night-v31/styles.xml', V31)
os.makedirs(f'{RES}/drawable', exist_ok=True)
shutil.copy('tv/splash_icon.png', f'{RES}/drawable/splash_icon.png')

# ---------- 3. MainActivity (volume, brightness, TV, PiP, external player) ----------
KOTLIN = '''
import android.annotation.SuppressLint
import android.app.PictureInPictureParams
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.content.res.Configuration
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.Rational
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    @SuppressLint("NewApi")
    override fun onPictureInPictureModeChanged(isInPictureInPictureMode: Boolean, newConfig: Configuration) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        channel?.invokeMethod("pip", isInPictureInPictureMode)
    }

    @SuppressLint("NewApi")
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val ch = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "streamivo/native")
        channel = ch
        ch.setMethodCallHandler { call, result ->
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
                "cacheDir" -> {
                    result.success(cacheDir.absolutePath)
                }
                "isTv" -> {
                    val ui = getSystemService(Context.UI_MODE_SERVICE) as UiModeManager
                    val tv = ui.currentModeType == Configuration.UI_MODE_TYPE_TELEVISION ||
                        packageManager.hasSystemFeature("android.software.leanback") ||
                        packageManager.hasSystemFeature("android.hardware.type.television")
                    result.success(tv)
                }
                "enterPip" -> {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                        try {
                            enterPictureInPictureMode(
                                PictureInPictureParams.Builder().setAspectRatio(Rational(16, 9)).build()
                            )
                            result.success(true)
                        } catch (e: Exception) {
                            result.success(false)
                        }
                    } else {
                        result.success(false)
                    }
                }
                "openExternal" -> {
                    val url = call.argument<String>("url") ?: ""
                    val title = call.argument<String>("title") ?: ""
                    val pkg = call.argument<String>("pkg")
                    try {
                        val i = Intent(Intent.ACTION_VIEW)
                        i.setDataAndType(Uri.parse(url), "video/*")
                        i.putExtra("title", title)
                        if (!pkg.isNullOrEmpty()) {
                            i.setPackage(pkg)
                        }
                        startActivity(i)
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
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
