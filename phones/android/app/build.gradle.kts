plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "blog.parshwa.rysteria"
    compileSdk = 34

    defaultConfig {
        applicationId = "blog.parshwa.rysteria"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0"
        // the site the app shows, and the host of the master (login). Change both
        // here to point the app at another deployment
        buildConfigField("String", "GAME_URL", "\"https://game.parshwa.blog/\"")
        buildConfigField("String", "API_HOST", "\"api-game.parshwa.blog\"")
    }

    buildFeatures {
        buildConfig = true
    }

    buildTypes {
        release {
            isMinifyEnabled = false
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
