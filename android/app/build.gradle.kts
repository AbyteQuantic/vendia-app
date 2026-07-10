import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Firma de release (patrón oficial de Flutter).
// Carga android/key.properties SI existe. Ese archivo está en .gitignore y
// contiene las credenciales del upload keystore del fundador — nunca se sube a
// git. Si NO existe (CI web, `flutter run`, cualquiera sin el keystore), el
// release cae a la firma debug (ver buildTypes.release abajo) para no romper el
// build. Instrucciones para el fundador: ver frontend/RELEASE.md.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.vendia.vendia_pos"
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Requerido por flutter_local_notifications (y otras libs Java 8+).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.vendia.vendia_pos"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        // Config de firma del upload keystore. Solo queda "armada" si
        // key.properties existe; sus valores los pone el fundador (RELEASE.md).
        create("release") {
            val storeFilePath = keystoreProperties["storeFile"] as String?
            if (storeFilePath != null) {
                storeFile = file(storeFilePath)
                storePassword = keystoreProperties["storePassword"] as String?
                keyAlias = keystoreProperties["keyAlias"] as String?
                keyPassword = keystoreProperties["keyPassword"] as String?
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                // Firma real de Play/App Store con el keystore del fundador.
                signingConfigs.getByName("release")
            } else {
                // FALLBACK: sin key.properties (CI web, `flutter run --release`,
                // quien no tiene el keystore) se firma con las llaves debug para
                // que el build no se rompa. Un APK/AAB firmado en debug NO se
                // puede publicar en tiendas ni se considera "de confianza".
                signingConfigs.getByName("debug")
            }

            // minify/shrink deshabilitados a propósito: Flutter + varios plugins
            // basados en reflexión (flutter_dynamic_icon_plus, image_cropper/uCrop,
            // flutter_local_notifications, listener de notificaciones, USB/BLE)
            // pueden necesitar reglas ProGuard específicas. Prioridad = que firme
            // y publique sin romperse; activar R8 es una optimización futura que
            // exige probar un build release completo con reglas proguard.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
