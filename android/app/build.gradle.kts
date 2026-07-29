import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val releaseSigningPropertiesPath =
    providers
        .gradleProperty("ccTraceSigningProperties")
        .orElse(providers.environmentVariable("CC_TRACE_MOBILE_ANDROID_SIGNING_PROPERTIES"))
        .orElse("${System.getProperty("user.home")}/.config/cc-trace-mobile/android-signing.properties")
        .get()
val releaseSigningPropertiesFile = file(releaseSigningPropertiesPath)
val releaseSigningProperties =
    Properties().apply {
        if (releaseSigningPropertiesFile.isFile) {
            releaseSigningPropertiesFile.inputStream().use(::load)
        }
    }

fun releaseSigningValue(
    propertyName: String,
    environmentName: String,
): String? =
    providers.environmentVariable(environmentName).orNull?.takeIf(String::isNotBlank)
        ?: releaseSigningProperties.getProperty(propertyName)?.takeIf(String::isNotBlank)

val releaseStoreFile =
    releaseSigningValue("storeFile", "CC_TRACE_MOBILE_ANDROID_STORE_FILE")
val releaseStorePassword =
    releaseSigningValue("storePassword", "CC_TRACE_MOBILE_ANDROID_STORE_PASSWORD")
val releaseKeyAlias =
    releaseSigningValue("keyAlias", "CC_TRACE_MOBILE_ANDROID_KEY_ALIAS")
val releaseKeyPassword =
    releaseSigningValue("keyPassword", "CC_TRACE_MOBILE_ANDROID_KEY_PASSWORD")
val releaseTaskRequested =
    gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }

if (releaseTaskRequested) {
    val missingSigningValues =
        listOf(
            "storeFile" to releaseStoreFile,
            "storePassword" to releaseStorePassword,
            "keyAlias" to releaseKeyAlias,
            "keyPassword" to releaseKeyPassword,
        ).filter { (_, value) -> value == null }

    check(releaseSigningPropertiesFile.isFile || missingSigningValues.isEmpty()) {
        "Android Release 签名配置不存在：$releaseSigningPropertiesPath"
    }
    check(missingSigningValues.isEmpty()) {
        "Android Release 签名配置缺少：" +
            missingSigningValues.joinToString { (name, _) -> name }
    }
}

android {
    namespace = "com.nanvon.cctrace.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.nanvon.cctrace.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            storeFile = releaseStoreFile?.let(::file)
            storePassword = releaseStorePassword
            keyAlias = releaseKeyAlias
            keyPassword = releaseKeyPassword
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }
}

dependencies {
    implementation("androidx.browser:browser:1.10.0")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
