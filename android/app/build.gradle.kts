import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android Gradle plugin.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "app.cogwheel.conduit"
    compileSdk = 37
    ndkVersion = "29.0.14206865"

    defaultConfig {
    applicationId = "app.cogwheel.conduit"
    minSdk = flutter.minSdkVersion
    targetSdk = flutter.targetSdkVersion
    versionCode = flutter.versionCode
    versionName = flutter.versionName
    }

    compileOptions {
        // Align with modern Android Gradle Plugin requirements
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Enable core library desugaring for flutter_local_notifications
        isCoreLibraryDesugaringEnabled = true
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        getByName("release") {
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            // signingConfig = signingConfigs.getByName("debug")
            applicationIdSuffix = ".debug"
        }
        // Flutter creates "profile" from debug before this block runs, so it
        // misses the suffix. Matching it lets a profile build (AOT, the real
        // frame rate) install over the debug app and keep its sign-in.
        getByName("profile") {
            applicationIdSuffix = ".debug"
        }
    }
}

kotlin {
    compilerOptions {
        // Generate JVM bytecode targeting Java 17.
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

// The UnifiedPush connector depends on com.google.crypto.tink:tink (the JVM jar)
// while ML Kit / other libraries bring tink-android at the same version. Both
// carry the same classes, which fails the duplicate-class check, so keep only
// the Android artifact.
configurations.configureEach {
    exclude(group = "com.google.crypto.tink", module = "tink")
}

dependencies {
    implementation("androidx.work:work-runtime-ktx:2.11.2")
    // UnifiedPush connector (Kotlin). Receives pushes natively, with no Flutter engine.
    implementation("org.unifiedpush.android:connector:3.3.5")
    // Core library desugaring for flutter_local_notifications
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.activity:activity:1.12.4")
    implementation("com.google.mlkit:genai-speech-recognition:1.0.0-alpha1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    testImplementation("junit:junit:4.13.2")
    // Real org.json for JVM unit tests; the mockable android.jar only stubs it.
    testImplementation("org.json:json:20240303")
}

flutter {
    source = "../.."
}
