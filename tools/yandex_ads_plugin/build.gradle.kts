// Сборка Android-плагина GodotAndroidYandexAds под Yandex Mobile Ads SDK 8.x
// и Godot 4.7 (08.10.2026). Результат — AAR, который кладётся в
// addons/GodotAndroidYandexAds/bin/{debug,release}/ (см. build_plugin.ps1).
// Обе зависимости compileOnly: в APK библиотеку Godot даёт сам экспорт, а
// SDK Яндекса подтягивает export_plugin.gd (_get_android_dependencies).
plugins {
    // Та же версия AGP, что у шаблона Godot 4.3 (есть в кэше gradle) — плагину
    // хватает compileSdk 34, новый AGP не нужен.
    id("com.android.library") version "8.2.0"
}

val pluginName = "GodotAndroidYandexAds"
val pluginPackageName = "com.darkmoonight.godotandroidyandexads"
val yandexSdkVersion: String by project   // из gradle.properties
val godotVersion: String by project

android {
    namespace = pluginPackageName
    compileSdk = (project.findProperty("compileSdkVersion") as String).toInt()

    defaultConfig {
        minSdk = 24
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildTypes {
        release {
            isMinifyEnabled = false
        }
    }
}

dependencies {
    compileOnly("org.godotengine:godot:$godotVersion")
    compileOnly("com.yandex.android:mobileads:$yandexSdkVersion")
    compileOnly("androidx.annotation:annotation:1.5.0")
}
