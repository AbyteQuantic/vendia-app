# Publicar VendIA en las tiendas (Android + iOS)

Guía **paso a paso** para el fundador. Está pensada para abrirse dentro de dos
meses sin recordar nada y lograr publicar sin trabarse. Asume que sabe
programar, pero **no** que haya publicado antes en Google Play o App Store.

La configuración del repositorio **ya quedó lista** (firma de release Android,
HTTPS forzado, andamiaje de App Store — ver el resumen al final). Aquí van
**solo los pasos que debe ejecutar usted con sus propias credenciales**, con
cada comando listo para copiar y pegar.

> **¿Por qué la app salía como "no confiable"?**
> Hasta ahora el APK se firmaba con la llave **debug** de Flutter (una llave
> genérica, compartida por todos los proyectos del mundo). Android marca esos
> APK como no confiables y las tiendas los rechazan. Al firmar con **su propio
> keystore de release**, la app queda firmada a su nombre y desaparece la
> advertencia.
>
> **Las impresoras NO se ven afectadas por forzar HTTPS:** hablan por socket
> TCP crudo al puerto **9100** (protocolo ESC/POS, no HTTP), así que el cambio
> de red no las toca.

---

## Índice

- [0. Requisitos previos y costos](#0-requisitos-previos-y-costos)
- [1. Generar el keystore de Android (una sola vez)](#1-generar-el-keystore-de-android-una-sola-vez)
- [2. Configurar `android/key.properties`](#2-configurar-androidkeyproperties)
- [3. Compilar para Google Play](#3-compilar-para-google-play)
- [4. Publicar en Google Play Console](#4-publicar-en-google-play-console)
- [5. Compilar para App Store (requiere Mac)](#5-compilar-para-app-store-requiere-mac)
- [6. Publicar en App Store Connect](#6-publicar-en-app-store-connect)
- [7. Checklist de ficha de tienda](#7-checklist-de-ficha-de-tienda)
- [8. Solución de problemas comunes](#8-solución-de-problemas-comunes)
- [Resumen de lo que ya dejó listo el repo](#resumen-de-lo-que-ya-dejó-listo-el-repo)

---

## 0. Requisitos previos y costos

| Qué | Costo | Notas |
|-----|-------|-------|
| **Google Play Console** | **USD 25**, pago **único** | Cuenta de desarrollador de Android. |
| **Apple Developer Program** | **USD 99 al año** | Necesaria para publicar en App Store. |
| **Mac con Xcode** | — | **Obligatorio** para compilar y subir la versión iOS. Android se puede compilar desde cualquier sistema. |
| **Flutter instalado** | gratis | Verifique con `flutter doctor`. |

**Identificadores de la app (ya configurados, no los cambie):**

- Android `applicationId`: **`com.vendia.vendia_pos`**
- iOS bundle id: **`com.vendia.vendiaPos`** — Team ID **`4534FQ59N9`**

**Valores que necesitará en los comandos de build (dart-defines):**

- `API_BASE_URL=https://api.vendia.store` (fijo)
- `SUPPORT_WHATSAPP_NUMBER=<número de soporte en formato internacional, sin el `+`>`
  — el mismo valor que el secret `SUPPORT_WHATSAPP_NUMBER` que usa el deploy web
  (`.github/workflows/deploy-web.yml`). Ejemplo: `573001234567`.

> **Glosario rápido** (se explica cada término la primera vez que aparece):
> - **keystore**: archivo `.jks` con su llave privada para firmar la app.
> - **upload key vs app signing key**: usted firma con la *upload key*; Google
>   re-firma con la *app signing key* que guarda por usted (Play App Signing).
> - **`.aab` vs `.apk`**: el `.aab` (Android App Bundle) es lo que se **sube a
>   Play**; el `.apk` es lo que se **instala directo** en un teléfono.
> - **provisioning profile** (iOS): perfil que autoriza a su cuenta a firmar la
>   app. Con firma automática, Xcode lo gestiona por usted.

---

## 1. Generar el keystore de Android (una sola vez)

Un **keystore** es el archivo que contiene su llave privada para firmar la app.
Se genera **una sola vez** y se reutiliza para todas las actualizaciones.

Ejecute (desde cualquier carpeta; aquí lo guardamos en su *home*, **fuera del
repositorio**):

```bash
keytool -genkey -v -keystore ~/vendia-upload.jks -keyalg RSA -keysize 2048 -validity 10000 -alias vendia
```

**Qué debe pasar:** `keytool` le pedirá (en este orden):
1. Una **contraseña** para el keystore (escríbala dos veces).
2. Nombre, organización, ciudad, país, etc. (puede poner datos reales de VendIA).
3. Confirmar con `yes`.
4. Opcionalmente una contraseña para la llave (`alias`): pulse Enter para
   reutilizar la del keystore (lo más simple).

**Archivo generado:** `~/vendia-upload.jks` (o sea `/Users/admin/vendia-upload.jks`).

> ⚠️ **CRÍTICO — si pierde este archivo o su contraseña, NO podrá volver a
> publicar actualizaciones de la app nunca más** (Google solo acepta
> actualizaciones firmadas con la misma llave). Por eso:
> - Guarde el `.jks` **y** su contraseña en un **gestor de contraseñas** o
>   bóveda cifrada (1Password, Bitwarden, etc.).
> - Haga al menos **una copia de seguridad** del `.jks` en otro lugar seguro.
> - El `.jks` y `key.properties` **JAMÁS se suben a git** — ya están en
>   `.gitignore` (`android/.gitignore`: `key.properties`, `**/*.keystore`,
>   `**/*.jks`). No los saque de ahí.

---

## 2. Configurar `android/key.properties`

Este archivo le dice a Gradle dónde está su keystore y con qué contraseñas
abrirlo. El repo ya trae una plantilla.

Desde la raíz del proyecto:

```bash
cd /Users/admin/Documents/VendIA/frontend
cp android/key.properties.example android/key.properties
```

**Qué debe pasar:** se crea `android/key.properties` (ignorado por git).

Ábralo y rellene sus valores reales:

```properties
storePassword=SU_CONTRASENA_DEL_KEYSTORE
keyPassword=SU_CONTRASENA_DE_LA_LLAVE
keyAlias=vendia
storeFile=/Users/admin/vendia-upload.jks
```

- Si en el paso 1 pulsó Enter para reutilizar la contraseña, `keyPassword` y
  `storePassword` son **iguales**.
- `storeFile` debe ser la **ruta absoluta** al `.jks`.

> **Cómo sabe el build que debe usarlo:** `android/app/build.gradle.kts` detecta
> `key.properties` automáticamente. Si el archivo **existe**, firma el release
> con su keystore. Si **no existe** (CI web, `flutter run`, otra máquina), cae a
> la firma debug para no romper el build. Por eso publicar solo depende de este
> archivo local.

---

## 3. Compilar para Google Play

Un **App Bundle** (`.aab`) es el formato que se sube a Play; Google genera desde
él los APK optimizados para cada dispositivo.

Desde la raíz del proyecto:

```bash
cd /Users/admin/Documents/VendIA/frontend
flutter build appbundle --release \
  --dart-define=API_BASE_URL=https://api.vendia.store \
  --dart-define=SUPPORT_WHATSAPP_NUMBER=<NUMERO_SOPORTE>
```

**Qué debe pasar:** compila varios minutos y termina con
`✓ Built build/app/outputs/bundle/release/app-release.aab`.

**Archivo generado:** `build/app/outputs/bundle/release/app-release.aab` ← este
es el que sube a Play.

---

Si además quiere un **APK** para instalar directo en un teléfono (repartir por
fuera de la tienda), genere uno por arquitectura (`--split-per-abi` produce APK
más livianos):

```bash
cd /Users/admin/Documents/VendIA/frontend
flutter build apk --release --split-per-abi \
  --dart-define=API_BASE_URL=https://api.vendia.store \
  --dart-define=SUPPORT_WHATSAPP_NUMBER=<NUMERO_SOPORTE>
```

**Archivos generados:** en `build/app/outputs/flutter-apk/`, típicamente
`app-armeabi-v7a-release.apk`, `app-arm64-v8a-release.apk` y
`app-x86_64-release.apk`. Para un teléfono moderno reparta el `arm64-v8a`.

> Reemplace `<NUMERO_SOPORTE>` por el número real (mismo valor del secret
> `SUPPORT_WHATSAPP_NUMBER`, formato internacional sin `+`, ej. `573001234567`).

---

## 4. Publicar en Google Play Console

1. Cree su cuenta de desarrollador (**USD 25**, pago único):
   https://play.google.com/console/signup
2. **Create app**: nombre "VendIA", idioma por defecto español, tipo *App*,
   gratuita.
3. En **Producción** (o **Testing → Prueba interna** para empezar sin revisión
   pública) cree un *release* y **suba** el archivo
   `build/app/outputs/bundle/release/app-release.aab`.
4. Cuando Play lo ofrezca, **active Play App Signing** (recomendado): usted
   conserva solo la *upload key* y Google guarda la *app signing key*. Ventaja:
   si algún día pierde su upload keystore, Google puede ayudarle a recuperar la
   capacidad de publicar.
5. Complete la ficha de la tienda (ver [sección 7](#7-checklist-de-ficha-de-tienda))
   y envíe a revisión.

---

## 5. Compilar para App Store (requiere Mac)

**Requisitos:** un **Mac con Xcode**, cuenta **Apple Developer** activa (USD
99/año) y el bundle **`com.vendia.vendiaPos`** registrado en su cuenta (Team ID
`4534FQ59N9`). El repo ya trae `ios/ExportOptions.plist` con firma **automática**
(Xcode gestiona certificados y provisioning profile por usted).

Desde la raíz del proyecto, en el Mac:

```bash
cd /Users/admin/Documents/VendIA/frontend
flutter build ipa --export-options-plist=ios/ExportOptions.plist \
  --dart-define=API_BASE_URL=https://api.vendia.store \
  --dart-define=SUPPORT_WHATSAPP_NUMBER=<NUMERO_SOPORTE>
```

**Qué debe pasar:** compila y genera el **IPA** (el instalable de iOS).

**Archivo generado:** `build/ios/ipa/*.ipa`.

> Si es la primera vez, quizá deba abrir `ios/Runner.xcworkspace` en Xcode una
> vez, iniciar sesión con su Apple ID en **Xcode → Settings → Accounts** y dejar
> que Xcode registre el bundle y cree el provisioning profile automáticamente.

---

## 6. Publicar en App Store Connect

1. Suba el IPA con una de estas dos vías:
   - **Transporter** (app gratis en la Mac App Store): arrastre el `.ipa`.
   - **Xcode → Organizer → Distribute App**.
2. Entre a https://appstoreconnect.apple.com, cree la app (bundle
   `com.vendia.vendiaPos`), y complete la ficha.
3. Rellene las **Privacy Nutrition Labels** (qué datos recolecta la app) y la
   clasificación de contenido.
4. Envíe a revisión de Apple.

---

## 7. Checklist de ficha de tienda

Vale para Play y App Store salvo donde se indique:

- [ ] **Ícono** en alta resolución (Play 512×512; App Store 1024×1024).
- [ ] **Screenshots** de teléfono en varios tamaños (y tablet si aplica).
- [ ] **Política de privacidad** publicada en una **URL pública** (obligatoria
      en ambas tiendas) y enlazada en la ficha.
- [ ] **Descripción** corta y larga en español.
- [ ] **Categoría** (Negocios / Productividad) y datos de contacto de soporte.
- [ ] **Clasificación de contenido** (cuestionario de cada tienda).
- [ ] iOS: **Privacy Nutrition Labels** completadas.

---

## 8. Solución de problemas comunes

| Síntoma / error | Causa probable | Solución |
|-----------------|----------------|----------|
| `Keystore file '...jks' not found` al compilar | La ruta `storeFile` en `key.properties` está mal, o movió el `.jks`. | Ponga la **ruta absoluta** correcta al `.jks` en `android/key.properties`. |
| `Keystore was tampered with, or password was incorrect` | `storePassword`/`keyPassword` no coinciden con las del keystore. | Corrija las contraseñas. Si reutilizó la del keystore, ambas son iguales. |
| El build de release NO pide keystore y sale firmado en debug | No existe `android/key.properties`. | Complete el [paso 2](#2-configurar-androidkeyproperties). Un `.aab`/`.apk` en debug **no** se acepta en tiendas. |
| Play: *"Version code N has already been used"* | Subió un `.aab` con un `versionCode` ya usado. | Suba el número de build en `pubspec.yaml` (la parte tras el `+`, ej. `1.2.0+5` → `1.2.0+6`) y recompile. |
| Play/Apple: *"bundle id / package already registered"* | El identificador ya existe en otra cuenta o app. | Use la cuenta correcta; no cambie `com.vendia.vendia_pos` / `com.vendia.vendiaPos`. |
| Play rechaza el release por **screenshots/política de privacidad faltantes** | Ficha incompleta. | Complete el [checklist](#7-checklist-de-ficha-de-tienda) antes de enviar a revisión. |
| iOS: *"No profiles for 'com.vendia.vendiaPos' were found"* | El bundle no está registrado o Xcode no tiene su cuenta. | Inicie sesión en Xcode (Settings → Accounts) y deje que la firma automática cree el profile; verifique el Team `4534FQ59N9`. |
| `flutter build ipa` falla en Linux/Windows | iOS solo compila en macOS. | Use un **Mac con Xcode**. |
| La app instalada no llega al backend | Faltó pasar `--dart-define=API_BASE_URL=...` al compilar. | Recompile con **todos** los dart-defines de las secciones 3/5. |

---

## Resumen de lo que ya dejó listo el repo

No necesita tocar nada de esto; solo se documenta para su referencia:

- **`android/app/build.gradle.kts`** — carga `android/key.properties` si existe
  y firma el release con ese keystore; si no existe, cae a firma debug para no
  romper `flutter run` ni el CI web. `minify/shrinkResources` quedan en `false`
  a propósito (activar R8 exige probar reglas ProGuard para los plugins basados
  en reflexión; es una optimización futura, no bloquea publicar).
- **`android/key.properties.example`** — plantilla del [paso 2](#2-configurar-androidkeyproperties).
- **`android/app/src/main/AndroidManifest.xml`** — se eliminó
  `android:usesCleartextTraffic="true"`. Ahora manda
  `res/xml/network_security_config.xml`, que permite HTTP solo a la red local de
  desarrollo (emulador `10.0.2.2` y LAN `192.168.0.0/16`) y **bloquea cleartext
  para todo lo demás**. Producción ya es HTTPS (`api.vendia.store`). Las
  impresoras (TCP 9100, no HTTP) no se ven afectadas.
- **`ios/ExportOptions.plist`** — opciones de exportación para App Store:
  `method=app-store`, Team `4534FQ59N9`, firma automática, `uploadSymbols=true`,
  `uploadBitcode=false`.
