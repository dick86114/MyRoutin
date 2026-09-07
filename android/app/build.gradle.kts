plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "ai.routin.mytoken"
    compileSdk = 34

    defaultConfig {
        applicationId = "ai.routin.mytoken"
        minSdk = 29
        targetSdk = 34
        versionCode = 1
        versionName = "0.1.0"
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

    buildFeatures {
        compose = true
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":data"))
    implementation(project(":domain"))
    implementation(project(":provider"))
    implementation(project(":feature-home"))
    implementation(project(":feature-credentials"))
    implementation(project(":feature-settings"))
    implementation(project(":feature-transfer"))

    implementation("androidx.room:room-runtime:2.6.1")
    implementation(project(":feature-home"))
    implementation(project(":feature-credentials"))
    implementation(project(":feature-settings"))
    implementation(project(":feature-transfer"))

    implementation("androidx.room:room-runtime:2.6.1")

    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.6")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation(platform("androidx.compose:compose-bom:2024.09.03"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")

    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.13")
    testImplementation("androidx.test:core-ktx:1.6.1")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.compose.ui:ui-test-manifest")
    testImplementation("androidx.compose.ui:ui-test-junit4")
    testImplementation("androidx.compose.ui:ui-test-manifest")

    androidTestImplementation(project(":feature-transfer"))
    androidTestImplementation(project(":core"))
    androidTestImplementation(project(":domain"))
    androidTestImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.9.0")
    androidTestImplementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")
}
