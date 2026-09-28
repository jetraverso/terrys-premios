#!/bin/zsh
# Exporta el flyer a PDF (para imprenta) y PNG (para mandar por WhatsApp/redes).
# Uso: ./exportar.sh   → genera terrys-flyer-A6.pdf y terrys-flyer-A6.png en esta carpeta
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="file://$PWD/flyer.html?exportar"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=8000 \
  --print-to-pdf="$PWD/terrys-flyer-A6.pdf" "$URL" 2>/dev/null
# 105 × 148 mm a 300 ppp = 1240 × 1748 px
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=8000 \
  --window-size=397,560 --force-device-scale-factor=3.1236 \
  --screenshot="$PWD/terrys-flyer-A6.png" "$URL" 2>/dev/null
ls -la terrys-flyer-A6.*
