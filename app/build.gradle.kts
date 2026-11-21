plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.mobilvm.app"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.mobilvm.app"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "0.1"
        // QEMU ikilileri sadece arm64 için paketleniyor (telefonların neredeyse hepsi)
        ndk { abiFilters += listOf("arm64-v8a") }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            // Kendi imza anahtarını ekleyene kadar debug anahtarıyla imzala
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }

    packaging {
        // ÖNEMLİ: .so dosyaları kuruluşta nativeLibraryDir'e çıkarılsın.
        // Android 10+ uygulama klasöründen exec() yasak; QEMU'yu oradan çalıştırıyoruz.
        jniLibs { useLegacyPackaging = true }
    }
}
