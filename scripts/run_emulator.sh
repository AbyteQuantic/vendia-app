#!/usr/bin/env bash
# ══════════════════════════════════════════════════════════════════════════════
# VendIA POS — Limpia, levanta Docker y corre en emulador Android
# ══════════════════════════════════════════════════════════════════════════════
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FRONTEND_DIR="$(dirname "$SCRIPT_DIR")"
PROJECT_ROOT="$(dirname "$FRONTEND_DIR")"
COMPOSE_FILE="$PROJECT_ROOT/docker-compose.yml"
EMULATOR_ID="Pixel_API_35"

# ── Colores ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[INFO]${NC}  $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; }

# ── 1. Matar procesos Flutter/Gradle que hayan quedado colgados ─────────────
info "Matando procesos Flutter/Gradle anteriores..."
pkill -f "flutter_tools" 2>/dev/null || true
pkill -f "gradlew"       2>/dev/null || true
pkill -f "dart.*flutter"  2>/dev/null || true

# ── 2. Limpiar temporales de construccion Android ────────────────────────────
info "Limpiando temporales de build Android..."

cd "$FRONTEND_DIR"

# Flutter clean
flutter clean
info "flutter clean completado."

# Borrar caches de Gradle
if [ -d "$FRONTEND_DIR/android/.gradle" ]; then
  rm -rf "$FRONTEND_DIR/android/.gradle"
  info "android/.gradle eliminado."
fi

if [ -d "$FRONTEND_DIR/build" ]; then
  rm -rf "$FRONTEND_DIR/build"
  info "build/ eliminado."
fi

if [ -d "$FRONTEND_DIR/android/app/build" ]; then
  rm -rf "$FRONTEND_DIR/android/app/build"
  info "android/app/build eliminado."
fi

# Limpiar Gradle wrapper cache del proyecto
if [ -d "$FRONTEND_DIR/android/build" ]; then
  rm -rf "$FRONTEND_DIR/android/build"
  info "android/build eliminado."
fi

# ── 3. Reinstalar dependencias ───────────────────────────────────────────────
info "Obteniendo dependencias Dart..."
flutter pub get

# ── 4. Validar y levantar Docker (backend + admin-web) ──────────────────────
info "Verificando servicios Docker..."

if ! command -v docker &>/dev/null; then
  error "Docker no esta instalado. Instala Docker Desktop primero."
  exit 1
fi

if ! docker info &>/dev/null; then
  error "Docker daemon no esta corriendo. Abre Docker Desktop."
  exit 1
fi

ensure_service_running() {
  local service="$1"
  local container="$2"

  # Verificar si el contenedor existe y esta corriendo
  local state
  state=$(docker container inspect -f '{{.State.Status}}' "$container" 2>/dev/null || echo "not_found")

  if [ "$state" = "running" ]; then
    info "$service ya esta corriendo."
  else
    warn "$service no esta corriendo (estado: $state). Levantando..."
    docker compose -f "$COMPOSE_FILE" up -d "$service"
    info "$service levantado."
  fi
}

ensure_service_running "postgres"   "vendia_postgres"
ensure_service_running "backend"    "vendia_backend"
ensure_service_running "admin-web"  "vendia_admin_web"

# Esperar a que el backend este healthy
info "Esperando a que el backend este healthy..."
RETRIES=30
for i in $(seq 1 $RETRIES); do
  health=$(docker container inspect -f '{{.State.Health.Status}}' vendia_backend 2>/dev/null || echo "unknown")
  if [ "$health" = "healthy" ]; then
    info "Backend healthy."
    break
  fi
  if [ "$i" -eq "$RETRIES" ]; then
    warn "Backend no alcanzo estado healthy despues de ${RETRIES}s, continuando de todas formas..."
  fi
  sleep 1
done

# ── 5. Lanzar emulador Android y correr la app ──────────────────────────────
info "Lanzando emulador Android ($EMULATOR_ID)..."

# Usar adb para detectar emuladores reales (flutter devices puede dar falsos positivos)
if adb devices 2>/dev/null | grep -q "emulator"; then
  info "Ya hay un emulador Android corriendo."
else
  flutter emulators --launch "$EMULATOR_ID" &
  info "Esperando a que el emulador arranque..."
  sleep 20
fi

# Esperar a que el dispositivo este disponible via adb
RETRIES=40
for i in $(seq 1 $RETRIES); do
  if adb devices 2>/dev/null | grep -q "emulator.*device$"; then
    info "Dispositivo Android detectado via adb."
    break
  fi
  if [ "$i" -eq "$RETRIES" ]; then
    error "No se detecto dispositivo Android despues de ${RETRIES} intentos."
    error "Intenta abrir el emulador manualmente desde Android Studio."
    exit 1
  fi
  sleep 2
done

# Obtener el device id del emulador
DEVICE_ID=$(adb devices | grep "emulator" | awk '{print $1}')
info "Usando dispositivo: $DEVICE_ID"

# ── 6. Correr la app ────────────────────────────────────────────────────────
info "Corriendo VendIA POS en el emulador..."
flutter run -d "$DEVICE_ID"
