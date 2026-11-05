#!/usr/bin/env bash
# Gera as pastas android/, windows/ e web/ e aplica os ajustes do projeto.
# Usado pelo GitHub Actions e também localmente (Linux, macOS ou Git Bash no Windows):
#   cd app && bash tool/setup_platforms.sh
# Desenvolvido por Edivaldo.Nascimento - IaHope-Technology
set -euo pipefail
cd "$(dirname "$0")/.."

flutter create --platforms=android,windows,web --org br.com.iahope --project-name iahope_gestao . >/dev/null
rm -f test/widget_test.dart   # o modelo padrão do Flutter não se aplica a este app

MANIFEST=android/app/src/main/AndroidManifest.xml
if ! grep -q 'android.permission.CAMERA' "$MANIFEST"; then
  # permissões: internet (API) e câmera (leitor de código de barras no PDV)
  sed -i.bak '0,/<manifest[^>]*>/s//&\n    <uses-permission android:name="android.permission.INTERNET"\/>\n    <uses-permission android:name="android.permission.CAMERA"\/>/' "$MANIFEST"
  # nome amigável no ícone
  sed -i.bak 's/android:label="iahope_gestao"/android:label="IaHope Gestão"/' "$MANIFEST"
  rm -f "$MANIFEST.bak"
fi
# abrir links (WhatsApp) no Android 11+: declara o intent https
if ! grep -q 'android:scheme="https"' "$MANIFEST"; then
  if grep -q '<queries>' "$MANIFEST"; then
    sed -i.bak 's#<queries>#<queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n            <data android:scheme="https"/>\n        </intent>#' "$MANIFEST"
  else
    sed -i.bak 's#</manifest>#    <queries>\n        <intent>\n            <action android:name="android.intent.action.VIEW"/>\n            <data android:scheme="https"/>\n        </intent>\n    </queries>\n</manifest>#' "$MANIFEST"
  fi
  rm -f "$MANIFEST.bak"
fi

# Android 7.0+ (SDK 24): exigido pelo leitor de código por câmera (mobile_scanner 7)
for G in android/app/build.gradle.kts android/app/build.gradle; do
  if [ -f "$G" ]; then
    sed -i.bak -E 's/minSdk( =|Version) flutter\.minSdkVersion/minSdk\1 24/' "$G" && rm -f "$G.bak"
  fi
done

# título da aba no navegador
if [ -f web/index.html ]; then
  sed -i.bak 's#<title>.*</title>#<title>IaHope Gestão — Edivaldo.Nascimento - IaHope-Technology</title>#' web/index.html && rm -f web/index.html.bak
fi
echo "Plataformas prontas (android, windows, web)."
