import re

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
s = re.sub(
    r'(<category android:name="android.intent.category.LAUNCHER"\s*/>)',
    r'\1\n                <category android:name="android.intent.category.LEANBACK_LAUNCHER"/>',
    s,
    count=1,
)
s = re.sub(r'android:label="[^"]*"', 'android:label="Streamivo"', s)

assert 'LEANBACK_LAUNCHER' in s, 'LEANBACK_LAUNCHER patch failed'
assert 'android:banner' in s, 'banner patch failed'
open(p, 'w', encoding='utf-8').write(s)
print(s)
