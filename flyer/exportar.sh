#!/bin/zsh
# Exporta el flyer a PDF (para imprenta) y PNG (para mandar por WhatsApp/redes).
# Uso: ./exportar.sh   → genera el flyer de las bolsas (terrys-flyer-A6) y el folleto para repartir (terrys-folleto-A6), en PDF y PNG
cd "$(dirname "$0")"
CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
URL="file://$PWD/flyer.html?exportar"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=8000 \
  --print-to-pdf="$PWD/terrys-flyer-A6.pdf" "$URL" 2>/dev/null
# 105 × 148 mm a 300 ppp = 1240 × 1748 px
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=8000 \
  --window-size=397,560 --force-device-scale-factor=3.1236 \
  --screenshot="$PWD/terrys-flyer-A6.png" "$URL" 2>/dev/null
# El folleto para repartir (3 tiros de regalo, QR con ?o=folleto)
URL2="file://$PWD/folleto.html?exportar"
"$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=8000 \
  --print-to-pdf="$PWD/terrys-folleto-A6.pdf" "$URL2" 2>/dev/null
"$CHROME" --headless=new --disable-gpu --hide-scrollbars --virtual-time-budget=8000 \
  --window-size=397,560 --force-device-scale-factor=3.1236 \
  --screenshot="$PWD/terrys-folleto-A6.png" "$URL2" 2>/dev/null
# Hojas A4 con 4 de cada uno, para imprenta o impresora común
for f in folleto flyer; do
  "$CHROME" --headless=new --disable-gpu --no-pdf-header-footer --virtual-time-budget=12000 \
    --print-to-pdf="$PWD/terrys-$f-A4-x4.pdf" "file://$PWD/hoja-a4.html?f=$f&exportar" 2>/dev/null
done
ls -la terrys-flyer-A6.* terrys-folleto-A6.* terrys-*-A4-x4.pdf
