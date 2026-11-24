import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties: Properties? =
    if (keyPropertiesFile.exists()) {
        Properties().apply { keyPropertiesFile.inputStream().use { load(it) } }
    } else {
        null
    }

android {
    // 이름에 chaerok이 남은 이유: 폰에 이미 깔린 '성공습관' 위에 덮어 설치해 계획이 남게(2026-11-21 사용자 결정). 바꾸면 새 앱으로 깔린다.
    namespace = "com.brad0329.chaerok.phone"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.brad0329.chaerok.phone"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // 릴리스 서명: app/android/key.properties(커밋 금지)가 가리키는 키로 한다.
    // 키는 이 PC의 디버그 키 사본이다(2026-11-24 사용자 결정) — 폰에 디버그 키로 깔린 앱 위에
    // 덮어 설치해 계획이 남게. 키가 달라지면 덮어 설치가 거부되고, 지우면 계획이 사라진다(백업 없음).
    signingConfigs {
        if (keyProperties != null) {
            create("release") {
                storeFile = file(keyProperties.getProperty("storeFile"))
                storePassword = keyProperties.getProperty("storePassword")
                keyAlias = keyProperties.getProperty("keyAlias")
                keyPassword = keyProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyProperties != null) signingConfigs.getByName("release") else null
        }
        debug {
            // 디버그 빌드도 같은 사본 키로 — PC를 바꾸거나 ~/.android가 새로 만들어져도 서명이 안 바뀌게.
            // key.properties가 없으면 Android 기본 디버그 키(이 PC에서는 같은 키)로 둔다.
            if (keyProperties != null) signingConfig = signingConfigs.getByName("release")
        }
    }
}

// fail-closed: key.properties가 없으면 릴리스 빌드를 거부한다 — 다른 키로 조용히 서명되면
// 받은 사람의 폰에서 덮어 설치가 안 된다. 디버그 빌드는 막지 않는다.
gradle.taskGraph.whenReady {
    val wantsRelease = allTasks.any { it.name.contains("Release") }
    if (wantsRelease && keyProperties == null) {
        throw GradleException(
            "app/android/key.properties가 없다 — 릴리스 서명 키 설정 필요(CLAUDE.md 배포 체크리스트)"
        )
    }
}

flutter {
    source = "../.."
}
