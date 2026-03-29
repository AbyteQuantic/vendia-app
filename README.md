# VendIA App

Aplicación móvil POS para tenderos colombianos. Diseño orientado a adultos mayores (Gerontodiseño).

## Tech Stack

- **Flutter 3.3+** (Dart)
- **Dio** (HTTP client)
- **Provider** (estado)
- **Isar** (base de datos local offline-first)
- **flutter_dotenv** (variables de entorno)

## Setup Local

```bash
cp .env.example .env   # Configurar API_BASE_URL
flutter pub get
flutter run
```

## Variables de Entorno

| Variable | Descripción |
|---|---|
| `API_BASE_URL` | URL del backend (ej: `http://192.168.1.98:8089/api/v1`) |

## Build APK

```bash
flutter build apk --release
```

El APK se genera en `build/app/outputs/flutter-apk/app-release.apk`.
