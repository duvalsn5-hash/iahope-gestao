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

# título da aba no navegador
if [ -f web/index.html ]; then
  sed -i.bak 's#<title>.*</title>#<title>IaHope Gestão — Edivaldo.Nascimento - IaHope-Technology</title>#' web/index.html && rm -f web/index.html.bak
fi
echo "Plataformas prontas (android, windows, web)."
