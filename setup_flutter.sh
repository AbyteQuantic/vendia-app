#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# VendIA Frontend — Setup inicial de Flutter
# Ejecutar UNA SOLA VEZ después de instalar el SDK de Flutter
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

FRONTEND_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$FRONTEND_DIR"

echo "📦 Generando archivos nativos (ios/, android/)..."
# --org y --project-name deben coincidir con pubspec.yaml
# NO sobreescribe archivos existentes en lib/
flutter create \
  --org com.vendia \
  --project-name vendia_pos \
  --platforms ios,android \
  .

echo ""
echo "📥 Descargando dependencias Dart..."
flutter pub get

echo ""
echo "🩺 Diagnóstico del entorno..."
flutter doctor -v

echo ""
echo "✅ Setup completo. Próximos pasos:"
echo "   1. Abrir iOS Simulator: open -a Simulator"
echo "   2. Correr la app:       flutter run"
echo "   3. Para ver todos los   flutter run -d <device_id>"
echo "      devices disponibles: flutter devices"
