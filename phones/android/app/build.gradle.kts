plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

// Everything a build may change comes in as -P<name>=<value> (scripts-phones/ passes them from
// scripts-phones/phones.env); the defaults are the live site.
fun prop(name: String, fallback: String): String = (project.findProperty(name) as String?) ?: fallback

android {
    namespace = "blog.parshwa.rysteria"
    compileSdk = 36

    defaultConfig {
        applicationId = prop("appId", "blog.parshwa.rysteria")
        minSdk = 24
        targetSdk = 36 // Google Play takes new apps and updates only at API 36 or higher since 31 August 2026
        versionCode = prop("versionCode", "1").toInt()
        versionName = prop("versionName", "1.0")
        // the site the app shows, and the host of the master (login). Change both
        // here to point the app at another deployment
        buildConfigField("String", "GAME_URL", "\"${prop("gameUrl", "https://game.parshwa.blog/")}\"")
        buildConfigField("String", "API_HOST", "\"${prop("apiHost", "api-game.parshwa.blog")}\"")
    }

    buildFeatures {
        buildConfig = true
    }

    // a release is signed when ANDROID_KEYSTORE is set (scripts-phones/android-deploy.sh does that);
    // the passwords only ever come from the environment
    val keystore: String? = System.getenv("ANDROID_KEYSTORE")
    signingConfigs {
        if (keystore != null) {
            create("release") {
                storeFile = file(keystore)
                storePassword = System.getenv("ANDROID_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("ANDROID_KEY_ALIAS")
                keyPassword = System.getenv("ANDROID_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = false
            if (keystore != null) signingConfig = signingConfigs.getByName("release")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
    // Google does not allow sign in inside a WebView: that goes to a Custom Tab
    implementation("androidx.browser:browser:1.8.0")
}
